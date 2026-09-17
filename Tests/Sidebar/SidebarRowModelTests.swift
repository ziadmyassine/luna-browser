//
//  SidebarRowModelTests.swift
//  LunaTests
//
//  `SidebarList` is where §3.4's row order and §6.6's drop maths live. Both are
//  pure, and both are the kind of off-by-one that is invisible until a user
//  drags a tab to the wrong section — so they are asserted here rather than
//  eyeballed in a running window.
//

import BrowserKit
import XCTest
@testable import Luna

final class SidebarRowModelTests: XCTestCase {

    private let space = UUID()

    private func tab(_ kind: TabKind, _ name: String) -> Tab {
        Tab(spaceID: space, kind: kind, url: URL(string: "https://\(name).example")!, title: name)
    }

    /// `Archive` → separator → `+ Add Tab` → tabs, Essentials excluded. The
    /// rule sits **between** the commands, which is what the reference shows —
    /// §3.4's prose puts it after both.
    func testRowOrder() {
        let essential = tab(.essential, "e")
        let pinned = tab(.pinned, "p")
        let today = tab(.today, "t")
        let list = SidebarList(tabs: [today, essential, pinned])

        XCTAssertEqual(list.rows, [.archive, .separator, .addTab, .tab(pinned.id), .tab(today.id)])
        XCTAssertEqual(list.essentials, [essential])
        XCTAssertEqual(list.listed.map(\.id), [pinned.id, today.id])
    }

    func testRowLookup() {
        let pinned = tab(.pinned, "p")
        let list = SidebarList(tabs: [pinned])

        XCTAssertEqual(list.row(of: pinned.id), 3)
        XCTAssertEqual(list.tab(at: 3), pinned)
        XCTAssertNil(list.tab(at: 0))
        XCTAssertNil(list.tab(at: 99))
        XCTAssertNil(list[99])
    }

    /// The separator is furniture: the keyboard must not be able to land on it.
    func testSeparatorIsNotSelectable() {
        let list = SidebarList(tabs: [tab(.today, "t")])

        XCTAssertTrue(list.isSelectable(0))
        XCTAssertFalse(list.isSelectable(1))
        XCTAssertTrue(list.isSelectable(2))
        XCTAssertTrue(list.isSelectable(3))
        XCTAssertFalse(list.isSelectable(4))
    }

    /// §6.6: the row index a drop landed on maps to a section plus an index
    /// *within* that section, which is what `reorderTab` takes.
    func testDropTargets() {
        let list = SidebarList(tabs: [tab(.pinned, "p1"), tab(.pinned, "p2"), tab(.today, "t1")])

        XCTAssertEqual(list.dropTarget(insertingAt: 3).kind, .pinned)
        XCTAssertEqual(list.dropTarget(insertingAt: 3).index, 0)
        XCTAssertEqual(list.dropTarget(insertingAt: 4).index, 1)
        XCTAssertEqual(list.dropTarget(insertingAt: 5).kind, .today)
        XCTAssertEqual(list.dropTarget(insertingAt: 5).index, 0)
        XCTAssertEqual(list.dropTarget(insertingAt: 6).index, 1)
        // Never inside the leading command group.
        XCTAssertEqual(list.dropTarget(insertingAt: 0).kind, .pinned)
        XCTAssertEqual(list.dropTarget(insertingAt: 0).index, 0)
    }

    /// With no pinned section there is no pinned row to sit above, so the top
    /// of the list is the top of today's tabs.
    func testDropAtTopWithoutPinnedSectionIsToday() {
        let list = SidebarList(tabs: [tab(.today, "t1")])

        XCTAssertEqual(list.dropTarget(insertingAt: 3).kind, .today)
        XCTAssertEqual(list.dropTarget(insertingAt: 3).index, 0)
    }

    /// AppKit reports the row under the pointer; a drop belongs in the gap
    /// below it once the pointer is past the midpoint.
    func testInsertionRowClampsToTheFirstTab() {
        XCTAssertEqual(SidebarList.insertionRow(forRow: 0, isBelowMidpoint: false), 3)
        XCTAssertEqual(SidebarList.insertionRow(forRow: 4, isBelowMidpoint: false), 4)
        XCTAssertEqual(SidebarList.insertionRow(forRow: 4, isBelowMidpoint: true), 5)
    }
}
