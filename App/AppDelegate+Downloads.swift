//
//  AppDelegate+Downloads.swift
//  Luna
//
//  §5.0's flight and §15.3's list, wired to whichever Downloads button the
//  chrome on screen is showing. Split out of `AppDelegate.swift` for its type
//  body length.
//
//  `DownloadsSite` is why this is worth being one file: there are two chromes,
//  and exactly one place that knows it. The flight, the list and `⌘⌥L` all ask
//  it the same question.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// One manager and one list for the app, wired to each window's two
    /// buttons. §15.3's list is a pop-out and a pop-out is told which window to
    /// stand in, so one of it serves all of them — and a file that lands while
    /// you are in another window still has one list to appear in.
    func wireDownloads(in window: BrowserWindow) {
        let session = window.session
        let controller = window.controller
        let (manager, panel) = downloadsManagerAndPanel()
        guard let sidebar = window.sidebar, let topBar = window.topBar else { return }
        // §15.3's list is the whole of the downloads UI, and these two
        // buttons are the two places it stands. Same pop-out, two ends of the
        // window, so the edge is the caller's to say — exactly as History's is.
        topBar.onDownloads = { [weak panel, weak controller] anchor in
            guard let panel, let window = controller?.window else { return }
            panel.toggle(in: window, from: anchor, edge: .below)
        }
        sidebar.onOpenDownloads = { [weak panel, weak controller, weak sidebar] in
            guard let panel, let sidebar, let window = controller?.window else { return }
            panel.toggle(in: window, from: sidebar.downloadsAnchor, edge: .above)
        }
        // §15.3's list belongs to the Space the page was in, so the file is
        // stamped with it as it starts rather than looked up later — by the time
        // it lands the user may be in the other Space.
        session.onDownload = { [weak manager, weak session] download in
            manager?.begin(download, inSpace: session?.activeSpaceID, session: session)
        }
    }

    /// The app's one manager and list, and the hooks that are the app's rather
    /// than any one window's. Wired once: a hook set per window answers for
    /// whichever window was wired last, which after `⌘⇧N` was the private one.
    private func downloadsManagerAndPanel() -> (DownloadManager, DownloadsPanelController) {
        if let downloads, let downloadsPanel { return (downloads, downloadsPanel) }
        let manager = DownloadManager()
        let panel = DownloadsPanelController(manager: manager)
        downloads = manager
        downloadsPanel = panel
        panel.activeSpace = { [weak self] host in
            self?.windows.first { $0.controller.window === host }?.activeSpaceID
        }
        manager.agentApproval = { [weak self] webView, name, risky in
            await self?.control?.approveDownload(named: name, risky: risky, from: webView)
        }
        // §5.0: the file leaves the page and lands on whichever Downloads
        // button this layout is showing — unless the front window is showing
        // another Space, because a list that opens without the row it opened
        // for is worse than no list at all.
        manager.onBegin = { [weak self] item in
            guard let self, item.spaceID == front?.activeSpaceID else { return }
            announceDownload(item)
        }
        manager.onFinish = { [weak self] item in
            guard let self, item.spaceID == front?.activeSpaceID else { return }
            announceCompletion()
        }
        return (manager, panel)
    }

    /// Where a download ends up, in the layout that is on screen: the button
    /// it lands on, the glass that catches it, and which way a pop-out grows
    /// out of it.
    ///
    /// The one place that knows there are two chromes. §5.0's flight,
    /// §15.3's list and `⌘⌥L` are all asking this same question, and three
    /// separate answers to it is how a feature comes to work in one layout and
    /// not the other.
    ///
    /// It reads the setting rather than the window's state, because a
    /// collapsed sidebar is still the sidebar layout — its button is parked
    /// off-screen and everything here falls back to the corner it would have
    /// been in.
    private struct DownloadsSite {
        let anchor: NSView
        let catcher: NSView
        /// Which way a pop-out grows out of the button — and, because it is the
        /// same fact, which end of the window the button is at: `.below` means
        /// it hangs off §4's capsule at the head, `.above` that it stands on
        /// §3.5's cylinder at the foot.
        let edge: PopoutEdge
    }

    private func downloadsSite() -> DownloadsSite? {
        switch Settings.chromeLayout {
        case .topBar:
            guard let bar = topBar, let anchor = bar.downloadsAnchor else { return nil }
            return DownloadsSite(anchor: anchor, catcher: bar.downloadsCatcher, edge: .below)
        case .sidebar:
            guard let sidebar else { return nil }
            return DownloadsSite(
                anchor: sidebar.downloadsAnchor,
                catcher: sidebar.downloadsCatcher,
                edge: .above
            )
        }
    }

    /// `⌘⌥L`, from `BrowserCommands`: §15.3's list, on whichever Downloads
    /// button the layout on screen is showing.
    ///
    /// The menu item cannot hand over an anchor the way a button can, which is
    /// what `downloadsSite()` is for.
    func showDownloadsList() {
        guard let panel = downloadsPanel,
              let window = browserWindow?.window,
              let site = downloadsSite()
        else { return }
        panel.toggle(in: window, from: site.anchor, edge: site.edge)
    }

    /// §5.0 — a download has started. The file's own icon leaves the page on
    /// an arc, the Downloads button's glass catches it, and §15.3's list opens
    /// underneath with the bar running.
    private func announceDownload(_ item: DownloadItem) {
        guard let panel = downloadsPanel,
              let window = browserWindow?.window,
              let root = window.contentView,
              let site = downloadsSite()
        else { return }
        let button = root.convert(site.anchor.bounds, from: site.anchor)
        DownloadFlightView.fly(
            item.icon,
            from: downloadOrigin(in: root),
            to: CGPoint(x: button.midX, y: button.midY),
            in: root
        ) { [weak panel] in
            Tokens.Motion.catchDownload(on: site.catcher)
            panel?.announce(in: window, from: site.anchor, edge: site.edge)
        }
    }

    /// §5 — a download landed, announced on the Downloads button the layout
    /// is actually showing: §15.3's list, standing on the button the file was
    /// thrown at (§5.0) with the same row finishing on it.
    ///
    /// One surface, both chromes. There used to be a second one — a panel that
    /// floated outside the window above the top edge with a tail pointing down
    /// into the top bar's button — and it was wrong twice over. In the sidebar
    /// layout it appeared in the opposite corner of the screen from the button
    /// it was describing, pointing at the sidebar toggle; and in the top bar
    /// layout, where it was at least aimed correctly, it was a second card
    /// saying what the list under it already said. A download that has just
    /// been thrown at a button should be found *at* that button.
    ///
    /// A list already standing open is left alone: `announce` is a no-op on a
    /// panel that is up, and the row it is showing is this one — which is why
    /// the item itself is not a parameter. The list reads the manager's items
    /// for the Space it is standing in.
    private func announceCompletion() {
        // A small file can finish before its icon lands, and the list opening
        // under a file still in the air cuts the throw short. The landing
        // opens it, on the row that has already finished.
        guard DownloadFlightView.inAir == 0 else { return }
        guard let site = downloadsSite(), let window = browserWindow?.window else { return }
        downloadsPanel?.announce(in: window, from: site.anchor, edge: site.edge)
    }

    /// Where the file leaves from: the pointer, because that is where the
    /// link the user just clicked was.
    ///
    /// There is no honest alternative. WebKit hands over a `WKDownload` and an
    /// originating frame; it does not say which element started it or where on
    /// the page that element was drawn, and asking the page through JavaScript
    /// would be Luna running script on every site to decorate an animation.
    /// The pointer is right for every download a click started, which is
    /// almost all of them.
    ///
    /// The centre of the content is the fallback, for the ones a click did not
    /// start — a redirect, a `⌘⌥L` retry, a page that downloaded on load. A
    /// file appearing to leave from the middle of the page is a thing that
    /// came from the page, which is exactly what happened.
    private func downloadOrigin(in root: NSView) -> CGPoint {
        let centre = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
        guard let window = root.window else { return centre }
        let pointer = root.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return root.bounds.contains(pointer) ? pointer : centre
    }
}
