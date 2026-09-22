//
//  SidebarRowModel.swift
//  Luna
//
//  The §3.4 list, as data. Pure: no AppKit, no session, no side effects — so
//  the two things that are genuinely easy to get wrong (which row is which tab,
//  and which section a drop lands in) are asserted in `Tests/Sidebar/` instead
//  of discovered by dragging a row in a running app.
//
//  The order, top to bottom (§3.4b):
//
//      saved slots  →  the rule  →  New Tab  →  today's slots
//
//  A **slot** is one top-level place: a loose tab, or a group with its tabs
//  under it. The two tiers are the same shape; what differs is what closing a
//  tab in one means. `TabList` decides the order of the slots and hands them
//  over already arranged, because "which index does a drop mean" must have
//  exactly one answer and that answer is not in two files.
//
//  **The rule is not always there.** It marks the bottom of the saved tier, so
//  with nothing saved there is no bottom to mark and no rule — the list simply
//  starts at New Tab, which is where it started before §3.4b. A drag is the
//  exception: the rule comes out for the length of one, because a zone you
//  cannot see is a zone you cannot aim at.
//
//  `Archive` is no longer a row here. It was a second way into the page the
//  bottom bar's button already opens, sitting under the pinned tiles where the
//  eye lands first — a history button at the top of a list of live tabs. History
//  belongs with the other standing destinations at the foot of the sidebar.
//
//  Essentials are not in this list; they are the §3.3 grid above the scroll
//  view, and §3.4b's groups may not go there.
//

import BrowserKit
import Foundation

/// One line of the sidebar list. `New Tab` is a first-class row with identical
/// metrics to a tab (§30.6), not header decoration.
enum SidebarRow: Hashable, Sendable {
    case addTab
    /// The rule under §3.4b's saved tier. Not selectable.
    case separator
    /// A group's header — its icon, its name, and the chevron that folds it.
    case group(UUID)
    case tab(UUID)
}

/// One top-level place in a section, as the list is handed it.
enum SidebarSlot: Equatable, Sendable {
    case tab(Tab)
    case group(TabGroup, tabs: [Tab])

    var tabID: UUID? {
        guard case let .tab(tab) = self else { return nil }
        return tab.id
    }

    var groupID: UUID? {
        guard case let .group(group, _) = self else { return nil }
        return group.id
    }
}

/// Where a drop would land: a tier, a group inside it or nil for loose, and an
/// index in whichever run that names. Exactly `BrowserSession.reorderTab`'s
/// three arguments, because it is what gets passed to it.
struct SidebarDestination: Equatable, Sendable {
    var kind: TabKind
    var groupID: UUID?
    var index: Int
}

/// The list for one Space.
struct SidebarList: Equatable, Sendable {

    /// Tabs in row order, excluding Essentials — every tab the list draws.
    let listed: [Tab]
    /// The §3.3 grid's tabs, in session order.
    let essentials: [Tab]
    let rows: [SidebarRow]
    /// Whether the rule is drawn — see the header.
    let showsRule: Bool

    private let savedSlots: [SidebarSlot]
    private let todaySlots: [SidebarSlot]
    private let groupsByID: [UUID: TabGroup]
    /// Which tabs are inside a group, and the group each one is in. Row-level
    /// questions — indentation, the spine — are answered from here rather than
    /// re-derived from `Tab.groupID`, so a row can be drawn without a lookup.
    private let memberDepth: [UUID: UUID]
    /// Per row, where a drop above and below its midpoint lands.
    ///
    /// Two answers per row rather than one per boundary, and that is the whole
    /// reason this is not an insertion-index array. The gap under a group's last
    /// tab and the gap over the next slot are the same boundary and mean two
    /// different things — the end of the group, and after it — so a list keyed
    /// by boundary can express one of them and loses the other. A pointer knows
    /// which half of which row it is on; this is keyed the same way.
    private let above: [SidebarDestination]
    private let below: [SidebarDestination]
    /// Per row, where the gap opens for a drop above and below its midpoint.
    /// Its own pair rather than `row + 1` arithmetic, because the block the
    /// rule and New Tab make has no inside — see the initialiser.
    private let gapAbove: [Int]
    private let gapBelow: [Int]

