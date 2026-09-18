//
//  BrowserSession.swift
//  Luna
//
//  The coordinator: one per window, and the single source of truth the whole
//  UI reads from (M1 wave-2 contract). It owns the Space list, the tab list,
//  the active selections and the `TabController`s, and it is the only object
//  that talks to both `BrowserStore` and the engine. Views own no model state;
//  they re-read this on `onChange`.
//
//  What it deliberately is not: Nook's `BrowserManager` (~4,000 lines). What
//  keeps it small (§0.3, §19, §33) is that navigation lives in `TabController`,
//  persistence in `BrowserStore`, ordering in `TabList`, geometry in
//  `BrowserWindowController` — and anything a *view* can compute from `tabs`
//  does not get a method here. It is four files:
//
//      BrowserSession.swift         state, restore, the Space list (§5)
//      BrowserSession+Spaces.swift  the Space lifecycle and Favorites (§6, §2)
//      BrowserSession+Tabs.swift    the tab API, navigation, persistence, undo
//      BrowserSession+Engine.swift  controllers, hibernation, WebKit callbacks
//
//  Two invariants everything depends on:
//    1. **`tabs` is sorted essential → pinned → today, each by `order`** — see
//       `TabList`. `reorderTab(_:to:kind:)` therefore takes a *section-relative*
//       index.
//    2. **A tab with no `TabController` has no `WKWebView` and no WebContent
//       process** (§19.2). Restoring a session creates no controllers at all
//       (§19.4); the first `activateTab` creates the first one.
//

import AppKit
import BrowserKit
import WebKit

/// A registration's lifetime. Hold it for as long as you want the callbacks;
/// releasing it unregisters, so a closed window's sidebar stops being called
/// without anyone having to remember to say so.
///
/// Not `@MainActor`: `deinit` is nonisolated, so the cancel closure hops back
/// to the main actor itself rather than the token pretending it is already
/// there.
final class ObservationToken: Sendable {
    private let cancel: @Sendable () -> Void

    init(_ cancel: @escaping @Sendable () -> Void) {
        self.cancel = cancel
    }

    deinit { cancel() }
}

@MainActor
final class BrowserSession {

    // MARK: - The contract surface

    /// The Space list, ordered. Written only by `BrowserSession+Spaces.swift`,
    /// which is why the setter is internal rather than `private(set)`: Swift's
    /// `private` is file-scoped and the coordinator is four files. Views read it
    /// and never assign, exactly as they never assign `list`.
    var spaces: [Space]

    private(set) var activeSpaceID: UUID {
        didSet { UserDefaults.standard.set(activeSpaceID.uuidString, forKey: Self.activeSpaceKey) }
    }

    /// Every tab in the active Space, ordered. Derived, so one tab is one value
    /// in one place no matter which Space it belongs to.
    var tabs: [Tab] { list[activeSpaceID] }

    /// nil straight after a restore: nothing is selected until the user picks a
    /// tab, and nothing selected means no web view anywhere (§19.4).
    var activeTabID: UUID? { activeTabBySpace[activeSpaceID] }

    /// Structural changes — the tab list, the Space list, the selection.
    ///
    /// **Register, do not assign.** The sidebar, the top bar and the app are
    /// all observers *at the same time* (both layouts stay alive across a
    /// switch), and a single `var` closure is last-writer-wins with no compile
    /// error and no crash to show for it. Hold the token for as long as you
    /// want the callbacks; releasing it unregisters.
    @discardableResult
    func addChangeObserver(_ body: @escaping () -> Void) -> ObservationToken {
        let key = UUID()
        changeObservers[key] = body
        return ObservationToken { [weak self] in
            Task { @MainActor in self?.changeObservers[key] = nil }
        }
    }

