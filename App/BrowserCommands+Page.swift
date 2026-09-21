//
//  BrowserCommands+Page.swift
//  Luna
//
//  The second half of §20.1: the commands added when the key map became a table
//  (`BrowserCommand`). Same rules as `BrowserCommands.swift` — a first-responder
//  action per command, no event monitors, nothing that is not also a menu item.
//
//  In their own file because the first one is full, not because they are a
//  different kind of thing.
//
//  Every one validates: a browser command that cannot run should dim rather
//  than swallow the keystroke, and these mostly have an obvious empty state —
//  nothing to copy, nothing stale to clean up, no tile to send home.
//  `validatePageCommand` is reached from `validateMenuItem`'s chain.
//

import AppKit
import BrowserKit

extension AppDelegate {

    // MARK: - Tabs

    /// Opens a copy of the active tab, carrying its back/forward history — the
    /// same call §3.4a's right-click menu makes.
    @objc func duplicateTab(_ sender: Any?) {
        guard let session, let active = session.activeTabID else { return }
        _ = session.duplicateTab(active)
    }

    /// Sends a Favorite tile back to the address it was pinned at (§6.1).
    @objc func resetPinnedTab(_ sender: Any?) {
        session?.resetPinnedTabToBaseURL()
    }

    /// `⇧⌘K`. Archives the Space's Today tabs in one undoable step; tiles and
    /// pinned tabs are not Today tabs and stay where they are.
    @objc func closeAllTabs(_ sender: Any?) {
        session?.closeAllTabs()
    }

    /// `⌥⌘K`. §6.3's auto-archive sweep, run now.
    @objc func cleanUpTabs(_ sender: Any?) {
        session?.cleanUpTabs()
    }

    // MARK: - The page

    /// `⇧⌘R`. Past the cache, unlike `⌘R`.
    @objc func forceReloadPage(_ sender: Any?) {
        session?.reloadIgnoringCache()
    }

    /// `⇧⌘C`.
    @objc func copyPageURL(_ sender: Any?) {
        session?.copyActiveURL(asMarkdown: false)
    }

    /// `⌥⇧⌘C`. `[title](url)` — the shape every notes app in the dock reads.
    @objc func copyPageMarkdown(_ sender: Any?) {
        session?.copyActiveURL(asMarkdown: true)
    }

    // MARK: - Zoom

    @objc func zoomIn(_ sender: Any?) {
        session?.zoomPage(by: 1)
    }

    @objc func zoomOut(_ sender: Any?) {
        session?.zoomPage(by: -1)
    }

    @objc func resetZoom(_ sender: Any?) {
        session?.resetPageZoom()
    }

    // MARK: - History (§6.4)

    /// `⌘Y`. The same pop-out both chrome layouts hang off a button, opened
    /// from the menu instead — which is the only way to reach it while the
    /// sidebar is hidden.
    @objc func showHistory(_ sender: Any?) {
        showHistoryList()
    }

    /// Whichever button the layout on screen is showing, exactly as
    /// `showDownloadsList` picks its own. A collapsed sidebar is still the
    /// sidebar layout — its button is parked off-screen and the pop-out falls
    /// back to the corner it would have been in.
    func showHistoryList() {
        guard let panel = historyPanel, let window = browserWindow?.window else { return }
        switch Settings.chromeLayout {
        case .topBar:
            guard let anchor = topBar?.historyAnchor else { return }
            panel.toggle(in: window, from: anchor, edge: .below)
        case .sidebar:
            guard let sidebar else { return }
            panel.toggle(in: window, from: sidebar.historyAnchor, edge: .above)
        }
    }

    // MARK: - Validation

    /// The commands declared in this file. Returns nil for anything it does not
    /// own, so `validateMenuItem`'s chain carries on past it.
    func validatePageCommand(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        switch item.action {
        case #selector(duplicateTab(_:)), #selector(forceReloadPage(_:)):
            return session.activeTabID != nil
        case #selector(resetPinnedTab(_:)):
            return session.resettablePinnedTab != nil
        case #selector(closeAllTabs(_:)):
            return !session.closableTabs.isEmpty
        // Dims to "nothing is stale enough yet", which is also how the user
        // finds out the command follows the auto-archive setting rather than
        // closing whatever it likes.
        case #selector(cleanUpTabs(_:)):
            return !session.staleTabs.isEmpty
        case #selector(copyPageURL(_:)), #selector(copyPageMarkdown(_:)):
            return session.activeURL != nil
        case #selector(zoomIn(_:)):
            return session.canZoom && session.pageZoom < (BrowserSession.zoomLevels.last ?? 1)
        case #selector(zoomOut(_:)):
            return session.canZoom && session.pageZoom > (BrowserSession.zoomLevels.first ?? 1)
        case #selector(resetZoom(_:)):
            return session.canZoom && session.pageZoom != 1
        case #selector(showHistory(_:)):
            return historyPanel != nil
        default:
            return nil
        }
    }
}

extension AppDelegate {

    // MARK: - Rebinding (§3.6)

    /// Listens for a shortcut the user changed in Settings.
    func observeShortcutChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: KeyBindings.didChange,
            object: nil
        )
    }

    /// Rebuilds the bar rather than editing the item that changed, for the
    /// reason `MainMenu`'s header gives: writing a key equivalent into a live
    /// menu bar is measurably unreliable, and building a fresh one is the path
    /// launch already takes.
    ///
    /// The two data-driven submenus come back empty from that rebuild, so
    /// `render` refills them — it is the one call that knows what the Spaces and
    /// the sidebar rows are called right now.
    @objc func shortcutsDidChange() {
        MainMenu.rebuild(in: NSApp)
        render()
    }
}