    /// - Parameter pinning: false in a §5.6 private window, which keeps
    ///   nothing — see `BrowserSession.allowsPinning`. The rule never comes
    ///   out, and `New Tab` is then the top of the column with nothing above
    ///   it: both halves of it mean the head of today's tabs, and both open
    ///   their gap underneath it.
    init(
        saved: [SidebarSlot] = [],
        today: [SidebarSlot] = [],
        essentials: [Tab] = [],
        revealingSaved: Bool = false,
        pinning: Bool = true
    ) {
        self.essentials = essentials
        showsRule = pinning && (!saved.isEmpty || revealingSaved)

        var build = Build()
        build.emit(saved, kind: .pinned)
        let todayHead = SidebarDestination(kind: .today, groupID: nil, index: 0)
        let savedEnd = SidebarDestination(kind: .pinned, groupID: nil, index: saved.count)
        if showsRule {
            // The rule and New Tab are one block: both rows mean the saved tier
            // at both halves, and both open their gap at the block's top edge.
            //
            // Two things follow, and both are the point. Nothing can be dropped
            // between the rule and New Tab, so the command row never drifts off
            // the rule it belongs to while a lift goes past. And the saved
            // tier's target is the whole block rather than a hairline, which is
            // the difference between aiming at a row and aiming at a line. The
            // head of today's tabs is still reachable — from the top half of
            // the first of them, or from the foot of an empty list.
            let head = build.rows.count
            build.add(.separator, above: savedEnd, below: savedEnd, gap: head)
            build.add(.addTab, above: savedEnd, below: savedEnd, gap: head)
        } else if pinning {
            build.add(.addTab, above: savedEnd, below: todayHead)
        } else {
            // §5.6 has no tier above New Tab, so it has no gap above it
            // either. Both halves open one row down: a lift carried to the top
            // of the column cannot push the command row aside to stand where
            // the kept tier would have been.
            build.add(.addTab, above: todayHead, below: todayHead, gap: build.rows.count + 1)
        }
        build.emit(today, kind: .today)

        savedSlots = saved
        todaySlots = today
        rows = build.rows
        above = build.above
        below = build.below
        gapAbove = build.gapAbove
        gapBelow = build.gapBelow
        listed = build.listed
        groupsByID = build.groupsByID
        memberDepth = build.memberDepth
        end = SidebarDestination(kind: .today, groupID: nil, index: today.count)
    }

    /// Where a drop past the last row lands — the foot of today's tabs.
    private let end: SidebarDestination

    var count: Int { rows.count }

    subscript(row: Int) -> SidebarRow? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    /// The tab a row shows, or nil for a group header, `New Tab` or the rule.
    func tab(at row: Int) -> Tab? {
        guard case let .tab(id)? = self[row] else { return nil }
        return listed.first { $0.id == id }
    }

    /// The group a header row shows, or nil for anything else.
    func group(at row: Int) -> TabGroup? {
        guard case let .group(id)? = self[row] else { return nil }
        return groupsByID[id]
    }

    func group(_ id: UUID) -> TabGroup? { groupsByID[id] }

    /// Every group the list is drawing, in row order, optionally without one of
    /// them — the menu that offers to move a tab into a group has no use for the
    /// group that tab is already in.
    func groups(besides excluded: UUID? = nil) -> [TabGroup] {
        rows.compactMap { row in
            guard case let .group(id) = row, id != excluded else { return nil }
            return groupsByID[id]
        }
    }

    /// The group a tab row stands inside, or nil for a loose one.
    func group(ofTab id: UUID) -> TabGroup? { memberDepth[id].flatMap { groupsByID[$0] } }

    func row(of id: UUID) -> Int? { rows.firstIndex(of: .tab(id)) }

    func row(ofGroup id: UUID) -> Int? { rows.firstIndex(of: .group(id)) }

    /// Rows the keyboard and the mouse may land on. The rule is furniture.
    func isSelectable(_ row: Int) -> Bool {
        self[row] != nil && self[row] != .separator
    }

    /// Where a drop belongs, as `BrowserSession.reorderTab` wants it.
    ///
    /// A row past the end is the foot of the list, which is what
    /// `NSTableView.row(at:)` reports for a pointer below the last row.
    func destination(forRow row: Int, isBelowMidpoint: Bool) -> SidebarDestination {
        guard rows.indices.contains(row) else { return end }
        return isBelowMidpoint ? below[row] : above[row]
    }

    /// Where the tab already stands in the run `destination` counts, or nil when
    /// it is not in that run at all.
    ///
    /// §6.6's arithmetic needs it: `reorderTab` takes the index the tab ends up
    /// at, so a move further down inside the run it is already in has to account
    /// for the gap its own removal leaves.
    func currentIndex(of id: UUID, in destination: SidebarDestination) -> Int? {
        let run = destination.kind == .pinned ? savedSlots : todaySlots
        guard let groupID = destination.groupID else {
            return run.firstIndex { $0.tabID == id }
        }
        for case let .group(group, tabs) in run where group.id == groupID {
            return tabs.firstIndex { $0.id == id }
        }
        return nil
    }

