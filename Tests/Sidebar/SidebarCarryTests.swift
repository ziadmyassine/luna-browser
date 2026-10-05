//
//  SidebarCarryTests.swift
//  LunaTests
//
//  What §6.6's lift takes out of the list while it is in the air: a folder's
//  tabs, so it cannot land among them, and the other marked tabs, so several
//  travel as one. Pure, like the rest of `SidebarList`.
//

import BrowserKit
import XCTest
@testable import Luna

final class SidebarCarryTests: XCTestCase {

    private let space = UUID()

    private func tab(_ name: String) -> Tab {
        Tab(spaceID: space, kind: .today, url: URL(string: "https://\(name).example")!, title: name)
    }

    func testACarriedFolderTravelsFolded() {
        let members = [tab("a"), tab("b")]
        let loose = tab("c")
        let folder = TabGroup(spaceID: space, name: "Work", kind: .today)
        let slots: [SidebarSlot] = [.group(folder, tabs: members), .tab(loose)]

        XCTAssertEqual(
            SidebarList(today: slots).rows,
            [.addTab, .group(folder.id), .tab(members[0].id), .tab(members[1].id), .groupEnd(folder.id), .tab(loose.id)]
        )
        XCTAssertEqual(
            SidebarList(today: slots, carrying: [folder.id]).rows,
            [.addTab, .group(folder.id), .tab(loose.id)],
            "its tabs are not there to be dropped among"
        )
    }

    /// A folded folder keeps the tab you are on showing; carried, it does not.
    func testACarriedFolderHidesTheTabItKeepsOut() {
        let member = tab("a")
        let folder = TabGroup(spaceID: space, name: "Work", kind: .today, isCollapsed: true)
        let slots: [SidebarSlot] = [.group(folder, tabs: [member])]

        XCTAssertTrue(SidebarList(today: slots, peeking: [member.id]).rows.contains(.tab(member.id)))
        XCTAssertFalse(SidebarList(today: slots, peeking: [member.id], carrying: [folder.id]).rows.contains(.tab(member.id)))
    }

    /// The other marked tabs leave, and the drop's index counts the run
    /// without them — the run they all land in.
    func testCarriedTabsLeaveAndTheIndexCountsWithoutThem() {
        let tabs = ["a", "b", "c", "d"].map(tab)
        let list = SidebarList(today: tabs.map(SidebarSlot.tab), carrying: [tabs[1].id])

        XCTAssertEqual(list.rows, [.addTab, .tab(tabs[0].id), .tab(tabs[2].id), .tab(tabs[3].id)])
        let row = try? XCTUnwrap(list.row(of: tabs[3].id))
        XCTAssertEqual(list.destination(forRow: row ?? 0, isBelowMidpoint: false).index, 2)
    }
}
