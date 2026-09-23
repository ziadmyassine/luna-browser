//
//  TopBarStripRun.swift
//  Luna
//
//  §4's run of tabs, as data: what the bar draws, in what order, which of the
//  two shapes each tab takes, and where a drop between any two of them lands.
//
//  Pure, the way `SidebarRowModel` is pure, and for the same reason. The
//  arrangement is the part with rules in it — kept tabs are bare icons, today's
//  tabs carry their titles, the hairline only comes out when there is something
//  on both sides of it, and the gap under a folder's header means *inside it*.
//  Each of those is a sentence that can be asserted rather than squinted at in
//  a screenshot, and the last one is a sentence §6.6's drag stakes a `reorderTab`
//  on.
//
//  Two shapes rather than one per tier, and both are the column's. §3.3's grid
//  and §3.4b's kept tier both draw as §3.3's tile: they are the tabs you keep,
//  recognised by their site rather than read. Today's tabs are §3.4's rows,
//  with their titles, because they are the ones being told apart right now.
//
//  Slot order inside each tier, which is the column's order. The bar drew loose
//  tabs before folders for one build, on the grounds that a named pill in the
//  middle of a run of icons breaks the run in two. That was fine while the run
//  was read-only and wrong the moment it could be dragged: an order the bar
//  imposes is an order a drop cannot express, so a tab carried past a folder
//  went back in front of it and the gesture read as broken. Folders still land
//  after the tabs in practice, because that is the order they were made in.
//
//  `excluding` is what a live drag is: the run without the thing in the air.
//  The column hides a row and offsets the ones after it; a bar has one line and
//  it is cheaper to ask for the run that is actually on screen — and it makes
//  the drop index exactly what `reorderTab` wants, which counts the run with
//  the tab already taken out of it.
//

import BrowserKit
import Foundation

/// How a tab is drawn on §4's bar.
enum TopBarTabStyle: Sendable, Equatable {
    /// §3.3's tile — the grid's own, icon only. Kept tabs.
    case tile
    /// §3.4's row — favicon and title. Today's tabs.
    case row
}

/// One drawn thing on §4's bar. A folder is its header; the tabs it is
/// showing follow it as blocks of their own, because a drop can land between
/// any two of them and each needs its own two answers. Which folder a tab
/// stands in is `TopBarStripRun.owner(of:)`.
enum TopBarStripBlock: Equatable, Sendable {
    case tab(Tab, style: TopBarTabStyle)
    /// §3.4b's folder's header.
    case group(TabGroup, style: TopBarTabStyle)
    /// The hairline between what is kept and what is not. Drawn as nothing on
    /// the bar, where the Space's plate already ends the kept run; kept as a
    /// block for the two drops either side of it.
    case rule
    /// An empty place a lift can land in, drawn only while one is up: §3.3's
    /// empty tile when nothing is pinned yet, or a new folder at the end of
    /// §3.4b's tier. The column has both as its two wells (§3.3a).
    case landing(TabKind)
}

/// §4's strip, left to right along its one line.
struct TopBarStripRun: Equatable, Sendable {

    let blocks: [TopBarStripBlock]
    /// How many of them are the kept run — everything in front of the hairline.
    let kept: Int
    /// Every tab the run draws, in the order it draws them — what §21.1's
    /// "tab 3 of 9" counts, and what a scroll-into-view looks itself up in.
    let tabs: [Tab]

    /// Per block, where a drop in its leading and trailing half lands. Two
    /// answers per block rather than one per boundary, for `SidebarList`'s
    /// reason: the space after a folder's last tab and the space before the
    /// next block are the same boundary and mean two different things.
    private let leading: [SidebarDestination]
    private let trailing: [SidebarDestination]
    /// Per block, the top-level block it belongs to — itself, or the folder it
    /// is standing inside. What a folder in the air lands beside.
    private let owner: [Int]
    /// Where a drop past the last block lands — the end of today's tabs.
    private let end: SidebarDestination

