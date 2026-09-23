//
//  TopBarStripRunTests.swift
//  LunaTests
//
//  §4's arrangement: kept tabs as icons, open tabs as chips, folders after the
//  loose tabs of their own tier, and a hairline only where there is something
//  on both sides of it.
//
//  Every one of those is a sentence, which is why `TopBarStripRun` is pure. The
//  bar it draws is one line of chips a few points apart, and a run that put the
//  hairline in the wrong place would look like a run that had it in the right
//  one until you counted.
//

import XCTest
@testable import Luna
@testable import BrowserKit

@MainActor
final class TopBarStripRunTests: XCTestCase {

    private let space = UUID()

    private func tab(_ name: String, kind: TabKind = .today) -> Tab {
        Tab(spaceID: space, kind: kind, url: URL(string: "https://\(name).com")!, title: name)
    }

    private func group(_ name: String, kind: TabKind = .today, collapsed: Bool = false) -> TabGroup {
        TabGroup(spaceID: space, name: name, kind: kind, isCollapsed: collapsed)
    }

    private func styles(_ run: TopBarStripRun) -> [TopBarTabStyle] {
        run.blocks.compactMap { block in
            switch block {
            case let .tab(_, style): style
            case let .group(_, style): style
            case .rule, .landing: nil
            }
        }
    }

    private func names(_ run: TopBarStripRun) -> [String] {
        run.blocks.map { block in
            switch block {
            case let .tab(tab, _): tab.title
            case let .group(group, _): group.name
            case .rule: "|"
            case .landing: "_"
            }
        }
    }

    // MARK: - The two shapes

