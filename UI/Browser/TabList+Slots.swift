//
//  TabList+Slots.swift
//  Luna
//
//  §3.4b's groups, and the run of indices they share with the loose tabs around
//  them. The other half of `TabList`, split off because the two subjects are
//  genuinely different: that file is "where does a tab go", this one is "what is
//  a place in the list".
//
//  A **slot** is one top-level position in a section: a loose tab, or a group.
//  They are numbered together, because §3.4b lets a group stand between two
//  loose tabs — so every mutation ends by rewriting a whole section's slots
//  `0..<n` and handing back everything it touched. Renumbering only one of the
//  two would leave the other's indices interleaved with values that no longer
//  exist, and the arrangement on disk would stop matching the one on screen.
//
//  Nothing here reads `order` to decide an arrangement. `order` is the value
//  being replaced: the array the caller built is the truth, and its positions
//  are what get written. `slots(inSpace:kind:)` is the one place `order` is
//  read, and it is a read.
//

import BrowserKit
import Foundation

/// One top-level place in a section (§3.4b).
enum TabSlot: Sendable, Equatable {
    case tab(Tab)
    case group(TabGroup)

    var id: UUID {
        switch self {
        case let .tab(tab): tab.id
        case let .group(group): group.id
        }
    }

    /// The tab this slot is, or nil when it is a group. Named for the question
    /// every caller actually asks — "is this loose tab the one I am moving".
    var tabID: UUID? {
        guard case let .tab(tab) = self else { return nil }
        return tab.id
    }

    var groupID: UUID? {
        guard case let .group(group) = self else { return nil }
        return group.id
    }

    var order: Int {
        switch self {
        case let .tab(tab): tab.order
        case let .group(group): group.order
        }
    }

    /// Tabs before groups when two slots claim the same index. A tie is
    /// transient — the next mutation renumbers the section — so this only has
    /// to be the same answer twice, not the right one.
    fileprivate var tieBreak: (Int, String) {
        switch self {
        case let .tab(tab): (0, tab.id.uuidString)
        case let .group(group): (1, group.id.uuidString)
        }
    }
}

extension TabList {

    // MARK: - Reading

