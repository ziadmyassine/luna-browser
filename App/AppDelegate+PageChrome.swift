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
        // The same URL-or-query parse the sidebar's pill commits through (§9.2).
        page.onSubmitURL = { [weak self] text in self?.open(text) }
        controller.setPageOverlay(page.view)
    }

    /// The sidebar drops the pill and the page bar picks it up, or the other way
    /// round.
    ///
    /// **Both ends are told by one reader.** `Settings.searchBarIsOnPage`
    /// resolves the placement against the layout, so the sidebar cannot end up
    /// having dropped its pill in a layout with no page bar to put it in.
    func applySearchBarPlacement(animated: Bool) {
        let onPage = Settings.searchBarIsOnPage
        sidebar?.setSearchBarOnPage(onPage)
        pageChrome?.setActive(onPage, animated: animated)
    }
}
