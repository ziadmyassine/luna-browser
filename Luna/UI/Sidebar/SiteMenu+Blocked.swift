//
//  SiteMenu+Blocked.swift
//  Luna
//
//  §17.4: how much the blocker caught on the page in front, as one line of the
//  site pop-out, and behind it the sites it came from. Counted by the page
//  script's heuristic (`ContentBlocker.blockedCountScript`), per page.
//

import AppKit
import BrowserKit

extension SiteMenu {

    /// At most this many sites in the list, most often blocked first; the rest are
    /// one row that says how many.
    static let blockedHostLimit = 8

    /// A band of one row, "12 blocked on this page", when blocking is on for the site
    /// and has caught something; no band otherwise. Choosing it lists the sites.
    static func blockedLine(tab: UUID, host: String, scope: SitePermissions, from anchor: NSView) -> [SiteSettingsContent.Action] {
        let blocker = ContentBlocker.shared
        let count = blocker.blockedCount(tab: tab)
        guard count > 0, !blocker.isDisabled(forHost: host, in: scope) else { return [] }
        let hosts = blocker.blockedHosts(tab: tab)
        return [.init(title: blockedTitle(count), symbol: Glyph.blocked) { [weak anchor] in
            guard let anchor, !hosts.isEmpty else { return }
            show(blockedList(count: count, hosts: hosts), from: anchor)
        }]
    }

    static func blockedTitle(_ count: Int) -> String {
        count == 1 ? String(localized: "1 blocked on this page") : String(localized: "\(count) blocked on this page")
    }

    /// The sites the blocked loads were for, each with how many. A row does nothing
    /// but close the list, as a menu item with nothing to do would.
    static func blockedList(count: Int, hosts: [(host: String, count: Int)]) -> SiteSettingsContent {
        var content = SiteSettingsContent(heading: blockedTitle(count))
        content.symbol = Glyph.blocking
        var rows: [SiteSettingsContent.Action] = hosts.prefix(blockedHostLimit).map { entry in
            .init(title: "\(entry.host) · \(entry.count)", symbol: Glyph.blocked) {}
        }
        let rest = hosts.count - blockedHostLimit
        if rest > 0 {
            rows.append(.init(
                title: rest == 1 ? String(localized: "1 more site") : String(localized: "\(rest) more sites"),
                symbol: Glyph.blocked
            ) {})
        }
        content.actions = [rows]
        return content
    }

    /// Puts `content` up on `anchor` in place of whatever the pop-out was showing.
    static func show(_ content: SiteSettingsContent, from anchor: NSView) {
        guard let window = anchor.window else { return }
        let edge: PopoutEdge = anchor.convert(anchor.bounds, to: nil).midY > window.contentLayoutRect.midY
            ? .below
            : .above
        controller.dismiss()
        controller.toggle(in: window, from: anchor, edge: edge, content: content)
    }
}