    /// - Parameters:
    ///   - essentials: §3.3's tiles for this Space.
    ///   - saved: §3.4b's kept tier, as slots.
    ///   - today: the ordinary tier, as slots.
    ///   - excluding: the tab or folder in the air, which the run leaves out
    ///     entirely — a folder takes its tabs with it.
    ///   - landings: the empty places to offer a lift. `.essential` is offered
    ///     only while nothing is pinned, because among tiles a drop already has
    ///     somewhere to go; `.pinned` always stands at the end of its tier.
    init(
        essentials: [Tab] = [],
        saved: [SidebarSlot] = [],
        today: [SidebarSlot] = [],
        excluding lifted: UUID? = nil,
        landings: Set<TabKind> = []
    ) {
        var build = Build()
        let tiles = essentials.filter { $0.id != lifted }
        build.emit(tiles, kind: .essential)
        if tiles.isEmpty, landings.contains(.essential) { build.emitLanding(.essential) }
        build.emit(saved, kind: .pinned, excluding: lifted)
        if landings.contains(.pinned) { build.emitLanding(.pinned) }
        let keptCount = build.blocks.count
        let openStart = build.blocks.count
        build.emit(today, kind: .today, excluding: lifted)

        kept = keptCount
        if keptCount > 0, build.blocks.count > openStart {
            build.insertRule(
                at: keptCount,
                leading: SidebarDestination(kind: .pinned, groupID: nil, index: build.slots(.pinned)),
                trailing: SidebarDestination(kind: .today, groupID: nil, index: 0)
            )
        }
        blocks = build.blocks
        leading = build.leading
        trailing = build.trailing
        owner = build.owner
        tabs = build.tabs
        end = SidebarDestination(kind: .today, groupID: nil, index: build.slots(.today))
    }

    /// Whether `block` is in front of the hairline — on the Space's plate.
    func isKept(_ block: Int) -> Bool { block < kept }

    /// `id` if it is one of the kept run's tabs — the ones §3.3's light may
    /// stand on. Nil for an open tab, and nil for a tab in a folded folder,
    /// which is not drawn at all.
    func keptTab(_ id: UUID) -> Tab? {
        for case let .tab(tab, _) in blocks.prefix(kept) where tab.id == id { return tab }
        return nil
    }

    /// The top-level block `block` belongs to: itself, or the header of the
    /// folder it stands in.
    func owner(of block: Int) -> Int { owner[block] }

    /// The last block a folder takes up — its header when it is shut.
    func lastBlock(ofFolderAt header: Int) -> Int {
        var last = header
        while last + 1 < blocks.count, owner[last + 1] == header { last += 1 }
        return last
    }

    /// Where a drop on `block` belongs, as `BrowserSession.reorderTab` wants
    /// it. A block past the end is the end of the run, which is what a pointer
    /// beyond the last tab means.
    func destination(forBlock block: Int, isPastMidpoint: Bool) -> SidebarDestination {
        guard blocks.indices.contains(block) else { return end }
        return isPastMidpoint ? trailing[block] : leading[block]
    }

    /// The block a gap opens in front of, for a pointer on `block`'s leading or
    /// trailing half. `blocks.count` is the end of the run.
    ///
    /// Not `block + 1` for a trailing half on a folder's header: the gap that
    /// means "inside this folder" opens in front of its first tab, which is the
    /// next block along, and in front of nothing at all when it is shut.
    func gap(forBlock block: Int, isPastMidpoint: Bool) -> Int {
        guard blocks.indices.contains(block) else { return blocks.count }
        if case .landing = blocks[block] { return block }
        return isPastMidpoint ? block + 1 : block
    }

    /// Where a folder dropped on `block` belongs. §3.4b's folders hold tabs,
    /// not other folders, so one carried over a folder — or over a tab inside
    /// one — lands beside that folder rather than in it.
    ///
    /// A top-level block's leading destination is always its own slot with no
    /// folder on it, which is why one step past it is all this has to add.
    func folderDestination(forBlock block: Int, isPastMidpoint: Bool) -> SidebarDestination {
        guard blocks.indices.contains(block) else { return end }
        let top = owner[block]
        switch blocks[top] {
        case .rule: return destination(forBlock: top, isPastMidpoint: isPastMidpoint)
        case .landing: return leading[top]
        default: break
        }
        var landing = leading[top]
        if isPastMidpoint { landing.index += 1 }
        return landing
    }

}