    /// The same landing with any group stripped off — where the thing being
    /// dropped may go when it cannot go inside a group. §3.4b's groups hold
    /// tabs, not other groups, so a group carried over one lands beside it:
    /// above when the pointer was asking for the group's first place, below
    /// otherwise.
    func topLevel(_ destination: SidebarDestination) -> SidebarDestination {
        guard let groupID = destination.groupID else { return destination }
        let run = destination.kind == .pinned ? savedSlots : todaySlots
        guard let slot = run.firstIndex(where: { $0.groupID == groupID }) else { return destination }
        return SidebarDestination(
            kind: destination.kind,
            groupID: nil,
            index: destination.index == 0 ? slot : slot + 1
        )
    }

    /// Where a group currently stands among its section's slots.
    func currentSlotIndex(ofGroup id: UUID, in kind: TabKind) -> Int? {
        (kind == .pinned ? savedSlots : todaySlots).firstIndex { $0.groupID == id }
    }

    /// Row index a drag snaps its gap to when it is over `row`'s upper or lower
    /// half — AppKit reports the row under the pointer, not the gap between two.
    ///
    /// Deliberately not `row + 1` for a lower half: a gap inside the rule and
    /// New Tab block would be a tab landing where no tab may go.
    func gapRow(forRow row: Int, isBelowMidpoint: Bool) -> Int {
        guard rows.indices.contains(row) else { return rows.count }
        return isBelowMidpoint ? gapBelow[row] : gapAbove[row]
    }
}

/// The rows and the two destination tables, accumulated in one pass.
///
/// Its own type rather than six `var`s in an initialiser: the tables have to
/// stay exactly as long as `rows`, and one `append` forgotten in one branch is
/// an off-by-one in every drop below that row. `add` is the only way a row gets
/// in, so the three cannot drift apart.
private struct Build {
    var rows: [SidebarRow] = []
    var above: [SidebarDestination] = []
    var below: [SidebarDestination] = []
    var gapAbove: [Int] = []
    var gapBelow: [Int] = []
    var listed: [Tab] = []
    var groupsByID: [UUID: TabGroup] = [:]
    var memberDepth: [UUID: UUID] = [:]

    /// - Parameter gap: the one row both halves open their gap at, for a row
    ///   that is part of a block. Ordinary rows take the gap above and below
    ///   themselves, which is what an index in a flat list means.
    mutating func add(
        _ row: SidebarRow,
        above: SidebarDestination,
        below: SidebarDestination,
        gap: Int? = nil
    ) {
        let index = rows.count
        rows.append(row)
        self.above.append(above)
        self.below.append(below)
        gapAbove.append(gap ?? index)
        gapBelow.append(gap ?? index + 1)
    }

    mutating func emit(_ slots: [SidebarSlot], kind: TabKind) {
        for (slot, position) in zip(slots, slots.indices) {
            let outside = SidebarDestination(kind: kind, groupID: nil, index: position)
            let after = SidebarDestination(kind: kind, groupID: nil, index: position + 1)
            switch slot {
            case let .tab(tab):
                listed.append(tab)
                add(.tab(tab.id), above: outside, below: after)
            case let .group(group, tabs):
                groupsByID[group.id] = group
                // Under the header is inside the group, either way. A folded
                // group has no tabs on screen to drop between, so the one
                // gesture it can offer is "put it in there", and the end of the
                // list is where a tab joins a run it was not in.
                add(
                    .group(group.id),
                    above: outside,
                    below: SidebarDestination(
                        kind: kind,
                        groupID: group.id,
                        index: group.isCollapsed ? tabs.count : 0
                    )
                )
                guard !group.isCollapsed else { continue }
                emit(tabs, ofGroup: group.id, kind: kind)
            }
        }
    }

    private mutating func emit(_ tabs: [Tab], ofGroup id: UUID, kind: TabKind) {
        for (member, index) in zip(tabs, tabs.indices) {
            listed.append(member)
            memberDepth[member.id] = id
            add(
                .tab(member.id),
                above: SidebarDestination(kind: kind, groupID: id, index: index),
                below: SidebarDestination(kind: kind, groupID: id, index: index + 1)
            )
        }
    }
}