    func testAKeptTabIsAnIconAndAnOpenTabIsAChip() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            saved: [.tab(tab("docs", kind: .pinned))],
            today: [.tab(tab("news"))]
        )
        XCTAssertEqual(styles(run), [.tile, .tile, .row])
    }

    func testAFoldersTabsTakeItsOwnTiersShape() {
        let saved = group("Work", kind: .pinned)
        let run = TopBarStripRun(
            saved: [.group(saved, tabs: [tab("docs", kind: .pinned)])],
            today: [.group(group("Fun"), tabs: [tab("news")])]
        )
        // Header, its tab; header, its tab.
        XCTAssertEqual(styles(run), [.tile, .tile, .row, .row])
    }

    // MARK: - The order

    /// The column's order, not one of the bar's own: an order the bar imposed
    /// would be an order a drop could not express.
    func testEachTierKeepsItsSlotOrder() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            saved: [.group(group("Work", kind: .pinned), tabs: []), .tab(tab("docs", kind: .pinned))],
            today: [.group(group("Fun"), tabs: []), .tab(tab("news"))]
        )
        XCTAssertEqual(names(run), ["mail", "Work", "docs", "|", "Fun", "news"])
    }

    func testAnOpenFolderCarriesItsTabsAndAFoldedOneDoesNot() {
        let open = TopBarStripRun(today: [.group(group("Fun"), tabs: [tab("news")])])
        XCTAssertEqual(open.tabs.map(\.title), ["news"])
        XCTAssertEqual(open.lastBlock(ofFolderAt: 0), 1)
        XCTAssertEqual(open.owner(of: 1), 0, "a folder's tab does not belong to its folder")

        let folded = TopBarStripRun(today: [.group(group("Fun", collapsed: true), tabs: [tab("news")])])
        XCTAssertTrue(folded.tabs.isEmpty)
        XCTAssertEqual(folded.blocks.count, 1)
        XCTAssertEqual(folded.lastBlock(ofFolderAt: 0), 0)
    }

    // MARK: - The hairline

    func testTheHairlineDividesTheTwoRuns() {
        let run = TopBarStripRun(essentials: [tab("mail", kind: .essential)], today: [.tab(tab("news"))])
        XCTAssertEqual(names(run), ["mail", "|", "news"])
    }

    /// What the glass cylinder is drawn around: everything in front of the
    /// hairline, and nothing behind it.
    func testTheKeptCountIsTheRunInFrontOfTheHairline() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            saved: [.tab(tab("docs", kind: .pinned)), .group(group("Work", kind: .pinned), tabs: [])],
            today: [.tab(tab("news"))]
        )
        XCTAssertEqual(run.kept, 3)
        XCTAssertEqual(run.blocks[run.kept], .rule)
    }

    // MARK: - Where a drop lands (§6.6)

    private func landing(_ kind: TabKind, _ index: Int, in folder: UUID? = nil) -> SidebarDestination {
        SidebarDestination(kind: kind, groupID: folder, index: index)
    }

    func testEitherHalfOfATabIsEitherSideOfIt() {
        let run = TopBarStripRun(today: [.tab(tab("one")), .tab(tab("two"))])
        XCTAssertEqual(run.destination(forBlock: 1, isPastMidpoint: false), landing(.today, 1))
        XCTAssertEqual(run.destination(forBlock: 1, isPastMidpoint: true), landing(.today, 2))
        XCTAssertEqual(run.destination(forBlock: 9, isPastMidpoint: false), landing(.today, 2), "past the end")
    }

    /// The column's rule, turned on its side: past a folder's header is inside
    /// it — at the front when it is open, at the end when it is shut.
    func testPastAFoldersHeaderIsInsideIt() {
        let open = group("Work")
        let shut = group("Play", collapsed: true)
        let run = TopBarStripRun(today: [
            .group(open, tabs: [tab("a"), tab("b")]),
            .group(shut, tabs: [tab("c"), tab("d"), tab("e")])
        ])
        XCTAssertEqual(run.destination(forBlock: 0, isPastMidpoint: true), landing(.today, 0, in: open.id))
        XCTAssertEqual(run.destination(forBlock: 2, isPastMidpoint: true), landing(.today, 2, in: open.id))
        XCTAssertEqual(run.destination(forBlock: 3, isPastMidpoint: false), landing(.today, 1))
        XCTAssertEqual(run.destination(forBlock: 3, isPastMidpoint: true), landing(.today, 3, in: shut.id))
    }

    /// A tab becomes the same kind of thing as what it lands beside, and the
    /// hairline's two halves are the end of one tier and the head of the other.
    func testTheTierIsTheNeighboursAndTheHairlineSplitsThem() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            saved: [.tab(tab("docs", kind: .pinned))],
            today: [.tab(tab("news"))]
        )
        XCTAssertEqual(run.destination(forBlock: 0, isPastMidpoint: true), landing(.essential, 1))
        XCTAssertEqual(run.destination(forBlock: 1, isPastMidpoint: false), landing(.pinned, 0))
        XCTAssertEqual(run.destination(forBlock: 2, isPastMidpoint: false), landing(.pinned, 1), "left of the hairline")
        XCTAssertEqual(run.destination(forBlock: 2, isPastMidpoint: true), landing(.today, 0), "right of it")
    }

    /// What is in the air is not in the run, so the index a drop reports is
    /// the one `reorderTab` counts — with the tab already taken out.
    func testALiftedTabLeavesTheRunAndTheIndicesCloseUp() {
        let lifted = tab("two")
        let run = TopBarStripRun(today: [.tab(tab("one")), .tab(lifted), .tab(tab("three"))], excluding: lifted.id)
        XCTAssertEqual(names(run), ["one", "three"])
        XCTAssertEqual(run.destination(forBlock: 1, isPastMidpoint: true), landing(.today, 2))
    }

    /// §3.4b's folders hold tabs, not folders: one carried over a folder, or
    /// over a tab inside one, lands beside that folder.
    func testAFolderNeverLandsInsideAnother() {
        let work = group("Work")
        let run = TopBarStripRun(today: [.tab(tab("loose")), .group(work, tabs: [tab("a"), tab("b")])])
        XCTAssertEqual(run.folderDestination(forBlock: 1, isPastMidpoint: true), landing(.today, 2))
        XCTAssertEqual(run.folderDestination(forBlock: 3, isPastMidpoint: false), landing(.today, 1))
        XCTAssertEqual(run.folderDestination(forBlock: 0, isPastMidpoint: false), landing(.today, 0))
    }

    /// The light only ever stands on a kept chip: an open tab says it is the
    /// current one with §3.4's plate instead.
    func testOnlyAKeptTabCanCarryTheLight() {
        let kept = tab("mail", kind: .essential)
        let open = tab("news")
        let run = TopBarStripRun(essentials: [kept], today: [.tab(open)])
        XCTAssertEqual(run.keptTab(kept.id)?.id, kept.id)
        XCTAssertNil(run.keptTab(open.id))
    }

    func testNothingKeptMeansNoHairline() {
        let run = TopBarStripRun(today: [.tab(tab("news"))])
        XCTAssertFalse(run.blocks.contains(.rule))
    }

    func testNothingOpenMeansNoHairlineEither() {
        let run = TopBarStripRun(essentials: [tab("mail", kind: .essential)])
        XCTAssertFalse(run.blocks.contains(.rule))
    }

    // MARK: - What the run counts

    func testTheTabsAreEveryTabDrawnInTheOrderTheyAreDrawn() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            today: [.tab(tab("news")), .group(group("Fun"), tabs: [tab("video"), tab("music")])]
        )
        XCTAssertEqual(run.tabs.map(\.title), ["mail", "news", "video", "music"])
    }

    // MARK: - The landings a lift opens

    /// The empty tile is offered only while nothing is pinned — among tiles a
    /// drop already has somewhere to go — and the folder landing always stands
    /// at the end of the kept tier, before the hairline.
    func testTheLandingsStandOnThePlate() {
        let open = tab("news")
        let empty = TopBarStripRun(today: [.tab(open)], landings: [.essential, .pinned])
        XCTAssertEqual(names(empty), ["_", "_", "|", "news"])
        XCTAssertEqual(empty.kept, 2)

        let pinned = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            today: [.tab(open)],
            landings: [.essential, .pinned]
        )
        XCTAssertEqual(names(pinned), ["mail", "_", "|", "news"])
    }

    /// A drop on a landing fills it, and means the place it stands for: the
    /// first tile, or a new folder at the end of the kept tier.
    func testALandingMeansTheNextPlaceInItsTier() {
        let saved = group("Work", kind: .pinned)
        let run = TopBarStripRun(
            saved: [.group(saved, tabs: [])],
            today: [.tab(tab("news"))],
            landings: [.essential, .pinned]
        )
        // Empty tile, the folder, the folder landing, the hairline, news.
        XCTAssertEqual(run.destination(forBlock: 0, isPastMidpoint: true), SidebarDestination(kind: .essential, groupID: nil, index: 0))
        XCTAssertEqual(run.destination(forBlock: 2, isPastMidpoint: false), SidebarDestination(kind: .pinned, groupID: nil, index: 1))
        XCTAssertEqual(run.gap(forBlock: 2, isPastMidpoint: true), 2, "a landing is filled, not stepped past")
        XCTAssertEqual(run.folderDestination(forBlock: 2, isPastMidpoint: true), SidebarDestination(kind: .pinned, groupID: nil, index: 1))
    }
}
