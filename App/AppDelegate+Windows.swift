//
//  AppDelegate+Windows.swift
//  Luna
//
//  §22.6: opening a window, filling it with chrome, and keeping track of which
//  one the user is in.
//
//  `buildChrome` is the whole of what used to sit in the middle of
//  `startSession`, unchanged except that it writes into a `BrowserWindow`
//  instead of into the app. That is the point of the move: every one of these
//  objects is per window, and the app holding one of each is what made a second
//  window overwrite the first one's sidebar.
//
//  The front window is tracked rather than asked for. `NSApp.keyWindow` is nil
//  while a sheet, a pop-out or the Settings window is up, and every command
//  Luna has would then be about no window at all.
//

import AppKit
import BrowserKit

extension AppDelegate {

    // MARK: - The two commands

    /// `⌘N`. A second window onto the same Spaces and the same tabs, with its
    /// own idea of which tab it is on (§22.6).
    @objc func newWindow(_ sender: Any?) {
        openBrowserWindow(isPrivate: false)
    }

    /// `⌘⇧N` (§5.6).
    @objc func newPrivateWindow(_ sender: Any?) {
        openBrowserWindow(isPrivate: true)
    }

    // MARK: - Opening one

    /// `⌘N` and `⌘⇧N`. The new window opens where the front one is standing —
    /// the same Space, nothing selected, which is what a cold launch gives too
    /// (§19.4).
    ///
    /// A private window brings its own session and its own database; see
    /// `privateSession()`. Making one can fail — it is a file on disk — and a
    /// failure is presented rather than swallowed, because the user asked for
    /// a window and would otherwise get silence.
    func openBrowserWindow(isPrivate: Bool) {
        guard let session = front?.session else { return }
        let controller = BrowserWindowController(remembersFrame: windows.isEmpty)
        if isPrivate {
            Task { await openPrivateWindow(in: controller) }
            return
        }
        let window = BrowserWindow(session: session, controller: controller)
        adopt(window)
        window.applyChromeLayout(animated: false)
        window.render()
    }

    /// A new window lands down and across from the one it came out of, rather
    /// than exactly on top of it.
    ///
    /// Not `NSWindow.cascadeTopLeft(from:)`, which was measured doing nothing
    /// here: it places the window's top-left *at* the point it is given and
    /// only offsets the one after that, so handing it the previous window's
    /// corner puts the new window exactly over it. The offset is Luna's.
    ///
    /// Clamped to the screen the window it came from is on, because a cascade
    /// that walks off the bottom right is how the fifth window ends up with its
    /// traffic lights past the edge.
    private func cascade(_ controller: BrowserWindowController, after previous: BrowserWindowController?) {
        guard let window = controller.window, let previous = previous?.window else { return }
        let step = Tokens.Metric.windowCascadeStep
        var corner = NSPoint(x: previous.frame.minX + step, y: previous.frame.maxY - step)
        if let screen = previous.screen?.visibleFrame {
            corner.x = min(corner.x, screen.maxX - window.frame.width)
            corner.y = max(corner.y, screen.minY + window.frame.height)
        }
        window.setFrameTopLeftPoint(corner)
    }

    /// Takes a new window into the app: on screen, on the list, and in front.
    func adopt(_ window: BrowserWindow) {
        windows.append(window)
        buildChrome(in: window)
        window.controller.onBecameKey = { [weak self, weak window] in
            guard let self, let window else { return }
            front = window
            window.session.setKeyWindow(window.id)
        }
        window.controller.onClosed = { [weak self, weak window] in
            guard let self, let window else { return }
            retire(window)
        }
        front = window
        window.session.setKeyWindow(window.id)
        let previous = windows.dropLast().last?.controller
        window.controller.showWindow(self)
        // After `showWindow`, not before it: AppKit gives a window its frame on
        // the way on screen — the autosaved one, or its own cascade for a
        // second window of the same app — and a frame set before that is
        // overwritten without a word.
        cascade(window.controller, after: previous)
        NSApp.activate()
    }

    /// A window has closed. Its pages stay — they belong to the session, and
    /// another window may be showing one — unless it was a §5.6 window, whose
    /// session is its own and goes with it.
    private func retire(_ window: BrowserWindow) {
        window.close()
        windows.removeAll { $0 === window }
        if let home = window.privateHome { endPrivateSession(window.session, home: home) }
        guard front === window else { return }
        front = windows.last
        if let front { front.session.setKeyWindow(front.id) }
    }

    // MARK: - Filling one

