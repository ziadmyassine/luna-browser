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
    func wirePageChrome(in window: BrowserWindow) {
        let page = PageChromeController(session: window.session, windowID: window.id)
        window.pageChrome = page
        page.onToggleSidebar = { [weak window] in window?.toggleSidebar() }
        page.onBandHeight = { [weak window] height, animated in
            window?.controller.setPageBarInset(height, animated: animated)
        }
        window.controller.setPageOverlay(page.view)
    }

    /// §20.1's `⌘L` belongs to whichever address bar is on screen — §3.2's in
    /// the column, §3.2b's on the page, §4's in the top bar — and all three now
    /// answer it the same way: by handing the address to §9.1, which opens
    /// standing on the pill that asked (`CommandBarAnchor`).
    ///
    /// Chained, not assigned, which is how `TopBarView` claims it: each layout
    /// answers only for itself and passes the command on otherwise. This one is
    /// registered last and asks the two questions the others cannot — whether
    /// the page bar is showing, and whether the column's pill is on screen.
    ///
    /// Without it `⌘L` did nothing in the sidebar layout: the top bar's claim
    /// was the whole chain, it answered "not my layout", and the fallback in
    /// `editLocation()` was never reached because the closure it tests for was
    /// not nil.
    func wireEditLocation(in window: BrowserWindow) {
        let previous = window.session.urlField(inWindow: window.id)
        window.session.setURLField({ [weak window] in
            guard let window else { return previous?() ?? () }
            if let page = window.pageChrome, page.isOnScreen { return page.beginEditing() }
            if let sidebar = window.sidebar, sidebar.showsURLPill { return sidebar.beginEditingURL() }
            previous?()
        }, inWindow: window.id)
    }

    /// §3.2c's fallback line, which is the one host with nothing of its own to
    /// observe: the three pills are each fed by the controller that owns them,
    /// and the window's top edge is fed from here.
    ///
    /// Registered, not assigned, like every other observer on this session
    /// — and both halves are needed. The state observer carries the progress;
    /// the change observer carries the switch, which no tab state reports,
    /// and without it the line kept counting the tab the user just left.
    func wireLoadLine(in window: BrowserWindow) {
        let session = window.session
        let feed: @MainActor (UUID?) -> Void = { [weak window] tick in
            guard let window else { return }
            let controller = window.controller
            guard let active = window.activeTabID else {
                return controller.setLoadProgress(nil, for: nil)
            }
            // A background tab's tick is not this line's business. The line
            // describes the page the window is showing; a second tab loading
            // behind it used to wipe it.
            guard tick == nil || tick == active else { return }
            // A cold tab has no state to read, and that is the honest answer:
            // nothing is loading in a tab that has no web view.
            controller.setLoadProgress(window.session.controller(for: active)?.state, for: active)
        }
        window.loadLineObservations = [
            session.addTabStateObserver { id, _ in feed(id) },
            session.addChangeObserver { feed(nil) }
        ]
    }
}
