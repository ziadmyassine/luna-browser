//
//  BrowserCommands+Tab.swift
//  Luna
//
//  §20.2: §3.4a's tab menu without the mouse. Each command runs the verb the
//  menu runs (`BrowserSession.tabMenuActions`) on the front window's tab, and
//  puts its question where the window can show it: the name field on the
//  tab's own row, the pop-out on the address bar that is on screen.
//
//  Pin and Unpin are not here. A pinned tab is a Favorite, so the menu's Pin
//  is `⌘D`'s Add to Favorites, which already has a command.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// The front window's selected tab, with the window it is in.
    private var frontTab: (window: BrowserWindow, tab: Tab)? {
        guard let window = front, let id = window.activeTabID, let tab = window.session.tab(id) else { return nil }
        return (window, tab)
    }

    @objc func renameActiveTab(_ sender: Any?) {
        guard let (window, tab) = frontTab else { return }
        let session = window.session
        if !window.controller.isSidebarCollapsed, window.sidebar?.beginRenaming(tab: tab.id) == true { return }
        if window.topBar?.strip.beginRenaming(tab.id) == true { return }
        TabMenu.askName(for: tab) { [weak session] name in session?.renameTab(tab.id, to: name) }
    }

    @objc func toggleSiteMute(_ sender: Any?) {
        guard let (window, tab) = frontTab else { return }
        window.session.setMuted(!window.session.isMuted(tab.id), tab: tab.id)
    }

    /// The folder submenu, popped up on its own over the tab it moves, and
    /// worked with the arrow keys like any menu.
    @objc func moveActiveTabToFolder(_ sender: Any?) {
        guard let (window, tab) = frontTab, let menu = window.session.folderMenu(forTab: tab.id),
              let content = window.controller.window?.contentView else { return }
        let anchor = window.anchorForTab(tab.id)
        let view = anchor ?? content
        // Under the row it moves; with no row on screen, near the top of the
        // window, where the column or the bar would have put it.
        let point = anchor.map { NSPoint(x: $0.bounds.minX, y: $0.isFlipped ? $0.bounds.maxY : $0.bounds.minY) }
            ?? NSPoint(x: content.bounds.midX, y: content.bounds.maxY - content.bounds.height / 4)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc func newTabFolder(_ sender: Any?) {
        guard let session else { return }
        session.newFolder(around: session.activeTabID)
    }

    @objc func openSiteSettings(_ sender: Any?) {
        front?.siteSettingsOpener()?()
    }

    /// Nil for anything it does not own, so `validateMenuItem`'s chain carries
    /// on past it.
    func validateTabCommand(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        let tab = frontTab?.tab
        switch item.action {
        case #selector(renameActiveTab(_:)):
            return tab != nil
        case #selector(toggleSiteMute(_:)):
            // Says which way the next press goes, as the tab menu does.
            let muted = tab.map { session.isMuted($0.id) } ?? false
            item.title = muted ? String(localized: "Unmute Site") : String(localized: "Mute Site")
            return tab != nil
        case #selector(moveActiveTabToFolder(_:)):
            return tab.map { $0.kind != .essential } ?? false
        case #selector(newTabFolder(_:)):
            return true
        case #selector(openSiteSettings(_:)):
            return tab != nil && front?.siteSettingsOpener() != nil
        default:
            return nil
        }
    }
}

extension BrowserWindow {

    /// What opens §3.2a's pop-out on the address bar this window is showing:
    /// §3.2b's on the page, §3.2's in the column, or the tab's own row in §4's
    /// bar. Nil when none of them is on screen — a hidden column's pill is
    /// parked off the window's edge, and a pop-out standing on it would too.
    func siteSettingsOpener() -> (() -> Void)? {
        if let page = pageChrome, page.isOnScreen { return { page.openSiteMenu() } }
        if !controller.isSidebarCollapsed, let sidebar, sidebar.showsURLPill { return { sidebar.openSiteMenu() } }
        if let topBar, let id = activeTabID, topBar.window != nil, !topBar.isHiddenOrHasHiddenAncestor {
            return { topBar.strip.openSiteSettings(for: id) }
        }
        return nil
    }

    /// The view that stands for tab `id` on screen: its row in the column or
    /// in the bar. Nil for a tab with neither in view.
    func anchorForTab(_ id: UUID) -> NSView? {
        if !controller.isSidebarCollapsed, let row = sidebar?.rowView(forTab: id) { return row }
        guard let topBar, topBar.window != nil, !topBar.isHiddenOrHasHiddenAncestor else { return nil }
        return topBar.strip.rows[id] ?? topBar.strip.tiles[id]
    }
}
