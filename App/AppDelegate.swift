//
//  AppDelegate.swift
//  Luna
//
//  Entry point and the app's one assembly seam: it owns the store, the
//  session, the window and the feature surfaces, and wires them to each other.
//  Commands live in `BrowserCommands.swift`, the key map in `MainMenu.swift` —
//  this file is lifecycle and wiring only.
//
//  Wave-2 integration points, all of them here and nowhere else:
//      UI/Sidebar    SidebarViewController(session:)   §3
//      UI/TopBar     TopBarView(session:)              §4
//      UI/CommandBar CommandBarController(session:adaptive:)  ⌘T / ⌘L
//      Features/Downloads  DownloadManager             session.onDownload
//

import AppKit
import BrowserKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApplicationMain` only installs an app delegate when it loads a main
    /// nib, and Luna has none — so we stand the app up ourselves. Verified: the
    /// inherited `NSApplicationDelegate.main()` leaves `NSApp.delegate` nil and
    /// the app launches to a dead run loop.
    static func main() {
        // Everything before this line is dyld, the Swift runtime and the ObjC
        // class registry — see `LaunchTrace.sinceExec`.
        LaunchTrace.mark("main")
        let app = LunaApplication.shared
        let delegate = AppDelegate()
        // `NSApplication.delegate` is weak and nothing else owns us.
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Every open browser window, oldest first, and the one the user is in
    /// (§22.6). AppKit's `NSWindow.windowController` is weak, so somebody has
    /// to own these; `BrowserWindow` owns everything built per window.
    var windows: [BrowserWindow] = []
    var front: BrowserWindow?

    private(set) var store: BrowserStore?
    /// The session behind the front window. Read all over `BrowserCommands`,
    /// and correctly: a command is about the window the user is in.
    var session: BrowserSession? { front?.session }
    /// `fileprivate` would do, except `BrowserCommands` is a separate file:
    /// the commands extension needs it to validate the View menu.
    var browserWindow: BrowserWindowController? { front?.controller }
    var sidebar: SidebarViewController? { front?.sidebar }
    var topBar: TopBarView? { front?.topBar }
    /// §3.2b's page bar. Wired in `AppDelegate+PageChrome.swift`.
    var pageChrome: PageChromeController? { front?.pageChrome }
    /// §9's bar. Wired and read from `AppDelegate+CommandBar.swift`.
    var commandBar: CommandBarController? { front?.commandBar }
    /// §6.4's pop-out. `⌘Y` opens it too (`BrowserCommands+Page`).
    var historyPanel: HistoryPanelController? { front?.historyPanel }
    /// Exactly one per `BrowserStore` (§9.3): two of them would bump divergent
    /// use counts against the same `inputHistory` rows.
    var adaptive: AdaptiveHistory?
    /// Wired in `AppDelegate+Downloads.swift`, so not private. `downloadsInFlight`
    /// below is the only thing anywhere else has any business asking it.
    var downloads: DownloadManager?
    /// How many downloads are still running, or nil before there is a manager
    /// to ask. §3.1's quit sheet is the only caller: a download is the one
    /// thing in Luna that quitting destroys rather than parks.
    var downloadsInFlight: Int? {
        downloads.map { manager in manager.items.filter { $0.state == .inProgress }.count }
    }

    /// §3.1's quit guard, both halves of it — see `AppDelegate+Quit.swift`.
    ///
    /// `isQuitConfirmed` is what makes the second `terminate` go through
    /// instead of asking again. `isQuitFromLogOut` is what stops it asking at
    /// all when the quit is not the user's: logging out, restarting or shutting
    /// down gives every app a few seconds and no keyboard, and a modal nobody
    /// can answer is a machine that will not shut down.
    var isQuitConfirmed = false
    private(set) var isQuitFromLogOut = false
    /// `⌘,`. One instance, re-shown rather than rebuilt.
    /// SETTINGS-SPEC §1's separate window. One instance, reused — `⌘,`
    /// opens it the first time and focuses it every time after, and it survives
    /// being closed because `isReleasedWhenClosed` is off.
    private var settingsWindow: SettingsWindowController?
    /// §30.17's first-run window, alive only while it is on screen.
    /// `AppDelegate+Onboarding.swift` puts it up.
    var onboarding: OnboardingWindowController?
    /// §15.3's list. `BrowserCommands` opens it as well as the two buttons, and
    /// `AppDelegate+Downloads.swift` builds it, so it is neither private nor
    /// `private(set)`.
    var downloadsPanel: DownloadsPanelController?
    /// Luna Control's socket, open only while its setting is on. Holds the
    /// first session, never a §5.6 window's.
    var control: ControlService?
    /// `⌃⇥`'s event monitor — see `AppDelegate+TabSwitcher.swift`.
    var tabSwitcherMonitor: Any?
    /// Web links handed over before the first window could take them, and nil
    /// from then on — see `AppDelegate+OpenURLs.swift`.
    var linksBeforeLaunch: [URL]? = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchTrace.mark("appkit")
        // Both must be in place before the app finishes launching, or the first
        // frame shows up without a menu bar.
        NSApp.setActivationPolicy(.regular)
        // Before anything reads a setting: the registration domain is what a
        // key's declared default is (SETTINGS-SPEC §6), and it is not
        // persisted, so it is re-published on every launch.
        SettingsDefaults.register()
        // §5.6: anything a crash or a hard quit left behind. At launch, where
        // the answer to "is this one in use" is always no.
        Self.sweepPrivateDatabases()
        MainMenu.install(into: NSApp)
        // §3.6: a rebound shortcut rebuilds the bar. Before the first window.
        observeShortcutChanges()
        installTabSwitcherKeys()
        LaunchTrace.mark("menu")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The gap between this and `menu` is AppKit's own: it is what
        // `-[NSApplication finishLaunching]` does between the two notifications,
        // and it is ~40 ms of every launch that no Luna code is in. It has a
        // milestone of its own because without one it looks like ours — it was
        // read as the cost of the line below for most of an afternoon.
        LaunchTrace.mark("didFinish")
        // Before anything is opened: a second copy launched to open a page has
        // no business touching the database the running one is using.
        if handOffToRunningLuna() { return }
        #if DEBUG
        // Fails the launch loudly if a token drifted out of §1 / §6 / §21.4.
        // Measured at 3 ms, so it stays in front of the first frame, where a
        // launch-time check belongs. `docs/PERF.md` has the tape.
        TokenCheck.run()
        LaunchTrace.mark("tokens")
        #endif

        // Before anything that could be interrupted: the notification arrives
        // moments before `applicationShouldTerminate` does, and the whole point
        // of it is to be there first.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(powerOffIsComing),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        // The database is opened before the window, and not on this thread —
        // see ``openStore()``.
        let opening = Self.openStore()

        // SETTINGS-SPEC §3.2. `NSApp.appearance` starts nil — "follow System
        // Settings" — so a stored Light or Dark choice is silently lost on every
        // relaunch unless something re-applies it. Before the window, so the
        // first frame is drawn in the theme the user chose rather than flashing
        // the system one.
        AppearanceSection.applyStoredTheme()

        // SETTINGS-SPEC §3.11. Once a day, off the main thread; never from a
        // test run, which would read the network and could install over the
        // host app.
        if !Self.isRunningTests { Updater.shared.start() }

        // The controller before the session, and on screen before it too: what
        // fills it is `adopt`, once there is something to put in it.
        let controller = BrowserWindowController()
        controller.showWindow(self)
        NSApp.activate()
        LaunchTrace.mark("window")

        // The window is on screen before the session is restored into it:
        // §19.1's 800 ms cold launch is a frame budget, not a disk budget.
        Task { await startSession(in: controller, opening: opening) }
    }

    /// The last of the launch, once the chrome is wired: the pages that stand
    /// on it, the clocks that sweep it, and the first thing on screen.
    private func openForBusiness(session: BrowserSession, store: BrowserStore) {
        // §4.4: the New Tab page, the archive browser and the token→CSS
        // palette. Must follow the sidebar, whose Archive row it claims.
        InternalPagesInstaller.install(session: session)
        // §19.2/§19.5: the hibernation sweep, the auto-archive clock and the
        // memory-pressure source. Before the first tab, so the budget is never
        // briefly unenforced.
        session.installLifecycle()
        let control = ControlService(session: session)
        control.update()
        self.control = control
        // An empty Space opens nothing. It used to be handed a tab on the New
        // Tab page so the content card had something in it; with that page gone
        // there is nothing honest to put in a tab nobody asked for, and the
        // column already says what to do — §3.3a's wells and §30.6's New Tab
        // row, which opens §9.1 rather than a blank page.
        render()
        // A link that launched Luna, over the session it restored.
        openLinksFromLaunch()
        // §19.1's "to interactive": the window has the restored session in it.
        // `Tools/perf` is polling for the file this writes.
        LaunchTrace.ready()
        // §16.1, and after `ready()` for the same reason as onboarding below:
        // extensions load one at a time into a browser that is already up.
        session.startExtensions()
        // §30.17, and after `ready()` on purpose: first run is a window over a
        // browser that is already up, not a gate in front of it.
        presentOnboardingIfNeeded(store: store, session: session)
    }

    /// Opens the store off the main thread, as early as launch can ask for
    /// it.
    ///
    /// `BrowserStore.init` is synchronous — it creates the directory, opens the
    /// pool and runs the migrator — so where it used to be called, it was main
    /// thread time inside the launch, in series with a window it has nothing to
    /// say about. Detached and started first, it runs while AppKit builds that
    /// window instead.
    ///
    /// Say what this bought: 10–20 ms of main thread, and no measurable
    /// change in the launch total. Luna reaches interactive in ~280 ms and
    /// over half of that is AppKit and dyld before any of this code runs
    /// (`docs/PERF.md` has the tape), so moving our own work off the critical
    /// path is worth doing and is not worth claiming a number for.
    ///
    /// Failures travel in the task and are presented where the old call threw,
    /// in `startSession`, rather than being swallowed out here.
    private static func openStore() -> Task<BrowserStore, any Error> {
        let path = databaseURL
        return Task.detached(priority: .userInitiated) {
            let store = try BrowserStore(path: path)
            // Idempotent, and the session restore's first call is a read once
            // this one has run — which is the point of doing it here.
            try await store.seedIfEmpty()
            return store
        }
    }

    /// Restores the last session (§6.2) and hands the UI its source of truth.
    private func startSession(
        in controller: BrowserWindowController,
        opening: Task<BrowserStore, any Error>
    ) async {
        do {
            // §4.7's second decoder. Before the first web view, so no page can
            // finish loading and be told its SVG mark is not an icon.
            VectorIconRasterizer.install()
            let store = try await opening.value
            LaunchTrace.mark("store")
            // §17.1: compiles cached rule lists and schedules the refresh. Before the
            // session, so the first web view is built with the lists already applied.
            ContentBlocker.shared.start(browserStore: store)
            SitePermissions.shared.start(browserStore: store)
            let session = try await BrowserSession.restored(store: store)
            LaunchTrace.mark("session")
            self.store = store
            adopt(BrowserWindow(session: session, controller: controller))
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsDidChange),
                name: Settings.didChange,
                object: nil
            )
            LaunchTrace.mark("chrome")
            openForBusiness(session: session, store: store)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Re-reads the session. Structural only — a tab's progress and title reach
    /// their row through `addTabStateObserver`, not through here.
    ///
    /// Every window, because one session change moves more than one of them: a
    /// tab closed in front of you leaves a window behind it pointing at a row
    /// that has gone (§22.6). The menus are the front window's alone — they
    /// describe what `⌘1` would do, and `⌘1` goes to the window the user is in.
    func render() {
        for window in windows { window.render() }
        guard let session else { return }
        MainMenu.setSpaces(session.spaces.map(\.name), in: NSApp)
        // §13.2's `⌘1…⌘9`. `session.tabs` is already in the sidebar's order —
        // Favorites, then Pinned, then Today — so the number in the menu is the
        // row on screen. Nine at most; `setSidebarItems` truncates.
        MainMenu.setSidebarItems(session.tabs.map(\.title), in: NSApp)
    }

    /// `⌘S` and §3.1's toggle button: hide or show the sidebar, so the page
    /// takes the whole window.
    ///
    /// It used to swap sidebar layout for top-bar layout, which meant a reflex
    /// the user performs several times a minute silently changed a preference
    /// they set once. The layout is now `Settings.chromeLayout` and lives in
    /// the Settings window; this is only a reveal.
    func toggleSidebar() {
        front?.toggleSidebar()
    }

    /// `⌘,`, and §3.2's site menu, which lands on the section it names.
    ///
    /// Over `front`: the browser window the user was last in, which Settings
    /// becoming key does not change.
    func showSettings(section: String? = nil) {
        let window = settingsWindow ?? SettingsWindowController()
        settingsWindow = window
        window.present(section: section, over: front?.controller.window)
    }

    @objc private func settingsDidChange() {
        for window in windows { window.applyChromeLayout(animated: true) }
        control?.update()
    }

    // MARK: - Termination

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `recordVisit` buffers and `interactionState` dies with its WebContent
    /// process, so quitting has real async work to do. `.terminateLater` is the
    /// only way to do it — `applicationWillTerminate` cannot await.
    @objc private func powerOffIsComing() {
        isQuitFromLogOut = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // §3.1: ask first, and answer `.cancel` while the question is up.
        // `AppDelegate+Quit.swift` has why it cannot be `.terminateLater`.
        if wantsQuitConfirmation(sender) {
            presentQuitSheet()
            return .terminateCancel
        }
        guard session != nil else { return .terminateNow }
        Task {
            await flush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// §11.1: the last second of history lives in the store's buffer, and the
    /// user switching apps is the likeliest moment for the app to be killed.
    func applicationDidResignActive(_ notification: Notification) {
        Task { await flush() }
    }

    private func flush() async {
        // A §5.6 window's session writes to a database that is deleted when it
        // closes, so there is nothing to push out of it.
        for window in windows where !window.isPrivate { await window.session.persist() }
        try? await store?.flush()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release the web views while AppKit is still running rather than
        // leaving WebContent processes to process teardown. Every session: a
        // §5.6 window has one of its own.
        control?.stop()
        var torn: Set<ObjectIdentifier> = []
        for window in windows where torn.insert(ObjectIdentifier(window.session)).inserted {
            window.session.tearDown()
        }
        windows = []
        front = nil
    }

    /// `LunaTests` is a unit-test bundle hosted by this app (`project.yml`:
    /// `dependencies: - target: Luna`), so `xcodebuild test` launches the real
    /// `AppDelegate`, runs `applicationDidFinishLaunching`, and opens whatever
    /// this property returns — before the first test method is entered and
    /// whether or not that test wanted a session.
    ///
    /// Which means that until this branch existed, every test run in this
    /// repo migrated and wrote the user's live database. Measured: the
    /// schema-version row in `~/Library/Application Support/dk.novapps.luna/`
    /// moved during this wave and its mtime tracked the test runs. A test that
    /// carefully builds its own fixture store is not protected by doing so —
    /// no test constructs that path, the app does, on their behalf.
    ///
    /// A throwaway directory per run is the fix, and it is here rather than in
    /// the tests because there is no test to put it in: the offending open
    /// happens in app launch. Internal, not private, so
    /// `AppDelegateDatabaseTests` can assert the branch below actually fires.
    static var databaseURL: URL {
        guard !isRunningTests else {
            return URL.temporaryDirectory
                .appending(path: "luna-tests-\(UUID().uuidString)")
                .appending(path: "luna.sqlite")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "luna.sqlite")
    }

    /// XCTest publishes this for every bundle it loads, host app included. Not
    /// `NSClassFromString("XCTestCase")` — that links only after the bundle is
    /// injected, which is after the database has already been opened.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
