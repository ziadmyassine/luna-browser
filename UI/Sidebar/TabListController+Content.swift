//
//  TabListController+Content.swift
//  Luna
//
//  What each row draws: the one place a `Tab` or a `TabGroup` becomes a
//  `SidebarRowContent`.
//
//  Split out of `TabListController.swift` for that file's length limit, and it
//  is a clean seam — nothing here touches the table, the pills or the gesture.
//  Everything it decides is a fact about the row rather than about the list:
//  which title outranks which, whether the trailing slot is the close chip or
//  the speaker, and §3.4b's two new ones — how far a row steps in, and whether
//  it is dimmed.
//

import AppKit
import BrowserKit

extension TabListController {

    func content(for row: Int) -> SidebarRowContent {
        switch list[row] {
        case .addTab:
            // "New Tab", and it opens §9.1 rather than an empty page. The
            // row used to be `+ Add Tab` and used to make a blank tab, which is
            // the one tab nobody wants: the next thing you do with it is reach
            // for the address bar. It now asks the question the blank tab was
            // standing in for.
            return SidebarRowContent(title: "New Tab", symbolName: "plus")
        case .separator, .none:
            return SidebarRowContent()
        case .group:
            guard let group = list.group(at: row) else { return SidebarRowContent() }
            return groupContent(group)
        case .tab:
            guard let tab = list.tab(at: row) else { return SidebarRowContent() }
            return tabContent(tab)
        }
    }

    /// §3.4b's header: the group's icon, its name, and the chevron that folds
    /// it. No trailing slot — a group is closed from its menu, which is where a
    /// command that ends several pages at once belongs.
    ///
    /// A folder a Luna Control client is working in wears the loading shimmer:
    /// something is happening in there that the user did not start, and the
    /// row says so without a control of its own. While it waits for the user,
    /// or is paused or stopped, it wears that state's icon in place of its own.
    private func groupContent(_ group: TabGroup) -> SidebarRowContent {
        SidebarRowContent(
            title: group.name,
            symbolName: controlBadges[group.id] ?? group.symbolName,
            isLoading: controlledGroupIDs.contains(group.id),
            disclosure: group.isCollapsed ? .collapsed : .expanded
        )
    }

    private func tabContent(_ tab: Tab) -> SidebarRowContent {
        let state = liveStates[tab.id]
        // §3.4a: a name the user typed outranks both the live title and the stored one.
        // The live title is the page's most current answer to a question the user has
        // already overruled.
        let pageTitle = state?.title.isEmpty == false ? (state?.title ?? "") : tab.title
        let title = tab.customTitle ?? pageTitle
        // Where the tab is now, not where the snapshot left it. `tab` is the
        // copy taken at the last `notifyChange()`, and an in-tab navigation
        // raises none — it writes the tab and publishes a `TabState`. Reading
        // the host off the snapshot is what kept the row wearing the icon of the
        // site it had already left.
        let url = state?.url ?? tab.url
        let muted = mutedTabIDs.contains(tab.id)
        let trailing: SidebarRowContent.Trailing
        if hoveredRow.flatMap({ list[$0] }) == .tab(tab.id) {
            trailing = .close
        } else if state?.isPlayingAudio == true || muted {
            trailing = .audio(muted: muted)
        } else {
            trailing = .none
        }
        return SidebarRowContent(
            title: title.isEmpty ? URLPillView.domain(of: url) : title,
            // §3.4a: a chosen symbol replaces the favicon, so the row draws its symbol
            // slot instead — which is the path `+ Add Tab` has always taken.
            symbolName: tab.customSymbolName ?? SidebarRowContent.siteFallbackSymbol,
            favicon: tab.customSymbolName == nil ? icons.favicon(for: url) : nil,
            hasUnread: tab.hasUnread,
            isLoading: state?.isLoading ?? false,
            trailing: trailing,
            // §3.4b: a tab inside a group steps in, and the spine is drawn in
            // the space that opens. A dimmed row is one that has been closed
            // once and kept — see `Tab.isDormant`.
            indent: list.group(ofTab: tab.id) == nil ? 0 : Tokens.Metric.groupIndent,
            isDormant: tab.isDormant
        )
    }
}
