//
//  SidebarDropLandingTests.swift
//  LunaTests
//
//  §6.6: where the lift comes to rest before it hands the tab over.
//
//  A drop travels into its landing place now, rather than fading out wherever
//  the pointer happened to be, and the place it travels to is the hole the gap
//  has opened — which is not the landing row's own rectangle. The rows between
//  the lift's own row and the gap close up behind it, so a landing further down
//  the list stands one row higher than its index, and a lift aimed at
//  `rect(ofRow:)` would settle one row past the space the list is holding open
//  for it.
//
//  Off by one row is the kind of mistake that looks like a stutter at the end
//  of a gesture rather than like a wrong number, which is why it is asserted
//  here instead of watched for on screen.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarDropLandingTests: XCTestCase {

    private let space = UUID()

    /// Dragging down: everything between closes up behind the lift, so the
    /// hole is one row above the index the drop means.
    func testALandingBelowTheLiftsOwnRowStandsOneRowHigher() throws {
        let controller = try list()
        controller.beginDrag(atRow: 0)
        controller.setGap(row: 3)
        XCTAssertEqual(
            controller.gapPillRect(forGapRow: 3, inside: nil, in: controller.table).minY,
            controller.pillBox(ofRow: 2).minY,
            accuracy: 0.51,
            "the lift would settle a row past the gap"
        )
    }

    /// Dragging up: the rows step down, so the hole is at the index itself.
    func testALandingAboveTheLiftsOwnRowStandsAtIt() throws {
        let controller = try list()
        controller.beginDrag(atRow: 3)
        controller.setGap(row: 1)
        XCTAssertEqual(
            controller.gapPillRect(forGapRow: 1, inside: nil, in: controller.table).minY,
            controller.pillBox(ofRow: 1).minY,
            accuracy: 0.51
        )
    }

    /// A tile carried down from §3.3 has no row here to close up behind it, so
    /// everything from the landing row down simply steps out of the way.
    func testAnIncomingLiftLandsAtTheRowItIsAimedAt() throws {
        let controller = try list()
        controller.beginIncomingDrag()
        controller.setGap(row: 2)
        XCTAssertEqual(
            controller.gapPillRect(forGapRow: 2, inside: nil, in: controller.table).minY,
            controller.pillBox(ofRow: 2).minY,
            accuracy: 0.51
        )
    }

    /// And a tab landing inside a §3.4b folder settles at the indent its row
    /// will have, which is the one the lift has already been carrying.
    func testALandingInsideAFolderCarriesTheIndent() throws {
        let controller = try list()
        controller.beginDrag(atRow: 0)
        let loose = controller.gapPillRect(forGapRow: 2, inside: nil, in: controller.table)
        let inside = controller.gapPillRect(forGapRow: 2, inside: UUID(), in: controller.table)
        XCTAssertEqual(inside.minX - loose.minX, Tokens.Metric.groupIndent, accuracy: 0.01)
        XCTAssertEqual(loose.maxX, inside.maxX, accuracy: 0.01, "the pill grew instead of stepping in")
    }

    // MARK: - Fixtures

    private func list() throws -> TabListController {
        let tabs = (0 ..< 4).map { index in
            Tab(
                spaceID: space,
                kind: .today,
                url: URL(string: "https://example.com/\(index)")!,
                title: "Tab \(index)",
                order: index
            )
        }
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 400)
        controller.show(saved: [], today: tabs.map(SidebarSlot.tab), essentials: [], activeTabID: tabs[0].id)
        controller.table.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.table.numberOfRows, 4, "the fixture has no rows to land between")
        return controller
    }
}
