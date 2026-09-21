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
            present(.newTab, nil)
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

    /// `⌘⌥L`. Toggles §30.15's list; the completion popover is the primary
    /// surface and shows itself.
    @objc func showDownloads(_ sender: Any?) {
        showDownloadsList()
    }

    // MARK: - Settings (SETTINGS-SPEC §2)

    /// `⌘,`. Opens the Settings window, or focuses the one already open.
    @objc func showSettings(_ sender: Any?) {
        showSettings()
    }

    // MARK: - Layout and Spaces

    /// `⌘S` (§8): hides and shows the sidebar. Not the layout switch —
    /// that is `Settings.chromeLayout`, reached with `⌘,`.
    ///
    /// Not called `toggleSidebar(_:)`. That selector is `NSSplitViewController`'s,
    /// and something in the responder chain answers to it: the menu item
    /// validated as enabled, the click went somewhere, and nothing happened.
    /// Named for what it does, and the name is now ours.
    @objc func toggleSidebarVisibility(_ sender: Any?) {
        toggleSidebar()
    }

    /// `⌃1…⌃9` (§5.3, §13.2). The item's tag is its index in `session.spaces`.
    ///
    /// It used to be `⌘1…⌘9`, which is "go to tab N" in Safari, Chrome,
    /// Firefox, Edge and Arc. That namespace now belongs to
    /// `goToSidebarItem(_:)`; Spaces moved one modifier over, where Arc and Dia
    /// both put them.
    @objc func switchToSpace(_ sender: Any?) {
        guard let session, let item = sender as? NSMenuItem,
              session.spaces.indices.contains(item.tag) else { return }
        session.switchSpace(session.spaces[item.tag].id)
    }

    /// `⌃⌥←` / `⌃⌥→`. Wraps, the same ring `selectAdjacentTab` walks.
    ///
    /// Not `⌘⌥←/→`, which SPACES-SPEC §13.2 asks for: that pair is already
    /// shipped as Show Previous/Next Tab (§7.4, and `TODO.md` §20.1 lists it
    /// under tabs in the same breath as it gives Spaces ⌃-number). One of the
    /// two has to move and the spec contradicts itself about which; keeping the
    /// tab binding and translating ⌘→⌃ keeps every Space command under one
    /// modifier. Reported rather than decided quietly.
    @objc func previousSpace(_ sender: Any?) {
        selectAdjacentSpace(offset: -1)
    }

    @objc func nextSpace(_ sender: Any?) {
        selectAdjacentSpace(offset: 1)
    }

    private func selectAdjacentSpace(offset: Int) {
        guard let session, session.spaces.count > 1 else { return }
        let spaces = session.spaces
        let current = spaces.firstIndex { $0.id == session.activeSpaceID } ?? 0
        let next = ((current + offset) % spaces.count + spaces.count) % spaces.count
        session.switchSpace(spaces[next].id)
    }

    /// `⌘1…⌘9` — Window ▸ Sidebar Items. The tag is the row's index in
    /// `session.tabs`, which is already sorted the way the sidebar draws it.
    ///
    /// The Settings window's own `⌘1…⌘9` arrives here too. Probed on macOS
    /// 26.5: the first key-equivalent match in menu-bar order consumes the
    /// event and nothing later ever sees it, disabled or not, so exactly one
    /// item can own `⌘1` and this is it. Forwarding is how Window ▸ Settings ▸
    /// <section> keeps working while that window is key; `SettingsWindowController`
    /// used to claim `switchToSpace(_:)` for the same reason, from the other
    /// side of the same rule.
    @objc func goToSidebarItem(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        if let settings = NSApp.keyWindow?.windowController as? SettingsWindowController {
            settings.goToSettingsSection(item)
            return
        }
        guard let session, session.tabs.indices.contains(item.tag) else { return }
        session.activateTab(session.tabs[item.tag].id)
    }

    // MARK: - Favorites (§2, §13.4)

    /// `⌘D`. Favorites are per Profile and capped at twelve, so this is the
    /// one command in Luna that can be refused rather than merely dimmed.
    ///
    /// The thirteenth gets a sentence, not a silent no-op: `pinTab` returns
    /// `false` when the cap is hit and there is nothing the user can infer from
    /// a tab that simply does not move. The alert names the profile the cap
    /// belongs to, because the cap is shared by every Space on it — which is
    /// the whole reason it can be full when this Space shows only three tiles.
    @objc func toggleFavorite(_ sender: Any?) {
        guard let session, let id = session.activeTabID, let tab = session.tabs.first(where: { $0.id == id })
        else { return }
        guard tab.kind != .essential else {
            session.unpinTab(id)
            return
        }
        guard !session.pinTab(id) else { return }
        let profile = session.space(session.activeSpaceID).flatMap { session.profile(for: $0) }
        let name = profile?.name ?? String(localized: "this profile")
        let alert = NSAlert()
        alert.messageText = String(localized: "Favorites is full.")
        alert.informativeText = String(localized: """
        \(name) keeps \(BrowserSession.favoritesCap) Favorites, and every Space on that profile shares them. \
        Remove one to make room for this tab.
        """)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
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
        // Before the session guard: hiding the sidebar is a window command and
        // works on an empty window.
        if let sidebar = validateSidebarToggle(menuItem) { return sidebar }
        // Settings needs no session. It can be opened during a cold launch —
        // several of its sections exist to say what is not wired up yet — and a
        // dimmed `⌘,` on a slow first run would be a bug, not a safeguard.
        if menuItem.action == #selector(showSettings(_:)) { return true }
        guard let session else { return false }
        return validateFavoriteToggle(menuItem, in: session)
            ?? validateNavigation(menuItem, in: session)
            ?? validatePageCommand(menuItem, in: session)
            ?? validateSessionCommand(menuItem, in: session)
    }

    /// `⌘D` says which way it will go, the same way the sidebar toggle does.
    /// A Favorite tile is removed, not closed — §2's "closing one puts the page
    /// away, keeps the tile" is `pinTab`'s job, not this item's.
    private func validateFavoriteToggle(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        guard item.action == #selector(toggleFavorite(_:)) else { return nil }
        let active = session.activeTabID.flatMap { id in session.tabs.first { $0.id == id } }
        item.title = active?.kind == .essential
            ? String(localized: "Remove from Favorites")
            : String(localized: "Add to Favorites")
        return active != nil
    }

    /// Keeps the View menu honest: the item says what the next press will do,
    /// and dims in the layout that has no sidebar to hide. Once the sidebar is
    /// hidden this menu item and `⌘S` are the only ways back — the toggle
    /// button goes with the sidebar.
    private func validateSidebarToggle(_ item: NSMenuItem) -> Bool? {
        guard item.action == #selector(toggleSidebarVisibility(_:)) else { return nil }
        item.title = browserWindow?.isSidebarCollapsed == true
            ? String(localized: "Show Sidebar")
            : String(localized: "Hide Sidebar")
        return browserWindow?.canCollapseSidebar ?? false
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
        case #selector(previousSpace(_:)), #selector(nextSpace(_:)):
            return session.spaces.count > 1
        // Never conditional. It is the first `⌘1…⌘9` in menu order, and a
        // disabled first match swallows the keystroke instead of passing it on
        // (probed, macOS 26.5) — so dimming this would take `⌘1` away from the
        // Settings window as well as from here. The action guards its own index.
        case #selector(goToSidebarItem(_:)):
            return true
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
