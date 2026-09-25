//
//  TopBarTabStrip+Rows.swift
//  Luna
//
//  §4's open tabs and folders' headers: §3.4's rows, built and kept, and what
//  each one says and does.
//
//  Split out of `TopBarTabStrip` for its type body length, along the seam the
//  file already had — the kept tiles stay with the session there, the rows come
//  here.
//

import AppKit
import BrowserKit

extension TopBarTabStrip {

    // MARK: - Rows

    func configureRow(for tab: Tab, arriving: Bool) {
        let row = row(for: tab.id, arriving: arriving)
        row.configure(rowContent(for: tab))
        row.setAccessibilityHelp(position(of: tab.id))
        row.row.isSelected = tab.id == activeID
        row.row.onTrailing = { [weak self] trailing in
            guard let self else { return }
            switch trailing {
            case .close: session.closeTab(tab.id)
            case let .audio(muted): session.setMuted(!muted, tab: tab.id)
            case .none: break
            }
        }
        row.onPress = { [weak self, weak row] press in
            guard let self, let row else { return }
            if press.clickCount == 2 {
                beginRenaming(tab.id, on: row)
                return
            }
            let wasShowing = tab.id == activeID
            // The column's rule: the press selects, before the hand has gone
            // anywhere — so a tab that is then carried is the tab on screen.
            activateTab(tab.id)
            track(
                press,
                on: row,
                onClick: { [weak self, weak row] in
                    // The bar has no address of its own, so the tab on screen
                    // is where it is edited — as `⌘L` would. At once: a second
                    // click lands on the bar, which folds back for the rename
                    // (`CommandBarAnchor.onDoubleClick`).
                    guard let self, let row, wasShowing else { return }
                    editAddress(of: tab.id, on: row)
                },
                onDrag: { [weak self] in self?.onDrag?(.tab(tab.id), row, press) }
            )
        }
        row.row.onRename = { [weak self] name in self?.session.renameTab(tab.id, to: name) }
        row.row.onSiteSettings = { anchor in SiteMenu.present(from: anchor) }
        row.menuBuilder = { [weak self] in self?.tabMenu(tab.id) }
    }

    /// §9.1 grown out of the tab, the way §3.2's pill hands its address over:
    /// the bar takes the tab's place and opens down out of it, and closes back
    /// into it (`CommandBarAnchor`).
    ///
    /// The selected pill goes with the row. It is the strip's, not the row's,
    /// so hiding the row alone left it glowing through the bar's glass.
    private func editAddress(of id: UUID, on row: TopBarTabRow) {
        guard let present = presentCommandBar else { return }
        selectionPill.isHidden = true
        let anchor = CommandBarAnchor(
            view: row,
            span: self,
            cornerRadius: Tokens.Metric.rowCornerRadius,
            onDoubleClick: { [weak self, weak row] in
                guard let row else { return }
                self?.beginRenaming(id, on: row)
            },
            onDismiss: { [weak self] in self?.selectionPill.isHidden = false }
        )
        present(.editCurrentURL, anchor)
    }

    /// A double-click on a tab: the column's name field, on the tab's own row,
    /// opened on the name the row is showing.
    private func beginRenaming(_ id: UUID, on row: TopBarTabRow) {
        guard let tab = session.tab(id) else { return }
        row.row.beginEditing(tab.customTitle ?? row.content.title)
    }

    /// A folder's header. Every folder stands on a plate of its own — the
    /// header, a divider, then the folder's tabs — the way §3.3's tiles stand
    /// on the Space's; a kept folder's plate stands beside that one, not on
    /// it.
    func configureRow(for group: TabGroup, arriving: Bool) {
        let row = row(for: group.id, arriving: arriving)
        // No chevron: on the bar the plate is what says a folder is open.
        row.configure(SidebarRowContent(title: group.name, symbolName: group.symbolName))
        row.setAccessibilityRole(.disclosureTriangle)
        row.setAccessibilityValue(group.isCollapsed ? 0 : 1)
        row.row.isSelected = false
        // A folder's header both folds and moves, and the two are told apart
        // by whether the hand went anywhere — the column's rule.
        row.onPress = { [weak self, weak row] press in
            guard let self, let row else { return }
            track(
                press,
                on: row,
                onClick: { [weak self] in
                    guard let self, let current = session.group(group.id) else { return }
                    session.setGroupCollapsed(!current.isCollapsed, forGroup: group.id)
                },
                onDrag: { [weak self] in self?.onDrag?(.group(group.id), row, press) }
            )
        }
        row.menuBuilder = { [weak self] in
            guard let self, let current = session.group(group.id) else { return nil }
            return GroupMenu.build(for: current, actions: session.groupMenuActions(for: group.id))
        }
        if dividers[group.id] == nil {
            let divider = TopBarSeparator()
            dividers[group.id] = divider
            content.addSubview(divider, positioned: .below, relativeTo: glow)
        }
        guard folderPlates[group.id] == nil else { return }
        let folderPlate = TopBarPlate()
        folderPlate.menuBuilder = row.menuBuilder
        folderPlates[group.id] = folderPlate
        // Over the Space's plate, under every fill and tab.
        content.addSubview(folderPlate, positioned: .above, relativeTo: plate)
        if arriving { fadeIn(folderPlate) }
    }

    private func row(for id: UUID, arriving: Bool) -> TopBarTabRow {
        if let existing = rows[id] { return existing }
        let row = TopBarTabRow()
        row.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        row.onHover = { [weak self] inside in self?.hover(id, inside: inside) }
        content.addSubview(row, positioned: .below, relativeTo: glow)
        rows[id] = row
        if arriving { fadeIn(row) }
        return row
    }

    /// The column's `tabContent`, for a row on the bar: the live title over the
    /// stored one and the user's name over both, the close glyph on the row
    /// the pointer is on and the speaker on one making sound.
    ///
    /// The selected tab also carries §3.2's site settings glyph — the bar has
    /// no address pill to put it on — and keeps its close glyph when the
    /// pointer is elsewhere, so the glyph has the same neighbour wherever the
    /// pointer is and nothing slides under a hand on its way to it.
    func rowContent(for tab: Tab) -> SidebarRowContent {
        let state = session.controller(for: tab.id)?.state
        let pageTitle = state?.title.isEmpty == false ? (state?.title ?? "") : tab.title
        let title = tab.customTitle ?? pageTitle
        let url = state?.url ?? tab.url
        let muted = session.isMuted(tab.id)
        let isSelected = tab.id == activeID
        let trailing: SidebarRowContent.Trailing = if hoveredID == tab.id {
            .close
        } else if state?.isPlayingAudio == true || muted {
            .audio(muted: muted)
        } else if isSelected {
            .close
        } else {
            .none
        }
        return SidebarRowContent(
            title: title.isEmpty ? URLPillView.domain(of: url) : title,
            symbolName: tab.customSymbolName ?? SidebarRowContent.siteFallbackSymbol,
            favicon: tab.customSymbolName == nil ? session.icons.favicon(for: url) : nil,
            hasUnread: tab.hasUnread,
            isLoading: state?.isLoading ?? false,
            trailing: trailing,
            isDormant: tab.isDormant,
            siteSettings: isSelected && url.host(percentEncoded: false)?.isEmpty == false
        )
    }
}
