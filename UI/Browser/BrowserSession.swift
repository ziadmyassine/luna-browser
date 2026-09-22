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
//  What keeps it small (§0.3, §19, §33) is that navigation lives in
//  `TabController`, persistence in `BrowserStore`, ordering in `TabList` and
//  geometry in `BrowserWindowController` — and anything a view can compute from
//  `tabs` does not get a method here. Four files:
//
//      BrowserSession.swift         state, restore, the Space list (§5)
//      BrowserSession+Spaces.swift  the Space lifecycle and Favorites (§6, §2)
//      BrowserSession+Tabs.swift    the tab API, navigation, persistence, undo
//      BrowserSession+Groups.swift  §3.4b's groups and the saved tier
//      BrowserSession+Engine.swift  controllers, hibernation, WebKit callbacks
//
//  Two invariants everything depends on:
//    1. `tabs` is sorted essential → pinned → today, and inside the last two it
//       is the order §3.4 draws — a §3.4b group's tabs inline under it. See
//       `TabList`, which is also where `reorderTab`'s index is defined: it
//       counts the run the tab is joining, not the whole list.
//    2. A tab with no `TabController` has no `WKWebView` and no WebContent
//       process (§19.2). Restoring a session creates no controllers at all
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

    /// The tab that is actually on screen, as far as §3.2's Picture-in-Picture
    /// hand-off is concerned. Not the same question as `activeTabID`: switching
    /// Space moves `activeSpaceID` first, so by the time `activateTab` runs the
    /// tab being left is no longer derivable. Written only by
    /// `BrowserSession+PictureInPicture.swift`.
    var presentedTabID: UUID?

    /// Structural changes — the tab list, the Space list, the selection.
    ///
    /// Register, do not assign. The sidebar, the top bar and the app are
    /// all observers at the same time (both layouts stay alive across a
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
    /// A §3.4b folder has just been made and its row is on screen. One slot, not
    /// an observer list: there is exactly one thing to do with a folder that has
    /// no name yet, which is open its name field, and exactly one column drawing
    /// the row to open it on.
    var onGroupCreated: ((UUID) -> Void)?

    private var changeObservers: [UUID: () -> Void] = [:]
    private var tabStateObservers: [UUID: (UUID, TabState) -> Void] = [:]

    func notifyChange() {
        // §3.2's Automatic Picture-In-Picture, before the observers run: the
        // selection has already moved by the time anything is told about it.
        handOffPictureInPicture(to: activeTabID)
        onChange?()
        // Snapshot: an observer may unregister itself from inside its callback.
        for observer in Array(changeObservers.values) { observer() }
    }

    func notifyTabState(_ id: UUID, _ state: TabState) {
        onTabStateChange?(id, state)
        for observer in Array(tabStateObservers.values) { observer(id, state) }
    }

    // MARK: - Collaborators the app plugs in

    /// `⌘T`, and every address pill that hands the job over. The first argument
    /// is what the bar opens with; the second is the pill it should grow out
    /// of — §3.2's and §3.2b's pass themselves, and `⌘T` passes nil and gets
    /// §9.1's panel over the page. The Command Bar's host sets this; without it
    /// `⌘T` opens a blank tab, which is an honest degradation rather than a
    /// dead key.
    var presentCommandBar: ((CommandBarMode, CommandBarAnchor?) -> Void)?

    /// `⌘L`. The sidebar or top bar sets this to focus and select its URL pill.
    var focusURLField: (() -> Void)?

    /// Downloads (§15). The receiver must set `download.delegate`
    /// synchronously; with no handler the download is cancelled rather than
    /// left to stall invisibly.
    var onDownload: ((WKDownload) -> Void)?

    /// §14's two floating panels — the credential picker and the save chip.
    /// One property, so neither can be presented without the other being
    /// reachable to dismiss. The behaviour is in
    /// `UI/Passwords/BrowserSession+Passwords.swift`.
    let passwordUI = PasswordUI()

    /// Undo for close / archive / move (§6.7), driven by the app's `undo:` /
    /// `redo:`. AppKit's text fields keep their own.
    let undoManager = UndoManager()

    /// The window JavaScript dialogs sheet onto. Weak: the session must not
    /// keep a closed window alive.
    weak var hostWindow: NSWindow?

    /// The gradient a new Space takes, given the ones already in use.
    ///
    /// Neutral: colour is something the user asks for. Handing a new Space one
    /// of §8.2's twelve curated pairs automatically meant the sidebar changed
    /// colour on its own, and the only way back was a menu the user had no
    /// reason to open. Neutral washes to nothing, so a Space that was never
    /// given a colour looks like the sidebar always did. `Tokens.Gradient.next`
    /// is still there, behind the dot's colour menu and §3.7's Gradient popup.
    ///
    /// The override exists so a test can pin the answer without a design system
    /// behind it; nothing in the app sets it.
    var nextGradient: ([GradientPair]) -> GradientPair = { _ in Tokens.Gradient.neutral }

    // MARK: - State
    //
    // `internal`, not `private`, only because Swift's `private` is file-scoped
    // and the coordinator is three files. Nothing outside `BrowserSession*.swift`
    // touches any of it.

    let store: BrowserStore
    let profileStore = ProfileStore()
    var list: TabList
    var activeTabBySpace: [UUID: UUID] = [:]
    var controllers: [UUID: TabController] = [:]
    /// Most-recently-used first. Drives §19.2's "keep the active tab + last N".
    var recentTabs: [UUID] = []
    var faviconPNG: [UUID: Data] = [:]
    /// How a tab's next navigation started, for §9.3's frecency weights.
    /// Absent means the user followed a link.
    var pendingVisitKind: [UUID: VisitKind] = [:]
    var recordedURL: [UUID: URL] = [:]
    /// §3.4a's muted tabs. Held here rather than on the `TabController` because a
    /// controller is discarded every time a tab goes cold (§19.2) and a mute that
    /// evaporated when the tab hibernated would come back making noise. Deliberately
    /// not on the `Tab` row: a mute answers the sound happening now, and a tab that
    /// came back silent after a relaunch with nothing on screen to say why would be a
    /// bug report, not a feature. See `setMuted(_:tab:)`.
    var mutedTabIDs: Set<UUID> = []
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
    /// What a tab with no URL of its own opens, which since §30.19's page was
    /// removed is only a popup — `window.open()` with nothing to open.
    ///
    /// `about:blank` is what the web platform already calls that, and there is
    /// nothing left for Luna to put there instead: every way a person makes a
    /// tab now asks where it is going first (§9.1).
    static let blankPage = URL(string: "about:blank")!

    // MARK: - Restore (§6.2, §19.4)

    /// Rebuilds the last session from SQLite. Tabs come back with their order,
    /// their titles and their `interactionState` blobs — and no web views:
    /// no `TabController` is created here, so a 30-tab relaunch costs one
    /// database read and zero WebContent processes.
    static func restored(store: BrowserStore) async throws -> BrowserSession {
        try await store.seedIfEmpty()
        let spaces = try await store.spaces()
        guard !spaces.isEmpty else { throw SessionError.noSpaces }

        var tabs: [UUID: [Tab]] = [:]
        var groups: [UUID: [TabGroup]] = [:]
        var archived: [Tab] = []
        for space in spaces {
            // One query per Space, not two: the archive is the same table.
            let all = try await store.tabs(inSpace: space.id, includeArchived: true)
            tabs[space.id] = all.filter { $0.archivedAt == nil }
            archived += all.filter { $0.archivedAt != nil }
            groups[space.id] = try await store.groups(inSpace: space.id)
        }
        let remembered = UserDefaults.standard.string(forKey: activeSpaceKey).flatMap(UUID.init(uuidString:))
        let session = BrowserSession(
            store: store,
            spaces: spaces,
            list: TabList(tabs, groups: groups),
            archived: archived.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) },
            activeSpaceID: (spaces.first { $0.id == remembered } ?? spaces[0]).id
        )
        // §3.4b's tier holds folders and nothing else, and a database written
        // before that rule has loose rows standing in it. Here rather than in a
        // schema migration: the fix is a folder and a run of `groupID`s, which
        // is this layer's arithmetic and not SQLite's.
        session.enfoldLooseSavedTabs()
        return session
    }

    private init(
        store: BrowserStore,
        spaces: [Space],
        list: TabList,
        archived: [Tab],
        activeSpaceID: UUID
    ) {
        self.store = store
        self.spaces = spaces
        self.list = list
        self.archived = archived
        self.activeSpaceID = activeSpaceID
    }

    enum SessionError: LocalizedError {
        case noSpaces
        case lastSpace
        case unknownSpace
        case emptyName

        var errorDescription: String? {
            switch self {
            case .noSpaces: "Luna's database has no Spaces in it."
            case .lastSpace: "The last Space cannot be deleted."
            case .unknownSpace: "That Space no longer exists."
            case .emptyName: "A Space needs a name."
            }
        }
    }

    // MARK: - Spaces (§5)
    //
    // A Space is a `WKWebsiteDataStore` created with an identifier Luna
    // generated and persisted itself, because WebKit will not hand the mapping
    // back (§5.1). It named a Profile row that held that identifier until §9's
    // `v7`; one Space, one jar, and nothing in between them now.

    func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }

    func switchSpace(_ id: UUID) {
        guard id != activeSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        activeSpaceID = id
        // Choosing a Space is choosing its tab, so unlike a restore this may
        // wake one: the Space's last selection, else its most recent open tab.
        //
        // Open, and nothing else. A Space the user had emptied came back with a
        // page on screen, because the fallback took the newest row of any kind
        // — so a §3.3 tile, or a §3.4b row that had been closed once, was
        // loaded by the act of walking past the Space. Both are places rather
        // than pages, and opening one is a gesture the user makes.
        if let remembered = activeTabBySpace[id] {
            activateTab(remembered)
        } else if let newest = openableTabs(inSpace: id).max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            activateTab(newest.id)
        } else {
            notifyChange()
        }
        enforceLiveTabBudget()
    }

    /// The data store every tab in this Space is built against.
    func dataStore(forSpace spaceID: UUID) -> WKWebsiteDataStore {
        guard let space = space(spaceID) else {
            // Unreachable while the Space exists at all. A non-persistent store
            // is the safe wrong answer: it leaks nothing into a jar the user did
            // not mean.
            return .nonPersistent()
        }
        return profileStore.dataStore(for: space)
    }

    /// The SF Symbol a new Space starts with, matching the seeded first Space.
    /// §8.2's twelve curated gradient pairs have no home in `Design/` yet, so a
    /// new Space also starts on `GradientPair.defaultSpace`.
    static var defaultSpaceSymbol: String { "moon.stars.fill" }
}
