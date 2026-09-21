//
//  AppDelegate+PageChrome.swift
//  Luna
//
//  §3.2b's two lines of wiring, and the one place that decides which of the two
//  address bars is the one on screen.
//
//  A file of its own because `AppDelegate.swift` is the app's assembly seam and
//  already the longest file in `App/`; this is a seam within it, not a new
//  responsibility.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// Built whether or not the setting has it on screen — it costs one hidden
    /// view, and building it lazily would mean the first flip of the setting
    /// had no bar to animate in.
    func wirePageChrome(_ session: BrowserSession, in controller: BrowserWindowController) {
        let page = PageChromeController(session: session)
        pageChrome = page
        page.onToggleSidebar = { [weak self] in self?.toggleSidebar() }
        page.onBandHeight = { [weak controller] height, animated in
            controller?.setPageBarInset(height, animated: animated)
        }
        controller.setPageOverlay(page.view)
    }

    /// §20.1's `⌘L` belongs to whichever address bar is on screen — §3.2's in
    /// the column, §3.2b's on the page, §4's in the top bar — and all three now
    /// answer it the same way: by handing the address to §9.1, which opens
    /// standing on the pill that asked (`CommandBarAnchor`).
    ///
    /// Chained, not assigned, which is how `TopBarView` claims it: each
    /// layout answers only for itself and passes the command on otherwise. This
    /// one is registered last and asks the two questions the others cannot —
    /// whether the page bar is the one showing, and whether the column's pill
    /// is on screen at all.
    ///
    /// Without it `⌘L` did nothing in the sidebar layout: the top bar's claim
    /// was the whole chain, it answered "not my layout", and the fallback in
    /// `editLocation()` was never reached because the closure it tests for was
    /// not nil.
    func wireEditLocation(_ session: BrowserSession, sidebar: SidebarViewController?) {
        let previous = session.focusURLField
        session.focusURLField = { [weak self, weak sidebar] in
            guard let self else { return previous?() ?? () }
            if let page = pageChrome, page.isOnScreen { return page.beginEditing() }
            if let sidebar, sidebar.showsURLPill { return sidebar.beginEditingURL() }
            previous?()
        }
    }

    /// The sidebar drops the pill and the page bar picks it up, or the other way
    /// round.
    ///
    /// Both ends are told by one reader. `Settings.searchBarIsOnPage`
    /// resolves the placement against the layout, so the sidebar cannot end up
    /// having dropped its pill in a layout with no page bar to put it in.
    func applySearchBarPlacement(animated: Bool) {
        let onPage = Settings.searchBarIsOnPage
        sidebar?.setSearchBarOnPage(onPage)
        pageChrome?.setActive(onPage, animated: animated)
        // §3.2c's third listener: the window only wears the load line when
        // neither of the two above is showing an address.
        browserWindow?.setSearchBarOnPage(onPage)
    }

    /// §3.2c's fallback line, which is the one host with nothing of its own to
    /// observe: the three pills are each fed by the controller that owns them,
    /// and the window's top edge is fed from here.
    ///
    /// Registered, not assigned, like every other observer on this session
    /// — and both halves are needed. The state observer carries the progress;
    /// the change observer carries the switch, which no tab state reports,
    /// and without it the line kept counting the tab the user just left.
    func wireLoadLine(_ session: BrowserSession, in controller: BrowserWindowController) {
        let feed: @MainActor (UUID?) -> Void = { [weak session, weak controller] tick in
            guard let session, let controller else { return }
            guard let active = session.activeTabID else {
                return controller.setLoadProgress(nil, for: nil)
            }
            // A background tab's tick is not this line's business. The line
            // describes the page the window is showing; a second tab loading
            // behind it used to wipe it.
            guard tick == nil || tick == active else { return }
            // A cold tab has no state to read, and that is the honest answer:
            // nothing is loading in a tab that has no web view.
            controller.setLoadProgress(session.controller(for: active)?.state, for: active)
        }
        loadLineObservations = [
            session.addTabStateObserver { id, _ in feed(id) },
            session.addChangeObserver { feed(nil) }
        ]
    }
}