/// The blocks and the two destination tables, accumulated in one pass.
///
/// Its own type for `SidebarRowModel.Build`'s reason: the tables have to stay
/// exactly as long as `blocks`, and one `append` forgotten in one branch is an
/// off-by-one in every drop after it. `add` is the only way a block gets in.
private struct Build {
    var blocks: [TopBarStripBlock] = []
    var leading: [SidebarDestination] = []
    var trailing: [SidebarDestination] = []
    var owner: [Int] = []
    var tabs: [Tab] = []
    /// Slots emitted per tier so far — what the next index in that tier is, and
    /// what the end of it is once the tier is done.
    private var counts: [TabKind: Int] = [:]

    func slots(_ kind: TabKind) -> Int { counts[kind] ?? 0 }

    /// An empty place at the end of `kind`'s run so far. Both halves are the
    /// same landing: there is nothing on either side of it to be before or
    /// after. Not a slot — it is where the next one would be.
    mutating func emitLanding(_ kind: TabKind) {
        let place = SidebarDestination(kind: kind, groupID: nil, index: slots(kind))
        add(.landing(kind), leading: place, trailing: place)
    }

    /// - Parameter inside: the top-level block this one stands in, for a
    ///   folder's own tabs. Nil means the block is top-level and owns itself.
    mutating func add(
        _ block: TopBarStripBlock,
        leading: SidebarDestination,
        trailing: SidebarDestination,
        inside: Int? = nil
    ) {
        owner.append(inside ?? blocks.count)
        blocks.append(block)
        self.leading.append(leading)
        self.trailing.append(trailing)
    }

    mutating func insertRule(at index: Int, leading: SidebarDestination, trailing: SidebarDestination) {
        blocks.insert(.rule, at: index)
        self.leading.insert(leading, at: index)
        self.trailing.insert(trailing, at: index)
        // Everything after the hairline moved one along, and the hairline owns
        // itself.
        owner = owner.map { $0 >= index ? $0 + 1 : $0 }
        owner.insert(index, at: index)
    }

    /// §3.3's tiles: one tab per slot, no folders, and the index is the
    /// position in the grid.
    mutating func emit(_ essentials: [Tab], kind: TabKind) {
        for tab in essentials {
            let slot = slots(kind)
            counts[kind] = slot + 1
            tabs.append(tab)
            add(
                .tab(tab, style: .tile),
                leading: SidebarDestination(kind: kind, groupID: nil, index: slot),
                trailing: SidebarDestination(kind: kind, groupID: nil, index: slot + 1)
            )
        }
    }

    mutating func emit(_ slots: [SidebarSlot], kind: TabKind, excluding lifted: UUID?) {
        let style: TopBarTabStyle = kind == .today ? .row : .tile
        for slot in slots {
            switch slot {
            case let .tab(tab):
                guard tab.id != lifted else { continue }
                let index = self.slots(kind)
                counts[kind] = index + 1
                tabs.append(tab)
                add(
                    .tab(tab, style: style),
                    leading: SidebarDestination(kind: kind, groupID: nil, index: index),
                    trailing: SidebarDestination(kind: kind, groupID: nil, index: index + 1)
                )
            case let .group(group, members):
                guard group.id != lifted else { continue }
                let open = members.filter { $0.id != lifted }
                let index = self.slots(kind)
                counts[kind] = index + 1
                add(
                    .group(group, style: style),
                    leading: SidebarDestination(kind: kind, groupID: nil, index: index),
                    // Past the header is inside the folder, either way. A shut
                    // folder has no tabs on screen to drop between, so the one
                    // gesture it can offer is "put it in there", and the end of
                    // the run is where a tab joins one it was not in.
                    trailing: SidebarDestination(
                        kind: kind,
                        groupID: group.id,
                        index: group.isCollapsed ? open.count : 0
                    )
                )
                guard !group.isCollapsed else { continue }
                emit(open, ofGroup: group.id, kind: kind, inside: blocks.count - 1)
            }
        }
    }

    private mutating func emit(_ members: [Tab], ofGroup id: UUID, kind: TabKind, inside header: Int) {
        for (member, index) in zip(members, members.indices) {
            tabs.append(member)
            add(
                .tab(member, style: kind == .today ? .row : .tile),
                leading: SidebarDestination(kind: kind, groupID: id, index: index),
                trailing: SidebarDestination(kind: kind, groupID: id, index: index + 1),
                inside: header
            )
        }
    }
}
