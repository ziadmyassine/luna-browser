//
//  BrowserSession.swift
//  Luna
//
//  The coordinator, and the single source of truth the UI reads from. It owns
//  the Space list, the tab list, the selections and the `TabController`s, and
//  is the only object that talks to both `BrowserStore` and the engine; views
//  own no model state and re-read it on `onChange`. Navigation, persistence,
//  ordering and geometry stay in `TabController`, `BrowserStore`, `TabList`
//  and `BrowserWindowController`. This file is state, restore and the Space
//  list (§5); each `BrowserSession+*.swift` holds one area of the API.
//
//  Two invariants everything depends on:
//    1. `tabs` is sorted essential → pinned → today, in §3.4's drawn order with
//       a group's tabs inline; `reorderTab`'s index counts the run it joins.
//    2. A tab with no `TabController` has no web view and no WebContent
//       process (§19.2); restoring creates no controllers at all (§19.4).
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
    /// `private` is file-scoped and the coordinator spans several. Views read it
    /// and never assign, exactly as they never assign `list`.
    var spaces: [Space]

    /// The Space the front window is showing (§5.3, §22.6). Every unqualified
    /// question here is about that window — see `BrowserSession+Windows.swift`,
    /// which is also where a named window's own answer comes from.
    var activeSpaceID: UUID { activeSpaceID(inWindow: keyWindowID) }

    /// Every tab in the active Space, ordered. Derived, so one tab is one value
    /// in one place no matter which Space it belongs to.
    var tabs: [Tab] { list[activeSpaceID] }

    /// nil straight after a restore: nothing is selected until the user picks a
    /// tab, and nothing selected means no web view anywhere (§19.4).
    var activeTabID: UUID? { activeTabID(inWindow: keyWindowID) }

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

    /// How far a tab's page has been read, 0...1 or nil, as it changes. Not
    /// part of `TabState`, for the engine's reason: a scroll must not
    /// re-render a row. The session is the one holder of each controller's
    /// `onScrollProgress` and hands it on here, because the sidebar and the
    /// top bar are both alive at once and a single closure was theirs in turn.
    @discardableResult
    func addScrollProgressObserver(_ body: @escaping (UUID, Double?) -> Void) -> ObservationToken {
        let key = UUID()
        scrollProgressObservers[key] = body
        return ObservationToken { [weak self] in
            Task { @MainActor in self?.scrollProgressObservers[key] = nil }
        }
    }

    /// The single-slot spelling: whoever assigns last wins, which is why the
    /// observer API above exists. New code registers.
    var onChange: (() -> Void)?
    var onTabStateChange: ((UUID, TabState) -> Void)?
    /// A §3.4b folder has just been made and its row is on screen. One slot, not
    /// an observer list: there is exactly one thing to do with a folder that has
    /// no name yet, which is open its name field, and exactly one column drawing
    /// the row to open it on.
    var onGroupCreated: ((UUID) -> Void)?

    private var changeObservers: [UUID: () -> Void] = [:]
    private var tabStateObservers: [UUID: (UUID, TabState) -> Void] = [:]
    private var scrollProgressObservers: [UUID: (UUID, Double?) -> Void] = [:]

    func notifyChange() {
        // §3.2's Automatic Picture-In-Picture, before the observers run: the
        // selection has already moved by the time anything is told about it.
        handOffPictureInPicture(to: activeTabID)
        // §7.3's dot, also before them: every way a tab reaches a window ends
        // here, and a row drawn from the snapshot before the clear would keep
        // its dot on the page being read.
        clearUnreadOnScreen()
        onChange?()
        extensions?.sync()
        // Snapshot: an observer may unregister itself from inside its callback.
        for observer in Array(changeObservers.values) { observer() }
    }

    func notifyTabState(_ id: UUID, _ state: TabState) {
        onTabStateChange?(id, state)
        extensions?.tabDidChange(id, state: state)
        for observer in Array(tabStateObservers.values) { observer(id, state) }
    }

    /// Takes `controller`'s scroll progress for the observers above.
    func relayScrollProgress(of controller: TabController) {
        let id = controller.id
        controller.onScrollProgress = { [weak self] progress in
            guard let self else { return }
            for observer in Array(scrollProgressObservers.values) { observer(id, progress) }
        }
    }

    /// Forwards the Chrome Web Store button-hijack's two signals to the offer,
    /// which cancels or runs its toast fallback (`WebStoreOffer`).
    func relayWebStoreOffer(of controller: TabController) {
        let id = controller.id
        controller.onWebStoreButtonReady = { [weak controller] url in
            WebStoreOffer.shared.buttonReady(url: url, tab: id) { controller?.webStoreButtonAdded() }
        }
        controller.onWebStoreAddRequested = { [weak controller] url in
            WebStoreOffer.shared.add(url: url, tab: id) { controller?.webStoreButtonAdded() }
        }
    }

    // MARK: - Collaborators the app plugs in

    /// `⌘T`, and every address pill that hands the job over. The first argument
    /// is what the bar opens with; the second is the pill it should grow out
    /// of — §3.2's and §3.2b's pass themselves, and `⌘T` passes nil and gets
    /// §9.1's panel over the page. The Command Bar's host sets this; without it
    /// `⌘T` opens a blank tab, which is an honest degradation rather than a
    /// dead key.
    /// Read-only, and the front window's: a command means the window the user
    /// is in. A view sets and reads its own through `WindowScoped` — see
    /// `BrowserSession+Windows.swift`, which holds the pair of them per window
    /// because §9.1's bar and §3.2's pill are chrome and chrome is per window.
    var presentCommandBar: CommandBarPresenter? { commandBarByWindow[keyWindowID] }

    /// `⌘L`. The sidebar or top bar sets this to focus and select its URL pill.
    var focusURLField: (() -> Void)? { urlFieldByWindow[keyWindowID] }

    /// Downloads (§15). The receiver must set `download.delegate`
    /// synchronously; with no handler the download is cancelled rather than
    /// left to stall invisibly.
    var onDownload: ((WKDownload) -> Void)?

    /// §14's credential picker.
    /// One property, so neither can be presented without the other being
    /// reachable to dismiss. The behaviour is in
    /// `Luna/UI/Passwords/BrowserSession+Passwords.swift`.
    let passwordUI = PasswordUI()

    /// §17's pop-up notice. The behaviour is in `Luna/UI/Popups/BrowserSession+Popups.swift`.
    let popupNotice = PopupNotice()

    /// Undo for close / archive / move (§6.7) and for hiding part of a page,
    /// and every browser window's list (`windowWillReturnUndoManager`).
    let undoManager = SessionUndoManager()

    /// The window JavaScript dialogs sheet onto. Weak: the session must not
    /// keep a closed window alive.
    weak var hostWindow: NSWindow?

    /// The gradient a new Space takes, given the ones already in use.
    ///
    /// Neutral: colour is something the user asks for. Not one of §8.2's
    /// curated pairs automatically — the sidebar then changed colour on its
    /// own, and the only way back was a menu the user had no reason to open.
    /// Neutral washes to nothing, so an uncoloured Space looks like a plain
    /// sidebar. `Tokens.Gradient.next` serves the dot's colour menu and §3.7's
    /// Gradient popup.
    ///
    /// The override exists so a test can pin the answer without a design system
    /// behind it; nothing in the app sets it.
    var nextGradient: ([GradientPair]) -> GradientPair = { _ in Tokens.Gradient.neutral }

    // MARK: - State
    //
    // `internal`, not `private`, only because Swift's `private` is file-scoped
    // and the coordinator spans several files. Nothing outside `BrowserSession*.swift`
    // touches any of it.

    /// §5.6. Set once at restore: it decides whether a Space gets a cookie jar
    /// on disk or one that dies with the window, and whether anything at all is
    /// written outside this session's own store.
    let isPrivate: Bool
    let store: BrowserStore
    let spaceJars = SpaceJarStore()
    /// §16's extensions: one controller per Space. Nil in a private session,
    /// where no extension runs, as in Chrome's incognito by default.
    private(set) var extensions: ExtensionManager?
    /// §5.6's one jar, shared by every Space in a private session. One rather
    /// than one each: the Spaces in such a window are a throwaway list in a
    /// throwaway database, and two in-memory jars would be two of a thing that
    /// exists to be forgotten.
    private lazy var privateDataStore = WKWebsiteDataStore.nonPersistent()
    var list: TabList
    /// §22.6. Made on first write rather than on registration, so a session
    /// with no chrome on it still answers every question about a selection.
    var windowFocus: [UUID: WindowFocus] = [:]
    var commandBarByWindow: [UUID: CommandBarPresenter] = [:]
    var urlFieldByWindow: [UUID: () -> Void] = [:]
    /// The window the app's own commands mean. A name nothing else holds until
    /// a window claims it.
    var keyWindowID = UUID()
    /// The Space a new window opens on, and the one the next launch comes back
    /// to: the last one anybody chose, in any window.
    private(set) var lastUsedSpaceID: UUID {
        didSet {
            guard !isPrivate else { return }
            UserDefaults.standard.set(lastUsedSpaceID.uuidString, forKey: Self.activeSpaceKey)
        }
    }

    /// Which tab the front window has selected in each Space (§22.6). The
    /// spelling the session's own verbs are written in; a window other than the
    /// front one is reached through `BrowserSession+Windows.swift`.
    var activeTabBySpace: [UUID: UUID] {
        get { focus(keyWindowID).tabBySpace }
        set { windowFocus[keyWindowID, default: WindowFocus(spaceID: lastUsedSpaceID)].tabBySpace = newValue }
    }
    var controllers: [UUID: TabController] = [:]
    /// The command bar's top hit, loading before Return is pressed.
    let topHit = TopHitPreload()
    /// Most-recently-used first. Drives §19.2's "keep the active tab + last N".
    var recentTabs: [UUID] = []
    var faviconPNG: [UUID: Data] = [:]
    /// §5.6: a private session's icons are fetched, kept and drawn from its own
    /// memory-only service, never the one normal windows share.
    lazy var icons: SidebarIcons = isPrivate ? SidebarIcons(service: FaviconService(directory: nil)) : .shared
    var favicons: FaviconService { icons.service }
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
    /// Tabs whose last reported `TabState` was loading, so the report that
    /// says otherwise can be read as a load finishing. Written only by
    /// `BrowserSession+Unread.swift`.
    var loadingTabIDs: Set<UUID> = []
    /// Links opened behind the tab in front that nobody has looked at yet,
    /// until their first load ends. Written only by `BrowserSession+Unread.swift`.
    var unseenBackgroundTabIDs: Set<UUID> = []

    /// The tab whose media played last, paused since or not — see
    /// `BrowserSession+NowPlaying.swift`, the only writer.
    var nowPlayingTabID: UUID?
    /// §3.4b: tabs still shown under their folder while it is folded — the
    /// one the user was on when they folded it, and any they have gone to
    /// inside it since. See `BrowserSession+Groups`'s "Folded, but showing".
    /// Not on the row: it is about this session's browsing, and a relaunch
    /// that came back with a folder half open would be a folder in a state
    /// nobody left it in.
    var folderPeeks: Set<UUID> = []
    /// Folders taken away with their last tab (`dropGroupIfEmptied`), so a
    /// tab reopened out of one brings it back. This launch only: the row on
    /// disk is gone, and a tab reopened after a relaunch comes back loose.
    var emptiedGroups: [UUID: TabGroup] = [:]
    /// §3.4b folders whose Luna Control client is working in them right now,
    /// which the sidebar marks. Written only by `BrowserSession+Control.swift`.
    var controlledGroupIDs: Set<UUID> = []
    /// Tabs a Luna Control client is acting on right now, with whose app it
    /// is, which the sidebar outlines. Written only by `BrowserSession+Control.swift`.
    var controlledTabs: [UUID: ControlFace] = [:]
    /// `ControlService.refreshBadges`'s symbols, by folder.
    var controlBadges: [UUID: String] = [:]
    /// Tabs an agent is waiting on the user in, which wear the raised hand.
    var controlNeedsYouTabs: Set<UUID> = []
    /// Which app each Luna Control folder belongs to, by folder:
    /// `ControlService.refreshFaces`'s.
    var controlFaces: [UUID: ControlFace] = [:]
    /// Folders Astro is working in for the whole of a turn, and the tab in
    /// each it last acted on.
    var astroWorkingGroups: Set<UUID> = []
    var astroWorkingTabs: Set<UUID> = []
    /// The Luna Control service driving this session, which holds the page
    /// dialogs of its agents' tabs.
    weak var control: ControlService?
    /// Whether a tab opening now goes to the end of today's tabs rather than
    /// the head — true while §4's top bar is the chrome. Told by the window
    /// rather than read from `Settings`, so the rule is the session's and a
    /// test's session is not answering from the machine's preferences.
    var opensTabsAtEnd = false

    /// `TabList.openIndex(for:)`, for the chrome on screen.
    func openIndex(for kind: TabKind) -> Int? {
        TabList.openIndex(for: kind, newestFirst: !opensTabsAtEnd)
    }
    /// §6.3's archive, newest first. Held in memory because `allTabs` and
    /// `⌘⇧T` are synchronous and an archived tab is the same row as an open one
    /// (§11.1: `archive` is a view over `tabs`, not a second table).
    var archived: [Tab]
    /// Serialises tab writes — see `enqueue` in `BrowserSession+Tabs.swift`.
    var writeChain: Task<Void, Never>?

    /// §19.2: the active tab plus the last seven — `HibernationPolicy` has
    /// why eight. Anything playing audio is exempt as well, checked live.
    static let liveTabBudget = 8
    private static let activeSpaceKey = "luna.activeSpaceID"
    /// What a tab with no URL of its own opens, which is only a popup —
    /// `window.open()` with nothing to open. `about:blank` is what the web
    /// platform calls that, and Luna has nothing to put there instead: every
    /// way a person makes a tab asks where it is going first (§9.1).
    static let blankPage = URL(string: "about:blank")!

    // MARK: - Restore (§6.2, §19.4)

    /// Rebuilds the last session from SQLite. Tabs come back with their order,
    /// their titles and their `interactionState` blobs — and no web views:
    /// no `TabController` is created here, so a 30-tab relaunch costs one
    /// database read and zero WebContent processes.
    /// - Parameter isPrivate: §5.6. A private session keeps nothing outside its
    ///   own store: no cookie jar on disk, and no note in `UserDefaults` of
    ///   which Space it was in — a window that leaves a trace of where it was
    ///   is not private, however little the trace says.
    static func restored(store: BrowserStore, isPrivate: Bool = false) async throws -> BrowserSession {
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
            activeSpaceID: (spaces.first { $0.id == remembered } ?? spaces[0]).id,
            isPrivate: isPrivate
        )
        // §3.4b's tier holds folders and nothing else, and a database written
        // before that rule has loose rows standing in it. Here rather than in a
        // schema migration: the fix is a folder and a run of `groupID`s, which
        // is this layer's arithmetic and not SQLite's.
        session.enfoldLooseSavedTabs()
        if !isPrivate {
            let extensions = ExtensionManager(
                store: store,
                library: ExtensionLibrary(root: store.directory.appending(path: "Extensions", directoryHint: .isDirectory))
            )
            extensions.browser = session
            session.extensions = extensions
        }
        return session
    }

    private init(
        store: BrowserStore,
        spaces: [Space],
        list: TabList,
        archived: [Tab],
        activeSpaceID: UUID,
        isPrivate: Bool
    ) {
        self.isPrivate = isPrivate
        self.store = store
        self.spaces = spaces
        self.list = list
        self.archived = archived
        self.lastUsedSpaceID = activeSpaceID
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
    // back (§5.1). Since §9's `v7` there is no Profile row between them: one
    // Space, one jar.

    func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }

    func switchSpace(_ id: UUID) {
        guard id != activeSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        windowFocus[keyWindowID, default: WindowFocus(spaceID: id)].spaceID = id
        lastUsedSpaceID = id
        // Choosing a Space is choosing its tab, so unlike a restore this may
        // wake one: the Space's last selection, else its most recent open tab.
        //
        // Open, and nothing else. Not the newest row of any kind: a §3.3 tile,
        // or a §3.4b row closed once, was then loaded by walking past the Space,
        // and an emptied Space came back with a page on screen. Both are places
        // rather than pages, and opening one is a gesture the user makes.
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
        // §5.6: nothing this window loads reaches disk, and `SpaceJarStore` —
        // which is the thing that makes a jar on disk — is never asked.
        guard !isPrivate else { return privateDataStore }
        guard let space = space(spaceID) else {
            // Unreachable while the Space exists at all. A non-persistent store
            // is the safe wrong answer: it leaks nothing into a jar the user did
            // not mean.
            return .nonPersistent()
        }
        return spaceJars.dataStore(for: space)
    }

    /// Whose per-site answers this window reads and writes: §5.6's own, or the active Space's.
    var sitePermissions: SitePermissions {
        isPrivate ? .scope(for: privateDataStore) : SitePermissions.shared.forSpace(activeSpaceID)
    }

    /// Whose hidden page parts this window wears and adds to, for the same reason.
    var hiddenElements: HiddenElements { isPrivate ? .scope(for: privateDataStore) : .shared }

    /// The SF Symbol a new Space starts with, matching the seeded first Space.
    /// Its gradient is `nextGradient`'s answer.
    static var defaultSpaceSymbol: String { "moon.stars.fill" }
}
