//
//  TopBarTests.swift
//  LunaTests
//
//  The pieces of the §4 top bar that are arithmetic rather than a picture: where
//  a centred run starts, that the action capsule hosts a variable number of
//  items (§30.14), and that the bar's tiles and rows are the column's own
//  sizes rather than sizes of their own.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarActionCapsuleTests: XCTestCase {

    private func item(_ id: String) -> TopBarActionItem {
        TopBarActionItem(id: id, symbolName: "plus", label: id) {}
    }

    /// §30.14: extension buttons dock into this capsule in v2. If its width
    /// stopped tracking its item count, that would mean re-laying out the whole
    /// right side of the bar later — which is exactly what building it this way
    /// was meant to avoid.
    func testWidthGrowsWithItemCountAndHeightDoesNot() {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("a"), item("b"), item("c")]
        let three = capsule.intrinsicContentSize
        capsule.items = [item("a"), item("b"), item("c"), item("d"), item("e")]
        let five = capsule.intrinsicContentSize

        XCTAssertGreaterThan(five.width, three.width)
        XCTAssertEqual(five.height, three.height)
        XCTAssertEqual(
            five.width - three.width,
            2 * (TopBarMetrics.capsuleItem.width + TopBarMetrics.gap),
            accuracy: 0.001
        )
    }

    func testEveryItemIsReachableByIdSoAPopoverCanAnchorToIt() {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("a"), item("downloads"), item("c")]
        XCTAssertNotNil(capsule.view(for: "downloads"))
        XCTAssertNil(capsule.view(for: "nope"))
    }

    /// Icon-only controls need an explicit VoiceOver label (§8, §21.1).
    func testItemsCarryTheirAccessibilityLabel() throws {
        let capsule = TopBarActionCapsule(frame: .zero)
        capsule.items = [item("Downloads")]
        let button = try XCTUnwrap(capsule.view(for: "Downloads"))
        XCTAssertEqual(button.accessibilityLabel(), "Downloads")
    }
}

@MainActor
final class TopBarTabRowTests: XCTestCase {

    /// §4's kept tab is a box the plate's own size and corner, so the lit
    /// one fills the plate top to bottom — and the plate, the open tabs and
    /// the capsule are one height.
    func testAKeptTabIsABoxThePlatesOwnSize() {
        XCTAssertEqual(TopBarMetrics.keptTile.width, TopBarMetrics.keptTile.height)
        XCTAssertEqual(TopBarMetrics.keptTile, TopBarMetrics.plate)
        XCTAssertEqual(TopBarMetrics.plate.height, TopBarMetrics.lineHeight)
        XCTAssertEqual(TopBarMetrics.lineHeight, TopBarMetrics.capsuleItem.height + TopBarMetrics.capsuleInset * 2)
    }

    /// Every tab is Dia's width, whatever its title — short, ordinary, or
    /// longer than the bar would ever give it.
    func testEveryTabIsTheSameWidthWhateverItsTitle() {
        for title in ["G", "Google", "example.com", String(repeating: "long title ", count: 20)] {
            XCTAssertEqual(TopBarTabRow.pillWidth(for: SidebarRowContent(title: title)), TopBarMetrics.tabWidth, title)
        }
    }

    /// An ordinary site's name is drawn whole in that width: the column's own
    /// row, given it, starts to fade a title only when it is longer.
    func testAnOrdinaryTitleFitsTheTab() {
        let content = SidebarRowContent(title: "example.com")
        let host = TopBarTabRow(frame: NSRect(
            x: 0,
            y: 0,
            width: TopBarTabRow.pillWidth(for: content),
            height: TopBarMetrics.lineHeight
        ))
        host.configure(content)
        host.layoutSubtreeIfNeeded()
        let column = SidebarRowView.titleColumn(
            inRowOfWidth: host.row.frame.width,
            hasUnread: false,
            slotOccupied: false
        )
        let label = NSTextField(labelWithString: "example.com")
        label.font = Tokens.TypeScale.sidebarRow
        XCTAssertGreaterThanOrEqual(column.width, label.intrinsicContentSize.width)
    }

    /// A folder's header is as long as its name, between its floor and the
    /// ceiling — it is a label on a plate, not a tab.
    func testAFoldersHeaderIsAsLongAsItsName() {
        let short = TopBarTabRow.pillWidth(for: SidebarRowContent(title: "A"), isFolder: true)
        let longer = TopBarTabRow.pillWidth(for: SidebarRowContent(title: "Work in progress"), isFolder: true)
        let longest = TopBarTabRow.pillWidth(
            for: SidebarRowContent(title: String(repeating: "long name ", count: 20)),
            isFolder: true
        )
        XCTAssertEqual(short, TopBarMetrics.rowFloor)
        XCTAssertGreaterThan(longer, short)
        XCTAssertEqual(longest, TopBarMetrics.rowCeiling)
    }
}
