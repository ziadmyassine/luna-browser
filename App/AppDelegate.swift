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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // `NSApplication.delegate` is weak and nothing else owns us.
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// AppKit's `NSWindow.windowController` is weak, so somebody has to own the
    /// controller. One window in M1; §22.6's window manager arrives when there
    /// is more than one to manage.
    private var browserWindow: BrowserWindowController?
    private let chrome = ChromeHostView()

    private(set) var store: BrowserStore?
    private(set) var session: BrowserSession?

    // Owned because nothing else retains them: `NSView` does not hold its view
    // controller, and `WKDownload.delegate` is weak (see `DownloadManager`).
    private var sidebar: SidebarViewController?
    private var topBar: TopBarView?
    private var commandBar: CommandBarController?
    /// Exactly one per `BrowserStore` (§9.3): two of them would bump divergent
    /// use counts against the same `inputHistory` rows.
    private var adaptive: AdaptiveHistory?
    private var downloads: DownloadManager?
    /// §15.3's secondary surface. `BrowserCommands` opens it as well as the
    /// top bar's button, so it is not file-private.
    private(set) var downloadsPanel: DownloadsListPanel?
    private var observation: ObservationToken?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Both must be in place before the app finishes launching, or the first
        // frame shows up without a menu bar.
        NSApp.setActivationPolicy(.regular)
        MainMenu.install(into: NSApp)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Fails the launch loudly if a token drifted out of §1 / §6 / §21.4.
        TokenCheck.run()
        #endif

        let controller = BrowserWindowController()
        browserWindow = controller
        controller.showWindow(self)
        NSApp.activate()

        // The window is on screen before the database is touched: §19.1's
        // 800 ms cold launch is a frame budget, not a disk budget.
        Task { await startSession(in: controller) }
    }

    /// Restores the last session (§6.2) and hands the UI its source of truth.
    private func startSession(in controller: BrowserWindowController) async {
        do {
            let store = try BrowserStore(path: Self.databaseURL)
            // §17.1: compiles cached rule lists and schedules the refresh. Before the
            // session, so the first web view is built with the lists already applied.
            ContentBlocker.shared.start(browserStore: store)
            let session = try await BrowserSession.restored(store: store)
            self.store = store
            self.session = session
            session.hostWindow = controller.window
            observation = session.addChangeObserver { [weak self] in self?.render() }

            let sidebar = SidebarViewController(session: session)
            let topBar = TopBarView(session: session)
            self.sidebar = sidebar
            self.topBar = topBar
            chrome.install(sidebar: sidebar.view, topBar: topBar)
            controller.setChrome(chrome)
            chrome.setLayout(controller.chromeState)
            wireSidebar(sidebar, in: controller)

            wireCommandBar(session, in: controller)
            wireDownloads(session, topBar: topBar)
            // §4.4: the New Tab page, the archive browser and the token→CSS
            // palette. Must follow the sidebar, whose Archive row it claims.
            InternalPagesInstaller.install(session: session, sidebar: sidebar)
            // §19.2/§19.5: the hibernation sweep, the auto-archive clock and the
            // memory-pressure source. Before the first tab, so the budget is
            // never briefly unenforced.
            session.installLifecycle()
            // A Space with nothing in it would otherwise show an empty content
            // card. A restore that *has* tabs deliberately selects none of them
            // (§19.4) — that is the memory budget, not a missing page.
            if session.activeTabID == nil, session.tabs.isEmpty {
                session.newTab(url: InternalPages.Page.newTab.url)
            }
            render()
        } catch {
            NSApp.presentError(error)
        }
    }

    /// The sidebar's outbound closures. It deliberately owns none of these:
    /// toggling the layout and resizing the window's chrome column are the
    /// window controller's, and turning typed text into a URL is §9.2's.
    ///
    /// **Until this existed none of them were connected**, which is why §3.7's
    /// resize handle drew, hovered, dragged — and did nothing at all.
    private func wireSidebar(_ sidebar: SidebarViewController, in controller: BrowserWindowController) {
        sidebar.onToggleSidebar = { [weak self] in self?.toggleChromeLayout() }
        sidebar.onSubmitURL = { [weak self] text in self?.open(text) }
        // Live during the drag and again on mouse-up: `setSidebarWidth` is
        // idempotent and the committed value is the one that gets persisted.
        sidebar.onWidthChange = { [weak controller] width in controller?.setSidebarWidth(width) }
        // §7.1: come back at the width the user left, not at the default — and
        // without animating a width the user never saw change.
        controller.setSidebarWidth(sidebar.preferredWidth)
    }

    /// §3.2's pill commits here: a URL is loaded, anything else is a search.
    /// Both shapes come from `CommandBarURL` so the pill and the Command Bar
    /// cannot disagree about which is which (§9.2).
    private func open(_ text: String) {
        guard let url = CommandBarURL.direct(from: text) ?? CommandBarURL.search(for: text) else { return }
        session?.load(url)
    }

    /// `⌘T` and `⌘L` (§9.1). The bar is one object shared by both entry points
    /// and by the top bar's pill.
    private func wireCommandBar(_ session: BrowserSession, in controller: BrowserWindowController) {
        let adaptive = adaptive ?? AdaptiveHistory(store: session.store)
        self.adaptive = adaptive
        let bar = CommandBarController(session: session, adaptive: adaptive)
        commandBar = bar
        // The results the bar cannot perform itself (§9.2).
        bar.onExternalAction = { [weak self] action in self?.perform(action) }
        // Weak: the bar holds the session, so a strong capture here is a cycle.
        session.presentCommandBar = { [weak bar, weak controller] mode in
            guard let bar, let window = controller?.window else { return }
            bar.present(mode, in: window)
        }
    }

    private func perform(_ action: CommandBarAction) {
        switch action {
        case let .unarchiveTab(id):
            session?.unarchiveTab(id)
        case .command(.toggleSidebar):
            toggleChromeLayout()
        case .command(.newSpace):
            guard let session else { return }
            // §23.1's rename UI does not exist yet, so the Space arrives named
            // and the user renames it there when it does.
            Task { try? await session.createSpace(name: String(localized: "New Space")) }
        case .activateTab, .open:
            // The bar performs these itself; they never reach here.
            break
        }
    }

    /// `⌘L`: the pill expands in place when a layout owns one (§3.2, §4), and
    /// falls back to the Command Bar's edit mode when none is installed.
    func editLocation() {
        guard let session else { return }
        if let focus = session.focusURLField {
            focus()
        } else if let bar = commandBar, let window = browserWindow?.window {
            bar.present(.editCurrentURL, in: window)
        }
    }

    private func wireDownloads(_ session: BrowserSession, topBar: TopBarView) {
        let manager = DownloadManager()
        downloads = manager
        let panel = DownloadsListPanel(manager: manager)
        downloadsPanel = panel
        // §30.15: the completion popover is the primary surface and appears by
        // itself; the button and the View menu open the secondary panel.
        topBar.onDownloads = { [weak panel] _ in panel?.toggle() }
        session.onDownload = { [weak manager] download in manager?.begin(download) }
        // §5's popover points at the top bar's downloads button when the bar is
        // showing; it falls back to a plain window-anchored panel when it is not.
        manager.anchorProvider = { [weak topBar] in topBar?.downloadsAnchor }
        // `WKDownload.webView` is weak and the originating tab may be cold, so
        // a retry resumes through whichever tab is live now.
        manager.webViewProvider = { [weak session] in
            guard let session, let id = session.activeTabID else { return nil }
            return session.controller(for: id)?.webView
        }
    }

    /// Re-reads the session. Structural only — a tab's progress and title reach
    /// their row through `addTabStateObserver`, not through here.
    private func render() {
        guard let session else { return }
        // `webView(for:)` wakes a cold tab, which is exactly right for the one
        // tab the user has selected and wrong for any other (§19.4).
        browserWindow?.setContent(session.activeTabID.flatMap { session.webView(for: $0) })
        MainMenu.setSpaces(session.spaces.map(\.name), in: NSApp)
    }

    /// `⌘S` (§8, §4.1): sidebar ↔ top bar, cross-fading the chrome while the
    /// window controller re-anchors the traffic lights in its own transaction.
    func toggleChromeLayout() {
        guard let controller = browserWindow else { return }
        let next: ChromeState = controller.chromeState == .topBar
            ? .sidebar(width: Tokens.Metric.sidebarWidth.default)
            : .topBar
        chrome.setLayout(next)
        controller.setChromeState(next)
    }

    // MARK: - Termination

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `recordVisit` buffers and `interactionState` dies with its WebContent
    /// process, so quitting has real async work to do. `.terminateLater` is the
    /// only way to do it — `applicationWillTerminate` cannot await.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        await session?.persist()
        try? await store?.flush()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release the web views while AppKit is still running rather than
        // leaving WebContent processes to process teardown.
        session?.tearDown()
        session = nil
        browserWindow = nil
    }

    private static var databaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "luna.sqlite")
    }
}
