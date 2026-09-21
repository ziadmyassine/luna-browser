//
//  BrowserSession+Commands.swift
//  Luna
//
//  The work behind §20.1's newer menu items: page zoom, a reload that means it,
//  copying the address, and the two bulk tab commands.
//
//  They are here rather than in `BrowserSession+Tabs` because that file is the
//  tab lifecycle and this is a drawer of commands — and because a menu command
//  needs one thing the lifecycle does not: an honest answer to "can you do this
//  right now", so the item dims instead of doing nothing. Each pair below is a
//  `can…` and a `do…` for exactly that reason.
//

import AppKit
import BrowserKit

extension BrowserSession {

    // MARK: - The page

    /// What the active tab is showing, live — `state.url` rather than the tab
    /// row, which is a pass behind during an in-tab navigation.
    var activeURL: URL? {
        guard let id = activeTabID else { return nil }
        return controller(for: id)?.state.url ?? tab(id)?.url
    }

    /// The page's own title, falling back to the row's and then to the host.
    /// Never empty: it is about to be the visible half of a Markdown link, and
    /// `[](https://…)` is not a link anybody can click.
    var activeTitle: String {
        guard let id = activeTabID else { return "" }
        let live = controller(for: id)?.state.title ?? ""
        let stored = tab(id)?.title ?? ""
        let title = live.isEmpty ? stored : live
        guard title.isEmpty else { return title }
        return activeURL?.host(percentEncoded: false) ?? ""
    }

    /// ⇧⌘R. `reloadFromOrigin` rather than `reload`: the point of asking twice
    /// is to get past the cache, and `reload` is allowed to answer out of it.
    func reloadIgnoringCache() {
        activeController?.webView?.reloadFromOrigin()
    }

    // MARK: - Zoom (§20.1)

    /// The ladder both zoom commands walk. Safari's, give or take: fine steps
    /// around 100 % where the user is nudging, coarse ones at the ends where
    /// they have already decided.
    static let zoomLevels: [CGFloat] = [0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// **Not persisted, and that is the honest version rather than the finished
    /// one.** Zoom lives on the `WKWebView`, so it survives as long as the tab
    /// stays awake and is lost when §19.2 hibernates it. Per-site zoom is a
    /// stored preference with its own row in Settings and its own rules about
    /// which of a site's subdomains it covers; promising it here by quietly
    /// remembering the number would be the harder half of that feature done
    /// invisibly and the easy half not done at all.
    var pageZoom: CGFloat {
        activeController?.webView?.pageZoom ?? 1
    }

    /// Moves `steps` rungs up or down the ladder from wherever the page is now.
    func zoomPage(by steps: Int) {
        guard let webView = activeController?.webView else { return }
        let levels = Self.zoomLevels
        let current = webView.pageZoom
        // Nearest rung, not an exact match: a page can arrive carrying a zoom
        // that is between two of ours, and `firstIndex(of:)` on a `CGFloat`
        // would then start counting from the bottom of the ladder.
        let nearest = levels.indices.min { abs(levels[$0] - current) < abs(levels[$1] - current) } ?? 0
        let next = min(max(nearest + steps, 0), levels.count - 1)
        guard levels[next] != current else { return }
        webView.pageZoom = levels[next]
    }

    func resetPageZoom() {
        activeController?.webView?.pageZoom = 1
    }

    var canZoom: Bool { activeController?.webView != nil }

    // MARK: - Copying the address (§11.2)

    /// Replaces the pasteboard, which is what every Copy does.
    func copyActiveURL(asMarkdown: Bool) {
        guard let url = activeURL else { return }
        let text = asMarkdown ? "[\(activeTitle)](\(url.absoluteString))" : url.absoluteString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Bulk tab commands

    /// The Today tabs of the Space on screen. Favorites and Pinned tabs are not
    /// in it by definition — §6.1 is that a tile is a place you keep, and a
    /// command called "Close All Tabs" is not an invitation to lose them.
    var closableTabs: [UUID] {
        tabs.filter { $0.kind == .today }.map(\.id)
    }

    /// ⇧⌘K. Archives every Today tab in the Space, as one undo step.
    ///
    /// `closeTab` registers its own undo per tab, so without the grouping a user
    /// who closed forty tabs would need forty ⌘Z to get them back — each one
    /// silently restoring a tab they had stopped expecting.
    func closeAllTabs() {
        let doomed = closableTabs
        guard !doomed.isEmpty else { return }
        undoManager.beginUndoGrouping()
        for id in doomed { closeTab(id) }
        undoManager.endUndoGrouping()
        undoManager.setActionName(String(localized: "Close All Tabs"))
    }

    /// The tabs §6.3's clock would take on its next pass — the same rule, asked
    /// early. Empty when auto-archive is set to "never", which is the setting
    /// saying this command has nothing to do.
    var staleTabs: [UUID] {
        AutoArchive.idleTabs(
            allTabs(includeArchived: false),
            now: Date(),
            hours: TabLifecycle.autoArchiveHours,
            excluding: activeTabID
        )
    }

    /// ⌥⌘K. Runs §6.3's sweep now instead of waiting for the hour it would have
    /// happened on its own.
    ///
    /// The same rule as the clock, not a second one. A "clean up" that used
    /// its own idea of stale would archive tabs the settings say to keep, and
    /// the user would have no way to find out which idea they had just invoked.
    func cleanUpTabs() {
        let doomed = staleTabs
        guard !doomed.isEmpty else { return }
        undoManager.beginUndoGrouping()
        for id in doomed { closeTab(id) }
        undoManager.endUndoGrouping()
        undoManager.setActionName(String(localized: "Clean Up Tabs"))
    }

    // MARK: - Tiles

    /// The active tab, if it is a tile with a home address to go back to.
    /// `pinnedURL` is nil for every kind but `.essential` (§6.1).
    var resettablePinnedTab: Tab? {
        guard let id = activeTabID, let tab = tab(id), tab.pinnedURL != nil else { return nil }
        return tab
    }

    /// Sends the tile back to the address it was pinned at, dropping the history
    /// it wandered off into. The same call `closeTab` makes on a tile, which is
    /// the point: this is that behaviour with a name and a menu item.
    func resetPinnedTabToBaseURL() {
        guard let tab = resettablePinnedTab else { return }
        sendTileHome(tab.id, in: tab.spaceID)
    }
}
