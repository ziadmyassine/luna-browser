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

    /// §17's user-recorded shortcut: the active tab's most recent blocked
    /// pop-up, chip or no chip.
    @objc func openBlockedPopup(_ sender: Any?) {
        session?.openLatestBlockedPopup()
    }

    /// `⌥⌘R`. Past the cache, unlike `⌘R`.
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

    // MARK: - Picture in Picture

    @objc func togglePictureInPicture(_ sender: Any?) {
        session?.togglePictureInPicture()
    }

    // MARK: - Print and PDF (§15.5)

    /// `⌘P`.
    @objc func printPage(_ sender: Any?) {
        session?.printActivePage()
    }

    @objc func downloadPDF(_ sender: Any?) {
        session?.downloadActivePDF()
    }

    // MARK: - Reader and hiding

    /// `⇧⌘R`.
    @objc func toggleReader(_ sender: Any?) {
        session?.toggleReader()
    }

    /// `⇧⌘H`. Point at a part of the page and it is gone on this site for good.
    @objc func toggleHidingElements(_ sender: Any?) {
        session?.toggleHidingElements()
    }

    // MARK: - Comments

    /// `⇧⌘M`. Point at an element and write a note on it, for an agent to act on.
    @objc func toggleCommenting(_ sender: Any?) {
        guard let front else { return }
        if let mode = front.comments { return mode.leave() }
        guard canComment(in: front.session) else { NSLog("CMDIAG cannot comment"); return }
        let set = commentSet ?? CommentSet()
        commentSet = set
        let mode = CommentMode(window: front, set: set)
        let entered = mode.enter()
        NSLog("CMDIAG entered %d", entered ? 1 : 0)
        if entered { front.comments = mode }
    }

    /// Works with the mode off too: the set is app-wide and outlives it.
    @objc func exportComments(_ sender: Any?) {
        exportComments()?.show(in: front?.controller.window)
    }

    /// Every site's bundle, and one prompt on the clipboard: the front page's
    /// site, or the first commented one when the front page has none. The set
    /// is cleared only once every bundle is written, and ⌘Z brings it back.
    /// - Returns: the toast to show, or nil when there was nothing to export.
    func exportComments(to root: URL = CommentBundle.folder, pasteboard: NSPasteboard = .general) -> PageToast? {
        guard let front else { return nil }
        // An open note holds text the set has not been given yet.
        for window in windows { window.comments?.closeNote(focusingPage: true, undoable: false) }
        let set = commentSet ?? CommentSet()
        commentSet = set
        let origins = set.comments.map(\.origin).uniqued()
        guard let first = origins.first else { return nil }
        let here = front.session.activeURL.flatMap(CommentBundle.slug(for:))
        let copied = origins.first { $0 == here } ?? first
        let count = set.comments.filter { $0.origin == copied }.count
        let written: [String: URL]
        do {
            written = try set.export(to: root, undoingOn: front.session.undoManager)
        } catch {
            return .commentsNotExported(error.localizedDescription)
        }
        if let file = written[copied] {
            pasteboard.clearContents()
            pasteboard.setString(CommentBundle.prompt(for: file), forType: .string)
        }
        let files = origins.compactMap { written[$0] }
        return .commentsExported(count, copied: copied, others: origins.filter { $0 != copied }) {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    /// Not in a private window, where a draft on disk would break the promise;
    /// not in Reader, whose markup is Luna's and not the site's.
    private func canComment(in session: BrowserSession) -> Bool {
        session.canUsePageTools && !session.isPrivate && !session.isReaderOn
    }

    // MARK: - History (§6.4)

    /// `⌘Y`. The same pop-out both chrome layouts hang off a button, opened
    /// from the menu instead — which is the only way to reach it while the
    /// sidebar is hidden.
    @objc func showHistory(_ sender: Any?) {
        showHistoryList()
    }

    /// §11.3. Asks which span, then clears it from the front window's Space,
    /// whether or not its History pop-out is open.
    @objc func clearHistory(_ sender: Any?) {
        historyPanel?.clearHistory()
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
        case #selector(duplicateTab(_:)), #selector(forceReloadPage(_:)), #selector(togglePictureInPicture(_:)):
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
        case #selector(showHistory(_:)), #selector(clearHistory(_:)):
            return historyPanel != nil
        default:
            return validatePageTool(item, in: session)
        }
    }

    /// Reader and the picker, ticked while on so the menu says how to get back
    /// out; Print and Download PDF.
    private func validatePageTool(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        switch item.action {
        case #selector(toggleReader(_:)):
            item.state = session.isReaderOn ? .on : .off
            return session.canUsePageTools
        case #selector(toggleHidingElements(_:)):
            item.state = session.isPickingElements ? .on : .off
            return session.canUsePageTools && !session.isDescribingElements
        case #selector(toggleCommenting(_:)):
            return canComment(in: session)
        // The set is app-wide, so the page in front has no say. A private
        // window stays out of comment mode's files altogether.
        case #selector(exportComments(_:)):
            return !session.isPrivate && !(commentSet?.comments ?? CommentSet.saved()).isEmpty
        case #selector(printPage(_:)):
            return session.canPrint
        case #selector(downloadPDF(_:)):
            return session.canDownloadActivePDF
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