    func groups(inSpace spaceID: UUID) -> [TabGroup] {
        (groupsBySpace[spaceID] ?? []).sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    func group(_ id: UUID) -> TabGroup? {
        for groups in groupsBySpace.values where groups.contains(where: { $0.id == id }) {
            return groups.first { $0.id == id }
        }
        return nil
    }

    /// The tabs inside a group, in the order it draws them.
    func members(ofGroup id: UUID) -> [Tab] {
        guard let group = group(id) else { return [] }
        return own(group.spaceID)
            .filter { $0.groupID == id }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    /// One section's top-level places, in the order §3.4 draws them.
    ///
    /// `.essential` has none: §3.3's grid is a Profile's tier of tiles rather
    /// than a Space's run of slots, and a group cannot be a tile at all.
    func slots(inSpace spaceID: UUID, kind: TabKind) -> [TabSlot] {
        guard kind != .essential else { return [] }
        let loose = own(spaceID)
            .filter { $0.kind == kind && $0.groupID == nil }
            .map(TabSlot.tab)
        let groups = (groupsBySpace[spaceID] ?? [])
            .filter { $0.kind == kind }
            .map(TabSlot.group)
        return (loose + groups).sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.tieBreak < rhs.tieBreak : lhs.order < rhs.order
        }
    }

    /// One section as §3.4 draws it: its slots, each group carrying its own
    /// tabs. The one crossing between the ordering rules in here and the rows in
    /// `SidebarList`, so the column has no arrangement of its own to disagree with.
    func drawnSlots(inSpace spaceID: UUID, kind: TabKind) -> [SidebarSlot] {
        slots(inSpace: spaceID, kind: kind).map { slot in
            switch slot {
            case let .tab(tab): .tab(tab)
            case let .group(group): .group(group, tabs: members(ofGroup: group.id))
            }
        }
    }

    // MARK: - Moving groups

    /// Puts a group into a section's slots at `index`, or at the end of them.
    ///
    /// Its members come with it: a group that has crossed between the saved tier
    /// and the ordinary one takes its tabs' `kind` along, which is what keeps
    /// "is this saved" a single question with a single answer.
    ///
    /// A group belongs to the Space it was made in and does not travel between
    /// them — there is no gesture that carries one, and a tab dragged to another
    /// Space leaves its group behind (`BrowserSession.moveTab`). So `spaceID` is
    /// read from the group and never changed here.
    @discardableResult
    mutating func insertGroup(_ group: TabGroup, at index: Int? = nil) -> TabListWrites {
        let placed = group.sanitisingKind()
        var writes = TabListWrites()
        // Crossing the rule is leaving one array for another, so the slot it
        // vacates has to close up before the slot it takes is opened.
        if let existing = self.group(placed.id), existing.kind != placed.kind {
            groupsBySpace[existing.spaceID]?.removeAll { $0.id == placed.id }
            writes += apply(
                slots(inSpace: existing.spaceID, kind: existing.kind),
                inSpace: existing.spaceID,
                kind: existing.kind
            )
        }
        var slots = slots(inSpace: placed.spaceID, kind: placed.kind).filter { $0.groupID != placed.id }
        slots.insert(.group(placed), at: Self.clamp(index, to: slots.count))
        writes += apply(slots, inSpace: placed.spaceID, kind: placed.kind)
        return writes
    }

    /// Renames a group, folds it, or gives it another icon — anything that does
    /// not move it. In place, so nothing is renumbered for a change of name.
    mutating func updateGroup(_ group: TabGroup) {
        let sanitised = group.sanitisingKind()
        guard let index = groupsBySpace[sanitised.spaceID]?.firstIndex(where: { $0.id == sanitised.id }),
              groupsBySpace[sanitised.spaceID]?[index].kind == sanitised.kind else { return }
        groupsBySpace[sanitised.spaceID]?[index] = sanitised
    }

    /// Takes the group away and leaves its tabs where it stood, loose, in its
    /// own order — §3.4b's *Ungroup*.
    ///
    /// Not a deletion of anything the user can see disappear: a group is a name
    /// around some tabs, so removing it removes the name. The command that does
    /// end the tabs archives them first, one at a time, where undo can reach them.
    @discardableResult
    mutating func removeGroup(_ id: UUID) -> TabListWrites {
        guard let group = group(id) else { return TabListWrites() }
        let released = members(ofGroup: id)
        var slots = slots(inSpace: group.spaceID, kind: group.kind)
        guard let at = slots.firstIndex(where: { $0.groupID == id }) else { return TabListWrites() }
        slots.replaceSubrange(at ... at, with: released.map { TabSlot.tab($0) })
        // Out of storage before the rewrite: `apply` re-adds what the slots
        // hold, and the members are still carrying a `groupID` it does not clear.
        groupsBySpace[group.spaceID]?.removeAll { $0.id == id }
        bySpace[group.spaceID]?.removeAll { $0.groupID == id }
        return apply(slots, inSpace: group.spaceID, kind: group.kind)
    }

    // MARK: - Renumbering

    /// Writes a section's slots back, renumbered `0..<n`.
    /// - Returns: every row it rewrote, for the caller to persist.
    @discardableResult
    mutating func apply(_ slots: [TabSlot], inSpace spaceID: UUID, kind: TabKind) -> TabListWrites {
        var writes = TabListWrites()
        // Which tier each group was standing in a moment ago, read before the
        // rewrite erases it. A group that has crossed the rule takes its tabs
        // with it, and this is the one line that can still tell that it did —
        // afterwards every group in the array is wearing the new kind. A group
        // that is not in here at all is arriving, which counts as a crossing.
        let previousKind = (groupsBySpace[spaceID] ?? []).reduce(into: [UUID: TabKind]()) { map, group in
            map[group.id] = group.kind
        }
        bySpace[spaceID]?.removeAll { $0.kind == kind && $0.groupID == nil }
        groupsBySpace[spaceID]?.removeAll { $0.kind == kind }
        for (position, slot) in slots.enumerated() {
            switch slot {
            case .tab(var tab):
                tab.order = position
                tab.kind = kind
                tab.groupID = nil
                tab.spaceID = spaceID
                // §3.4b's dimmed rows only exist in the saved tier: a tab
                // carried down past the rule is an ordinary open tab again.
                if kind == .today { tab.isDormant = false }
                bySpace[spaceID, default: []].append(tab)
                writes.tabs.append(tab)
            case .group(var group):
                let crossedTheRule = previousKind[group.id] != kind
                group.order = position
                group.kind = kind
                group.spaceID = spaceID
                groupsBySpace[spaceID, default: []].append(group)
                writes.groups.append(group)
                if crossedTheRule { writes += apply(members(ofGroup: group.id), ofGroup: group) }
            }
        }
        bySpace[spaceID] = Self.sorted(own(spaceID))
        return writes
    }

    /// Writes a group's members back, renumbered `0..<n` inside it, each one
    /// wearing the group's own `kind` and Space.
    @discardableResult
    mutating func apply(_ members: [Tab], ofGroup group: TabGroup) -> TabListWrites {
        var writes = TabListWrites()
        bySpace[group.spaceID]?.removeAll { $0.groupID == group.id }
        for (position, member) in members.enumerated() {
            var member = member
            member.order = position
            member.kind = group.kind
            member.groupID = group.id
            member.spaceID = group.spaceID
            // §3.4b's dimmed rows only exist in the saved tier. A group carried
            // down into the ordinary section brings its tabs back as live ones.
            if group.kind == .today { member.isDormant = false }
            bySpace[group.spaceID, default: []].append(member)
            writes.tabs.append(member)
        }
        bySpace[group.spaceID] = Self.sorted(own(group.spaceID))
        return writes
    }
}
