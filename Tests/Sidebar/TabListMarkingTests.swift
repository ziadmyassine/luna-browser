//
//  TabListMarkingTests.swift
//  LunaTests
//
//  ⌘- and ⇧-click marking in §3.4's list (`TabListController+Marking.swift`):
//  marking starts from the selected tab and keeps it, each marked tab but that
//  one wears a pill of its own, and leaving for an unmarked tab lets them go.
//  Nothing is put on screen.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TabListMarkingTests: XCTestCase {

    private let space = UUID()
    private lazy var tabs = (0 ..< 5).map { index in
        Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(index)")!,
            title: "Tab \(index)", order: index)
    }

    private func controller(active: Int = 1) -> TabListController {
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 500)
        controller.show(saved: [], today: tabs.map(SidebarSlot.tab), essentials: [], activeTabID: tabs[active].id)
        controller.table.layoutSubtreeIfNeeded()
        return controller
    }

    private func click(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    func testCommandClickMarksFromTheSelectedTab() throws {
        let list = controller()
        XCTAssertTrue(list.mark(tabs[3].id, for: try click(.command)))

        XCTAssertEqual(list.markedInOrder, [tabs[1].id, tabs[3].id])
        XCTAssertEqual(Set(list.markPills.keys), [tabs[3].id], "the selected tab already has its pill")

        // The selected tab stays marked; another click on the other lets it go,
        // and one marked tab is no marking at all.
        _ = list.mark(tabs[1].id, for: try click(.command))
        XCTAssertEqual(list.markedInOrder, [tabs[1].id, tabs[3].id])
        _ = list.mark(tabs[3].id, for: try click(.command))
        XCTAssertTrue(list.markedTabIDs.isEmpty)
    }

    func testShiftClickMarksTheRun() throws {
        let list = controller()
        _ = list.mark(tabs[4].id, for: try click(.shift))
        XCTAssertEqual(list.markedInOrder, tabs[1 ... 4].map(\.id))
        XCTAssertFalse(list.mark(tabs[0].id, for: try click([])), "a plain press is the list's own")
    }

    func testGoingToAnUnmarkedTabLetsTheMarksGo() throws {
        let list = controller()
        _ = list.mark(tabs[2].id, for: try click(.command))
        list.show(saved: [], today: tabs.map(SidebarSlot.tab), essentials: [], activeTabID: tabs[2].id)
        XCTAssertEqual(list.markedTabIDs.count, 2, "a marked tab is still among them")

        list.show(saved: [], today: tabs.map(SidebarSlot.tab), essentials: [], activeTabID: tabs[4].id)
        XCTAssertTrue(list.markedTabIDs.isEmpty)
    }
}
