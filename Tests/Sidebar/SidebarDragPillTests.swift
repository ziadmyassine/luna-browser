//
//  SidebarDragPillTests.swift
//  LunaTests
//
//  §6.6: while a lift is up, §3.4's two row fills stay parked.
//
//  The lift carries the selected pill itself, so a second one left lying in the
//  row the tab came from is a glass pill with nothing in it, following the drag
//  down the column and still there on the way back — which is exactly what
//  happened, because `setPillsHidden(true)` parks them once and a dozen things
//  ask for a pill move afterwards. A drag is when the list is re-laid most: the
//  §3.3 grid opens to a tile's height, §3.4b's rule comes out, the gap moves.
//  Every one of those reaches `movePills`.
//
//  So the rule is asserted where it is enforced — one guard, every caller — and
//  the test drives the three routes that used to break it.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarDragPillTests: XCTestCase {

    private let space = UUID()

    func testTheListsOwnFillsStayParkedForTheLengthOfALift() throws {
        let controller = try list()
        let dragged = try XCTUnwrap(controller.list.tab(at: 1))
        controller.beginDrag(atRow: 1)

        XCTAssertEqual(controller.selectionPill.alphaValue, 0, accuracy: 0.001, "the fill was not parked")

        // The three that used to bring it back: a layout pass (§3.3's grid
        // opening is one), the gap stepping to a new row, and a rebuild —
        // which is what §3.4b's rule coming out is.
        controller.table.layoutSubtreeIfNeeded()
        controller.setGap(row: 3)
        controller.setRevealingSaved(true)

        XCTAssertEqual(
            controller.selectionPill.alphaValue, 0, accuracy: 0.001,
            "a second selected pill came back in the row the lift left"
        )
        XCTAssertEqual(controller.hoverPill.alphaValue, 0, accuracy: 0.001)
        XCTAssertNotNil(dragged)
    }

    /// And they come back when it lands — parked is for the gesture, not for good.
    func testTheFillsComeBackOnTheDrop() throws {
        let controller = try list()
        controller.beginDrag(atRow: 1)
        controller.setRevealingSaved(true)

        controller.setRevealingSaved(false)
        controller.endDrag()
        controller.movePills(animated: false)

        XCTAssertEqual(controller.selectionPill.alphaValue, 1, accuracy: 0.001, "the fill never came back")
    }

    /// A tile carried down from §3.3 has no row here to be carried from, and
    /// the same rule holds: the lift is the only highlight on the column.
    func testAnIncomingLiftParksThemToo() throws {
        let controller = try list()
        controller.beginIncomingDrag()
        controller.setRevealingSaved(true)
        controller.table.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.selectionPill.alphaValue, 0, accuracy: 0.001)
    }

    // MARK: - Fixtures

    /// Three tabs, the first one selected, laid out in a window — the pill has
    /// to have been shown before it can be wrongly shown again.
    private func list() throws -> TabListController {
        let tabs = (0 ..< 3).map { index in
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
        controller.show(
            saved: [],
            today: tabs.map(SidebarSlot.tab),
            essentials: [],
            activeTabID: tabs[0].id
        )
        controller.table.layoutSubtreeIfNeeded()
        controller.movePills(animated: false)
        XCTAssertEqual(controller.selectionPill.alphaValue, 1, accuracy: 0.001, "nothing was showing to begin with")
        return controller
    }
}
