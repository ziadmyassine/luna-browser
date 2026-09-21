//
//  TabListOrderTests.swift
//  LunaTests
//
//  Where a tab that is opening now lands — `TabList.openIndex(for:)`.
//
//  It is one line of arithmetic and it decides the first thing the user sees
//  after `⌘T`, which is exactly the shape of rule that gets changed back by
//  accident. `TabList` is pure, so this needs no window, no store and no web
//  view.
//

import BrowserKit
import XCTest
@testable import Luna

final class TabListOrderTests: XCTestCase {

    private let space = UUID()

    /// The list is read from the top, so that is where a new tab goes.
    func testATabOpenedNowIsTheFirstOfTodays() {
        var list = TabList()
        list.addSpace(space)
        for index in 0 ..< 3 { open(&list, "old-\(index)") }

        open(&list, "newest")

        XCTAssertEqual(
            list[space].filter { $0.kind == .today }.map(\.url.lastPathComponent),
            ["newest", "old-2", "old-1", "old-0"],
            "newest first, and every earlier tab keeps its relative order"
        )
    }

    /// `order` is what a relaunch reads the list back in, so it has to agree
    /// with the arrangement and not merely with the array.
    func testTheStoredOrderMatchesWhatIsOnScreen() {
        var list = TabList()
        list.addSpace(space)
        open(&list, "first")
        open(&list, "second")

        let todays = list[space].filter { $0.kind == .today }
        XCTAssertEqual(todays.map(\.order), [0, 1])
        XCTAssertEqual(todays.first?.url.lastPathComponent, "second")
    }

    /// A pinned tab is a slot the user placed. A new one joins the end rather
    /// than pushing the arrangement they made down a row.
    func testAPinnedTabStillJoinsTheEnd() {
        var list = TabList()
        list.addSpace(space)
        open(&list, "pin-one", kind: .pinned)
        open(&list, "pin-two", kind: .pinned)

        XCTAssertEqual(
            list[space].filter { $0.kind == .pinned }.map(\.url.lastPathComponent),
            ["pin-one", "pin-two"]
        )
    }

    /// Exactly the rule the two callers ask for, stated once.
    func testOnlyTodaysTabsStackNewestFirst() {
        XCTAssertEqual(TabList.openIndex(for: .today), 0)
        XCTAssertNil(TabList.openIndex(for: .pinned))
        XCTAssertNil(TabList.openIndex(for: .essential))
    }

    private func open(_ list: inout TabList, _ path: String, kind: TabKind = .today) {
        let tab = Tab(
            spaceID: space,
            kind: kind,
            url: URL(string: "https://example.com/\(path)")!,
            order: list.nextOrder(kind: kind, in: space)
        )
        list.insert(tab, at: TabList.openIndex(for: kind))
    }
}