    /// Per-tab liveness: title, progress, tint, audio. Separate from
    /// `addChangeObserver` because a progress tick must not re-render a list.
    @discardableResult
    func addTabStateObserver(_ body: @escaping (UUID, TabState) -> Void) -> ObservationToken {
        let key = UUID()
        tabStateObservers[key] = body
        return ObservationToken { [weak self] in
            Task { @MainActor in self?.tabStateObservers[key] = nil }
        }
    }

    /// The pre-observer spelling, kept working so nothing breaks mid-wave. One
    /// slot: whoever assigns last wins, which is exactly why the observer API
    /// above exists. New code registers.
    var onChange: (() -> Void)?
    var onTabStateChange: ((UUID, TabState) -> Void)?

    private var changeObservers: [UUID: () -> Void] = [:]
    private var tabStateObservers: [UUID: (UUID, TabState) -> Void] = [:]

    func notifyChange() {
        onChange?()
        // Snapshot: an observer may unregister itself from inside its callback.
        for observer in Array(changeObservers.values) { observer() }
    }

    func notifyTabState(_ id: UUID, _ state: TabState) {
        onTabStateChange?(id, state)
        for observer in Array(tabStateObservers.values) { observer(id, state) }
    }

    // MARK: - Collaborators the app plugs in

    /// `⌘T`, and the top bar's pill when what was typed is not a URL. The
    /// argument is the query to open with — empty for a plain `⌘T`. The Command
    /// Bar's host sets this; without it `⌘T` opens a blank tab, which is an
    /// honest degradation rather than a dead key.
    var presentCommandBar: ((CommandBarMode) -> Void)?

    /// `⌘L`. The sidebar or top bar sets this to focus and select its URL pill.
    var focusURLField: (() -> Void)?

    /// Downloads (§15). The receiver **must** set `download.delegate`
    /// synchronously; with no handler the download is cancelled rather than
    /// left to stall invisibly.
    var onDownload: ((WKDownload) -> Void)?

    /// Undo for close / archive / move (§6.7), driven by the app's `undo:` /
    /// `redo:`. AppKit's text fields keep their own.
    let undoManager = UndoManager()

    /// The window JavaScript dialogs sheet onto. Weak: the session must not
    /// keep a closed window alive.
    weak var hostWindow: NSWindow?

    /// The gradient a new Space takes, given the ones already in use.
    ///
    /// §8.2's twelve curated pairs and the next-unused rule live in `Design`,
    /// which is where the rest of the colour lives; the session only asks. The
    /// override exists so a test can pin the answer without a design system
    /// behind it, and nothing in the app sets it.
    var nextGradient: ([GradientPair]) -> GradientPair = { Tokens.Gradient.next(after: $0) }

    // MARK: - State
    //
    // `internal`, not `private`, only because Swift's `private` is file-scoped
    // and the coordinator is three files. Nothing outside `BrowserSession*.swift`
    // touches any of it.

    let store: BrowserStore
    let profileStore = ProfileStore()
    var profiles: [UUID: Profile]
    var list: TabList
    var activeTabBySpace: [UUID: UUID] = [:]
    var controllers: [UUID: TabController] = [:]
    /// Most-recently-used first. Drives §19.2's "keep the active tab + last N".
    var recentTabs: [UUID] = []
    var faviconPNG: [UUID: Data] = [:]
    /// How a tab's *next* navigation started, for §9.3's frecency weights.
    /// Absent means the user followed a link.
    var pendingVisitKind: [UUID: VisitKind] = [:]
    var recordedURL: [UUID: URL] = [:]
    /// §6.3's archive, newest first. Held in memory because `allTabs` and
    /// `⌘⇧T` are synchronous and an archived tab is the same row as an open one
    /// (§11.1: `archive` is a view over `tabs`, not a second table).
    var archived: [Tab]
    /// Serialises tab writes — see `enqueue` in `BrowserSession+Tabs.swift`.
    var writeChain: Task<Void, Never>?

