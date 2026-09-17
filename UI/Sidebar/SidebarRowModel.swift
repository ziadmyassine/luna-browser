//
//  SidebarRowModel.swift
//  Luna
//
//  The §3.4 list, as data. Pure: no AppKit, no session, no side effects — so
//  the two things that are genuinely easy to get wrong (which row is which
//  tab, and which section a drop lands in) are asserted in `Tests/Sidebar/`
//  instead of discovered by dragging a row in a running app.
//
//  §3.4 fixes the order: `Archive` → `+ Add Tab` → separator → tabs. Essentials
//  are **not** in this list; they are the §3.3 grid above the scroll view.
//

import BrowserKit
import Foundation

/// One line of the sidebar list. `Archive` and `+ Add Tab` are first-class rows
/// with identical metrics to a tab (§30.6), not header decoration.
enum SidebarRow: Hashable, Sendable {
    case archive
    case addTab
    /// The rule between the commands and the tabs. Not selectable.
    case separator
    case tab(UUID)
}

/// The list for one Space: the fixed leading rows, then pinned tabs, then
/// today's tabs, in the order `BrowserSession` hands them over.
struct SidebarList: Equatable, Sendable {

    /// §3.4's fixed head. `separator` last, so both commands group together
    /// above the rule.
    static let leading: [SidebarRow] = [.archive, .addTab, .separator]

    /// Tabs in list order (pinned first), excluding Essentials.
    let listed: [Tab]
    /// The §3.3 grid's tabs, in session order.
    let essentials: [Tab]
    let rows: [SidebarRow]

    private let pinnedCount: Int

    init(tabs: [Tab] = []) {
        let pinned = tabs.filter { $0.kind == .pinned }
        let today = tabs.filter { $0.kind == .today }
        essentials = tabs.filter { $0.kind == .essential }
        listed = pinned + today
        pinnedCount = pinned.count
        rows = Self.leading + listed.map { SidebarRow.tab($0.id) }
    }

    var count: Int { rows.count }

    subscript(row: Int) -> SidebarRow? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    /// The tab a row shows, or nil for `Archive` / `+ Add Tab` / the separator.
    func tab(at row: Int) -> Tab? {
        guard case let .tab(id)? = self[row] else { return nil }
        return listed.first { $0.id == id }
    }

    func row(of id: UUID) -> Int? {
        rows.firstIndex(of: .tab(id))
    }

    /// Rows the keyboard and the mouse may land on. The separator is furniture.
    func isSelectable(_ row: Int) -> Bool {
        self[row] != nil && self[row] != .separator
    }

    /// Where a drop between rows belongs, as `BrowserSession.reorderTab` wants
    /// it: a section and an index within that section.
    ///
    /// A drop above the first tab lands in `pinned` only when a pinned section
    /// exists — otherwise there is no pinned row to sit above, and the user is
    /// dropping at the top of today's tabs.
    func dropTarget(insertingAt row: Int) -> (kind: TabKind, index: Int) {
        let offset = max(row - Self.leading.count, 0)
        if offset < pinnedCount || (offset == 0 && pinnedCount > 0) {
            return (.pinned, min(offset, pinnedCount))
        }
        return (.today, offset - pinnedCount)
    }

    /// Row index a drag should snap to when it is over `row`'s upper or lower
    /// half — AppKit reports the row under the pointer, not the gap.
    static func insertionRow(forRow row: Int, isBelowMidpoint: Bool) -> Int {
        max(row + (isBelowMidpoint ? 1 : 0), leading.count)
    }
}
