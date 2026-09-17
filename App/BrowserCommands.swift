//
//  BrowserCommands.swift
//  Luna
//
//  Every §20.1 command, as a first-responder action. They live on
//  `AppDelegate` because it is the last responder in the chain: a text field
//  that wants `⌘Z` or `⌘A` gets it first, and only what nothing else claimed
//  reaches a browser command.
//
//  There is no `NSEvent` monitor and no `performKeyEquivalent` override
//  anywhere in Luna. A shortcut that is not a menu item is undiscoverable
//  (§22.5) and, worse, invisible to the accessibility system — so the key map
//  is declared once, in `MainMenu`, and implemented once, here.
//

import AppKit
import BrowserKit

extension AppDelegate {

    // MARK: - Tabs

    /// `⌘T`. Opens the Command Bar when one is installed (§9.1); a blank tab
    /// is the honest fallback, not a no-op.
    @objc func newTab(_ sender: Any?) {
        guard let session else { return }
        if let present = session.presentCommandBar {
            present(.newTab)
        } else {
            session.newTab(url: nil, kind: .today)
        }
    }

    /// `⌘L`. Focuses the URL pill of whichever layout is showing (§3.2, §4).
    @objc func editLocation(_ sender: Any?) {
        editLocation()
    }

    /// `⌘W`. Archives rather than deletes (§6.3) — and is undoable (§6.7).
    @objc func closeTab(_ sender: Any?) {
        guard let session, let active = session.activeTabID else { return }
        session.closeTab(active)
    }

    /// `⌘⇧T`. Reads the archive, so it works after a relaunch too.
    @objc func reopenArchivedTab(_ sender: Any?) {
        session?.reopenLastArchived()
    }

    /// `⌘⌥←` / `⌘⌥→` (§7.4).
    @objc func previousTab(_ sender: Any?) {
        session?.selectAdjacentTab(offset: -1)
    }

    @objc func nextTab(_ sender: Any?) {
        session?.selectAdjacentTab(offset: 1)
    }

    // MARK: - Navigation

    @objc func reloadPage(_ sender: Any?) {
        session?.reload()
    }

    @objc func stopLoading(_ sender: Any?) {
        session?.stop()
    }

    @objc func goBack(_ sender: Any?) {
        session?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        session?.goForward()
    }

    // MARK: - Downloads (§15.3)

    /// `⌘⌥L`. Toggles §30.15's secondary surface; the completion popover is
    /// the primary one and shows itself.
    @objc func showDownloads(_ sender: Any?) {
        downloadsPanel?.toggle()
    }

    // MARK: - Layout and Spaces

    /// `⌘S` (§8): toggles the sidebar, and toggles back from top-bar mode.
    @objc func toggleChromeLayout(_ sender: Any?) {
        toggleChromeLayout()
    }

    /// `⌘1…⌘9` (§5.3). The item's tag is its index in `session.spaces`.
    @objc func switchToSpace(_ sender: Any?) {
        guard let session, let item = sender as? NSMenuItem,
              session.spaces.indices.contains(item.tag) else { return }
        session.switchSpace(session.spaces[item.tag].id)
    }

    // MARK: - Undo (§6.7)

    /// The Edit menu's `⌘Z`. A focused text field handles its own undo before
    /// this is ever reached; what lands here is a tab close, archive or move.
    @objc func undo(_ sender: Any?) {
        session?.undoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        session?.undoManager.redo()
    }
}

extension AppDelegate: NSMenuItemValidation {

    /// §20.2: a command the session cannot perform is dimmed, not silently
    /// ignored. Back and forward read the live controller — a hibernated tab
    /// has no history to walk until it is woken, which is the truth.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let session else { return false }
        return validateNavigation(menuItem, in: session)
            ?? validateSessionCommand(menuItem, in: session)
    }

    /// Reads the live controller, so it answers `nil` for anything it does not
    /// own rather than guessing.
    private func validateNavigation(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        let active = session.activeTabID.flatMap { session.controller(for: $0) }
        switch item.action {
        case #selector(goBack(_:)):
            return active?.state.canGoBack ?? false
        case #selector(goForward(_:)):
            return active?.state.canGoForward ?? false
        case #selector(stopLoading(_:)):
            return active?.state.isLoading ?? false
        default:
            return nil
        }
    }

    private func validateSessionCommand(_ item: NSMenuItem, in session: BrowserSession) -> Bool {
        switch item.action {
        case #selector(reloadPage(_:)), #selector(closeTab(_:)):
            return session.activeTabID != nil
        case #selector(previousTab(_:)), #selector(nextTab(_:)):
            return session.tabs.count > 1
        case #selector(reopenArchivedTab(_:)):
            return !session.archived.isEmpty
        case #selector(showDownloads(_:)):
            return downloadsPanel != nil
        case #selector(undo(_:)):
            return session.undoManager.canUndo
        case #selector(redo(_:)):
            return session.undoManager.canRedo
        default:
            return true
        }
    }
}