    /// Everything a window is made of, in the order it has to be made in.
    func buildChrome(in window: BrowserWindow) {
        let session = window.session
        let controller = window.controller
        session.hostWindow = controller.window
        window.observation = session.addChangeObserver { [weak self] in self?.render() }

        let sidebar = SidebarViewController(session: session, windowID: window.id)
        let topBar = TopBarView(session: session, windowID: window.id)
        window.sidebar = sidebar
        window.topBar = topBar
        window.chrome.install(sidebar: sidebar.view, topBar: topBar)
        // The list's row views do not survive the layout it is hidden in;
        // see `ChromeHostView.onShowSidebar`.
        window.chrome.onShowSidebar = { [weak sidebar] in sidebar?.willAppear() }
        // §7.2: the pointer resting on a peeked sidebar keeps it out. The
        // edge strip that summoned it is underneath by then.
        window.chrome.onPointerInside = { [weak controller] inside in
            controller?.setPointerInsideChrome(inside)
        }
        controller.setChrome(window.chrome)
        sidebar.onSpaceGradientChange = { [weak controller] gradient in
            controller?.setSpaceGradient(gradient)
        }
        wireSidebar(sidebar, in: window)
        wireSpaceStrip(topBar, in: window)
        wirePageChrome(in: window)
        wireLoadLine(in: window)
        // Last of the three address bars to claim `⌘L`, and the one that knows
        // which of them is on screen.
        wireEditLocation(in: window)
        // §7.1: the layout the user chose in Settings, applied before the first
        // frame the window shows with content in it.
        window.applyChromeLayout(animated: false)
        wireCommandBar(in: window)
        wireHistory(in: window)
        wireDownloads(in: window)
    }

    /// §3.5's Space strip, at the head of §4's bar. The same four verbs the
    /// sidebar's foot is wired to, and the one difference is New Space: the
    /// column has a place to show a Space being made in (`SpaceCreationView`)
    /// and a bar does not, so it simply makes one and switches to it.
    private func wireSpaceStrip(_ topBar: TopBarView, in window: BrowserWindow) {
        let session = window.session
        topBar.onSwitchSpace = { [weak window] id in
            guard let window else { return }
            session.switchSpace(id, inWindow: window.id)
        }
        // §8.2 / §13.6. Silent on failure, as the sidebar's copy is: a colour
        // that did not persist is a disappointment on the next launch, not
        // something to interrupt the user mid-browse with.
        topBar.onSetGradient = { [weak session] space, gradient in
            Task { try? await session?.setGradient(gradient, forSpace: space) }
        }
        topBar.onEditSpaces = { [weak self] in self?.showSettings(section: SpacesSection.id) }
        topBar.onNewSpace = { [weak session] in
            guard let session else { return }
            Task { try? await session.createSpace(name: String(localized: "New Space")) }
        }
    }

    /// The sidebar's outbound closures. It deliberately owns none of these:
    /// toggling the layout and resizing the window's chrome column are the
    /// window controller's, and turning typed text into a URL is §9.2's.
    private func wireSidebar(_ sidebar: SidebarViewController, in window: BrowserWindow) {
        sidebar.onToggleSidebar = { [weak window] in window?.toggleSidebar() }
        // Live during the drag and again on mouse-up: `setSidebarWidth` is
        // idempotent and the committed value is the one that gets persisted.
        sidebar.onWidthChange = { [weak window] width in window?.controller.setSidebarWidth(width) }
        // §7.1: come back at the width the user left, not at the default — and
        // without animating a width the user never saw change.
        window.controller.setSidebarWidth(sidebar.preferredWidth)
        sidebar.willAppear()
    }

    /// §3.5's History button (§6.4). A pop-out from the button, not a tab and
    /// not a panel over the page: looking something up in your history is a
    /// glance, and a glance should neither leave a tab behind to close nor take
    /// the page away while you take it.
    private func wireHistory(in window: BrowserWindow) {
        let panel = HistoryPanelController(session: window.session)
        window.historyPanel = panel
        let controller = window.controller
        window.sidebar?.onOpenHistory = { [weak panel, weak controller, weak window] in
            guard let panel, let sidebar = window?.sidebar, let host = controller?.window else { return }
            // The sidebar's button is at the foot of the window, so the pop-out
            // grows up out of it; the top bar's is at the head, so it grows
            // down. One panel, one controller, two directions.
            panel.toggle(in: host, from: sidebar.historyAnchor, edge: .above)
        }
        window.topBar?.onHistory = { [weak panel, weak controller] anchor in
            guard let panel, let host = controller?.window else { return }
            panel.toggle(in: host, from: anchor, edge: .below)
        }
    }
}
