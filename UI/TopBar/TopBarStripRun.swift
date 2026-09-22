//
//  TopBarStripRun.swift
//  Luna
//
//  §4's run of tabs, as data: what the bar draws, in what order, and which of
//  the two shapes each tab takes.
//
//  Pure, the way `SidebarRowModel` is pure, and for the same reason. The
//  arrangement is the part with rules in it — kept tabs are bare icons, today's
//  tabs carry their titles, a folder stands after the loose tabs of its own
//  tier, and the hairline only comes out when there is something on both sides
//  of it. Each of those is a sentence that can be asserted rather than squinted
//  at in a screenshot.
//
//  Two shapes rather than one per tier. §3.3's grid and §3.4b's kept tier both
//  draw as bare icons: they are the tabs you keep, they are recognised by their
//  site rather than read, and a run of icons is what "kept" looks like on a bar
//  where width is the scarce thing. Today's tabs carry a title because they are
//  the ones being told apart right now.
//
//  Loose tabs before folders, inside each tier. The column can put a folder
//  between two tabs because it has as many rows as it likes; a bar has one, and
//  a named pill standing in the middle of a run of icons breaks the run in two
//  for no reason the user asked for. So the bar states its own order, and it is
//  the only arrangement here that the column does not share.
//

import BrowserKit
import Foundation

/// How a tab is drawn on §4's bar.
enum TopBarTabStyle: Sendable, Equatable {
    /// 28 pt, icon only — §3.3's tiles and §3.4b's kept tier.
    case icon
    /// Favicon and title — today's tabs.
    case chip
}

/// One drawn block on §4's bar. A folder and the tabs it is showing are one
/// block because they are drawn on one plate; everything else is itself.
enum TopBarStripBlock: Equatable, Sendable {
    case tab(Tab, style: TopBarTabStyle)
    /// §3.4b's folder, and the tabs it is showing — none when it is folded.
    case group(TabGroup, members: [Tab], style: TopBarTabStyle)
    /// The hairline between what is kept and what is not.
    case rule
}

/// §4's strip, top to bottom of its one line.
struct TopBarStripRun: Equatable, Sendable {

    let blocks: [TopBarStripBlock]
    /// How many of them are the kept run — everything in front of the hairline,
    /// and what the glass cylinder is drawn around.
    let kept: Int
    /// Every tab the run draws, in the order it draws them — what §21.1's
    /// "tab 3 of 9" counts, and what a scroll-into-view looks itself up in.
    let tabs: [Tab]

    /// - Parameters:
    ///   - essentials: §3.3's tiles for this Space.
    ///   - saved: §3.4b's kept tier, as slots.
    ///   - today: the ordinary tier, as slots.
    init(essentials: [Tab] = [], saved: [SidebarSlot] = [], today: [SidebarSlot] = []) {
        let keptBlocks = essentials.map { TopBarStripBlock.tab($0, style: .icon) }
            + Self.blocks(saved, style: .icon)
        let open = Self.blocks(today, style: .chip)
        self.kept = keptBlocks.count
        blocks = keptBlocks.isEmpty || open.isEmpty ? keptBlocks + open : keptBlocks + [.rule] + open
        tabs = blocks.flatMap { block -> [Tab] in
            switch block {
            case let .tab(tab, _): [tab]
            case let .group(_, members, _): members
            case .rule: []
            }
        }
    }

    /// `id` if it is one of the kept run's tabs — the ones §3.3's light may
    /// stand on. Nil for an open tab, and nil for a tab in a folded folder,
    /// which is not drawn at all.
    func keptTab(_ id: UUID) -> Tab? {
        blocks.prefix(kept).lazy.flatMap { block -> [Tab] in
            switch block {
            case let .tab(tab, _): [tab]
            case let .group(_, members, _): members
            case .rule: []
            }
        }
        .first { $0.id == id }
    }

    private static func blocks(_ slots: [SidebarSlot], style: TopBarTabStyle) -> [TopBarStripBlock] {
        var loose: [TopBarStripBlock] = []
        var folders: [TopBarStripBlock] = []
        for slot in slots {
            switch slot {
            case let .tab(tab):
                loose.append(.tab(tab, style: style))
            case let .group(group, members):
                folders.append(.group(group, members: group.isCollapsed ? [] : members, style: style))
            }
        }
        return loose + folders
    }
}
