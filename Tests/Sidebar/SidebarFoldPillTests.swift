//
//  SidebarFoldPillTests.swift
//  LunaTests
//
//  §3.4b: when a folder folds or opens above the tab you are on, the
//  selection pill rides with that tab's row on the rows' own clock. It used
//  to follow on its usual spring, which settles later, and every layout pass
//  in between snapped it to the end — it trailed its row and caught up in a
//  jump. Measured off the controller's own views; nothing is put on screen.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarFoldPillTests: XCTestCase {

    private let space = UUID()
    private var trip = TabGroup(spaceID: UUID(), name: "Trip", order: 0)
    private var work = TabGroup(spaceID: UUID(), name: "Work", order: 1)
    private lazy var tabs = (0 ..< 6).map { index in
        Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(index)")!,
            title: "Tab \(index)", order: index)
    }

    /// The tab you are on, in the second folder, under the one that folds.
    private var current: Tab { tabs[4] }

    private func show(_ controller: TabListController) {
        controller.show(
            saved: [],
            today: [.group(trip, tabs: Array(tabs[0 ..< 3])), .group(work, tabs: Array(tabs[3 ..< 6]))],
            essentials: [],
            activeTabID: current.id
        )
    }

    func testThePillRidesWithItsRowWhenAFolderAboveFolds() throws {
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 500)
        show(controller)
        controller.table.layoutSubtreeIfNeeded()

        trip.isCollapsed = true
        show(controller)
        let row = try XCTUnwrap(controller.list.row(of: current.id))
        XCTAssertEqual(controller.selectionPill.frame, controller.pillBox(ofRow: row), "the pill is not bound for its row")

        let layer = try XCTUnwrap(controller.selectionPill.layer)
        guard !Tokens.Motion.reduceMotion else { return XCTAssertNil(layer.animation(forKey: "position")) }
        let ride = try XCTUnwrap(layer.animation(forKey: "position") as? CABasicAnimation, "the pill did not ride")
        XCTAssertFalse(ride is CASpringAnimation, "the pill followed on its own spring")
        XCTAssertEqual(ride.duration, Tokens.Motion.tabInsert.duration, accuracy: 0.001)

        // The rows' layout pass places the pills again while they slide.
        controller.table.needsLayout = true
        controller.table.layoutSubtreeIfNeeded()
        XCTAssertNotNil(layer.animation(forKey: "position"), "a layout pass snapped the pill to its row")
    }
}