    /// §19.2: the active tab plus the last three. Anything playing audio is
    /// exempt as well, checked live.
    static let liveTabBudget = 4
    private static let activeSpaceKey = "luna.activeSpaceID"
    /// What a tab with no URL of its own opens — ⌘T and popups. The New Tab
    /// page rather than `about:blank`, so §30.19's surface is reachable from
    /// more than an empty Space.
    static let blankPage = InternalPages.Page.newTab.url

    // MARK: - Restore (§6.2, §19.4)

    /// Rebuilds the last session from SQLite. Tabs come back with their order,
    /// their titles and their `interactionState` blobs — and **no web views**:
    /// no `TabController` is created here, so a 30-tab relaunch costs one
    /// database read and zero WebContent processes.
    static func restored(store: BrowserStore) async throws -> BrowserSession {
        try await store.seedIfEmpty()
        let spaces = try await store.spaces()
        guard !spaces.isEmpty else { throw SessionError.noSpaces }

        var tabs: [UUID: [Tab]] = [:]
        var archived: [Tab] = []
        for space in spaces {
            // One query per Space, not two: the archive is the same table.
            let all = try await store.tabs(inSpace: space.id, includeArchived: true)
            tabs[space.id] = all.filter { $0.archivedAt == nil }
            archived += all.filter { $0.archivedAt != nil }
        }
        let remembered = UserDefaults.standard.string(forKey: activeSpaceKey).flatMap(UUID.init(uuidString:))
        return BrowserSession(
            store: store,
            spaces: spaces,
            profiles: try await store.profiles(),
            list: TabList(tabs, profiles: Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.profileID) })),
            archived: archived.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) },
            activeSpaceID: (spaces.first { $0.id == remembered } ?? spaces[0]).id
        )
    }

    private init(
        store: BrowserStore,
        spaces: [Space],
        profiles: [Profile],
        list: TabList,
        archived: [Tab],
        activeSpaceID: UUID
    ) {
        self.store = store
        self.spaces = spaces
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        self.list = list
        self.archived = archived
        self.activeSpaceID = activeSpaceID
    }

    enum SessionError: LocalizedError {
        case noSpaces
        case lastSpace
        case unknownSpace
        case unknownProfile
        case emptyName

        var errorDescription: String? {
            switch self {
            case .noSpaces: "Luna's database has no Spaces in it."
            case .lastSpace: "The last Space cannot be deleted."
            case .unknownSpace: "That Space no longer exists."
            case .unknownProfile: "That profile no longer exists."
            case .emptyName: "A Space needs a name."
            }
        }
    }

    // MARK: - Spaces (§5)
    //
    // A Space names a Profile; a Profile *is* a `WKWebsiteDataStore` created
    // with an identifier Luna generated and persisted itself, because WebKit
    // will not hand the mapping back (§5.1).

    func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }

    func profile(for space: Space) -> Profile? { profiles[space.profileID] }

    func switchSpace(_ id: UUID) {
        guard id != activeSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        activeSpaceID = id
        // Choosing a Space is choosing its tab, so unlike a restore this may
        // wake one: the Space's last selection, else its most recent tab.
        if let remembered = activeTabBySpace[id] {
            activateTab(remembered)
        } else if let newest = tabs.max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            activateTab(newest.id)
        } else {
            notifyChange()
        }
        enforceLiveTabBudget()
    }

    /// The data store every tab in this Space is built against.
    func dataStore(forSpace spaceID: UUID) -> WKWebsiteDataStore {
        guard let space = space(spaceID), let profile = profiles[space.profileID] else {
            // Unreachable while the schema's foreign key holds. A non-persistent
            // store is the safe wrong answer: it leaks nothing into a profile
            // the user did not mean.
            return .nonPersistent()
        }
        return profileStore.dataStore(for: profile)
    }

    /// The SF Symbol a new Space starts with, matching the seeded first Space.
    /// §8.2's twelve curated gradient pairs have no home in `Design/` yet, so a
    /// new Space also starts on `GradientPair.defaultSpace`.
    static var defaultSpaceSymbol: String { "moon.stars.fill" }
}
