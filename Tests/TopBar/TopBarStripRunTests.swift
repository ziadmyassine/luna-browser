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
            case let .group(_, _, style): style
            case .rule: nil
            }
        }
    }

    private func names(_ run: TopBarStripRun) -> [String] {
        run.blocks.map { block in
            switch block {
            case let .tab(tab, _): tab.title
            case let .group(group, _, _): group.name
            case .rule: "|"
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
        XCTAssertEqual(styles(run), [.icon, .icon, .chip])
    }

    func testAFoldersTabsTakeItsOwnTiersShape() {
        let saved = group("Work", kind: .pinned)
        let run = TopBarStripRun(
            saved: [.group(saved, tabs: [tab("docs", kind: .pinned)])],
            today: [.group(group("Fun"), tabs: [tab("news")])]
        )
        XCTAssertEqual(styles(run), [.icon, .chip])
    }

    // MARK: - The order

    func testLooseTabsComeBeforeTheFoldersOfTheirOwnTier() {
        let run = TopBarStripRun(
            essentials: [tab("mail", kind: .essential)],
            saved: [.group(group("Work", kind: .pinned), tabs: []), .tab(tab("docs", kind: .pinned))],
            today: [.group(group("Fun"), tabs: []), .tab(tab("news"))]
        )
        XCTAssertEqual(names(run), ["mail", "docs", "Work", "|", "news", "Fun"])
    }

    func testAnOpenFolderCarriesItsTabsAndAFoldedOneDoesNot() {
        let open = TopBarStripRun(today: [.group(group("Fun"), tabs: [tab("news")])])
        XCTAssertEqual(open.tabs.map(\.title), ["news"])

        let folded = TopBarStripRun(today: [.group(group("Fun", collapsed: true), tabs: [tab("news")])])
        XCTAssertTrue(folded.tabs.isEmpty)
        XCTAssertEqual(folded.blocks.count, 1)
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
}
