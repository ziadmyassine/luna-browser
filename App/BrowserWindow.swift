//
//  BrowserWindow.swift
//  Luna
//
//  §22.6: one browser window, and everything that is built once per window.
//
//  All of this used to be fields on `AppDelegate`, which was honest while there
//  was one window and became a lie the moment there were two: a sidebar, a top
//  bar, a page bar and a Command Bar are per window, and the app holding one of
//  each meant the second window's chrome overwrote the first window's.
//
//  What stayed on the app is what there is genuinely one of: the store, §9.3's
//  use counts, §15's download manager and the Settings window. `AppDelegate`
//  still assembles this — see `AppDelegate+Windows.swift` — because that is
//  what that file is for; this is the box the assembly goes into, plus the two
//  things only a window can answer: what is on its own content card, and which
//  chrome it is wearing.
//
//  `session` is a `let` and may be shared. Ordinary windows all hold the one
//  session, because the tab list is a database and two copies of it would race
//  each other onto disk; a §5.6 private window holds one of its own, which is
//  what makes it private and what lets it be thrown away whole.
//

import AppKit
import BrowserKit

@MainActor
final class BrowserWindow {

    /// The name the session knows this window by (§22.6).
    let id = UUID()
    let session: BrowserSession
    let controller: BrowserWindowController
    let chrome = ChromeHostView()
    /// §5.6: the throwaway directory this window's session lives in, deleted
    /// when the window closes. Nil for an ordinary window, which shares the
    /// app's one session and its real database — and that is the whole of what
    /// `isPrivate` means, so it is read from here rather than stored twice.
    let privateHome: URL?
    var isPrivate: Bool { privateHome != nil }

    var sidebar: SidebarViewController?
    var topBar: TopBarView?
    var pageChrome: PageChromeController?
    var commandBar: CommandBarController?
    var historyPanel: HistoryPanelController?
    /// The session registration that redraws this window. Held here so a closed
    /// window stops being called without anyone having to remember to say so.
    var observation: ObservationToken?
    /// §3.2c's window-edge line. Two tokens — see `wireLoadLine`.
    var loadLineObservations: [ObservationToken] = []

    /// - Parameter controller: made by the caller, because the launch puts a
    ///   window on screen before there is a session to put in it — §19.1's
    ///   800 ms is a frame budget, not a disk budget.
    init(session: BrowserSession, controller: BrowserWindowController, privateHome: URL? = nil) {
        self.session = session
        self.controller = controller
        self.privateHome = privateHome
        session.openWindow(id)
    }

    // MARK: - What this window is showing

    /// Re-reads the session for this window alone. Structural only — a tab's
    /// progress and title reach their row through `addTabStateObserver`.
    ///
    /// `webView(for:)` wakes a cold tab, which is right for the one tab this
    /// window has selected and wrong for any other (§19.4). A window showing
    /// the same tab as another gets the same web view, and AppKit moves a view
    /// rather than copying it — so the page follows the window that asked last,
    /// which is the front one.
    func render() {
        controller.setContent(activeTabID.flatMap { session.webView(for: $0) })
        nameTheWindow()
    }

    /// The window's title, which §30.1 hides and macOS still reads: the Window
    /// menu, Mission Control and the app switcher all show it, and with two
    /// windows open a menu offering "Luna" and "Luna" is a menu that cannot be
    /// used. The page it is showing, or the Space it is standing in when it is
    /// showing none.
    private func nameTheWindow() {
        let page = activeTabID.flatMap { session.tab($0)?.title }
        let space = session.space(session.activeSpaceID(inWindow: id))?.name
        controller.window?.title = [page, space].compactMap { $0 }
            .first { !$0.isEmpty } ?? "Luna"
    }

    var activeTabID: UUID? { session.activeTabID(inWindow: id) }

    // MARK: - The chrome it wears

    /// `⌘S` and §3.1's toggle button: hide or show the sidebar, so the page
    /// takes the whole window.
    func toggleSidebar() {
        guard controller.canCollapseSidebar else { return }
        controller.setSidebarCollapsed(!controller.isSidebarCollapsed)
    }

    /// Puts the window into whichever chrome `Settings.chromeLayout` names.
    /// The cross-fade and the frame animation run on the same tick (§4.1).
    func applyChromeLayout(animated: Bool) {
        // Before the early return below, not after it. §3.2b's placement can
        // change while the layout does not, and it is the only setting here
        // whose effect is nothing at all if the chrome state happens to match.
        applySearchBarPlacement(animated: animated)
        let edge = Settings.sidebarEdge
        let state: ChromeState = switch Settings.chromeLayout {
        // A hidden sidebar stays hidden. `⌘S` and this setting are different
        // decisions, and rebuilding the state from the layout alone put the
        // column back on screen every time any preference changed.
        case .sidebar where controller.isSidebarCollapsed: .sidebarCollapsed(edge: edge)
        case .sidebar: .sidebar(
            width: sidebar?.preferredWidth ?? Tokens.Metric.sidebarWidth.default,
            edge: edge
        )
        case .topBar: .topBar
        }
        // The handle drags the divider, and which way is "wider" depends on
        // which side the column is on.
        sidebar?.sidebarEdge = edge
        guard state != controller.chromeState else { return }
        chrome.setLayout(state)
        if animated {
            controller.setChromeState(state)
        } else {
            controller.setChromeStateWithoutAnimation(state)
        }
    }

    /// The sidebar drops the pill and the page bar picks it up, or the other
    /// way round. Both ends are told by one reader: `Settings.searchBarIsOnPage`
    /// resolves the placement against the layout, so the sidebar cannot end up
    /// having dropped its pill in a layout with no page bar to put it in.
    func applySearchBarPlacement(animated: Bool) {
        let onPage = Settings.searchBarIsOnPage
        sidebar?.setSearchBarOnPage(onPage)
        pageChrome?.setActive(onPage, animated: animated)
        // §3.2c's third listener: the window only wears the load line when
        // neither of the two above is showing an address.
        controller.setSearchBarOnPage(onPage)
    }

    // MARK: - Going away

    /// Drops this window's registrations and tells the session it has gone.
    /// The pages are not torn down — they belong to the session, and another
    /// window may be showing one. A private window's session is the exception
    /// and is ended by the app, which is the only thing that knows it was the
    /// last window on it.
    func close() {
        observation = nil
        loadLineObservations = []
        historyPanel = nil
        commandBar = nil
        session.closeWindow(id)
    }
}
