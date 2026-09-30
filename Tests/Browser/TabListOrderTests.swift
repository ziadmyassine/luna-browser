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

    /// §4's top bar is read left to right, so there a new tab opens at the
    /// right-hand end, beside the tabs already open.
    func testUnderTheTopBarATabOpensAtTheEnd() {
        var list = TabList()
        list.addSpace(space)
        for index in 0 ..< 3 { open(&list, "old-\(index)", newestFirst: false) }

        open(&list, "newest", newestFirst: false)

        XCTAssertEqual(
            list[space].filter { $0.kind == .today }.map(\.url.lastPathComponent),
            ["old-0", "old-1", "old-2", "newest"]
        )
        XCTAssertNil(TabList.openIndex(for: .today, newestFirst: false))
    }

    /// A tab opened from a page goes right above it, and several open in
    /// the order they were asked for, the first highest.
    func testATabOpenedFromAPageSitsAboveIt() {
        var list = TabList()
        list.addSpace(space)
        for index in 0 ..< 3 { open(&list, "old-\(index)") }
        let parent = list[space][1].id

        openChild(&list, "first", from: parent)
        openChild(&list, "second", from: parent)

        XCTAssertEqual(
            list[space].map(\.url.lastPathComponent), ["old-2", "first", "second", "old-1", "old-0"]
        )
    }

    /// Under the top bar the same tab opens to the right of its page.
    func testUnderTheTopBarATabOpenedFromAPageSitsToItsRight() {
        var list = TabList()
        list.addSpace(space)
        for index in 0 ..< 3 { open(&list, "old-\(index)", newestFirst: false) }
        let parent = list[space][1].id

        openChild(&list, "child", from: parent, newestFirst: false)

        XCTAssertEqual(list[space].map(\.url.lastPathComponent), ["old-0", "old-1", "child", "old-2"])
    }

    /// From a tab in a folder, the child joins the folder, above its page.
    func testATabOpenedFromAFolderJoinsIt() throws {
        var list = TabList()
        list.addSpace(space)
        open(&list, "loose")
        let folder = TabGroup(spaceID: space, name: "Folder", kind: .today)
        list.insertGroup(folder)
        for index in 0 ..< 2 {
            let tab = Tab(spaceID: space, url: URL(string: "https://example.com/in-\(index)")!, order: index, groupID: folder.id)
            list.insert(tab)
        }
        let parent = try XCTUnwrap(list[space].first { $0.url.lastPathComponent == "in-1" }).id

        openChild(&list, "child", from: parent)

        XCTAssertEqual(list.members(ofGroup: folder.id).map(\.url.lastPathComponent), ["in-0", "child", "in-1"])
    }

    /// A Favorite or a saved row cannot have one of today's tabs beside it,
    /// so a tab opened from one opens where any new tab does.
    func testATabOpenedFromASavedRowOpensAtTheTop() {
        var list = TabList()
        list.addSpace(space)
        open(&list, "saved", kind: .pinned)
        XCTAssertNil(list.openIndex(openedFrom: list[space][0].id))
    }

    private func openChild(_ list: inout TabList, _ path: String, from parent: UUID, newestFirst: Bool = true) {
        let beside = list.openIndex(openedFrom: parent, newestFirst: newestFirst)
        let tab = Tab(
            spaceID: space,
            url: URL(string: "https://example.com/\(path)")!,
            parentTabID: parent,
            order: list.nextOrder(kind: .today, in: space),
            groupID: beside?.groupID
        )
        list.insert(tab, at: beside?.index)
    }

    private func open(_ list: inout TabList, _ path: String, kind: TabKind = .today, newestFirst: Bool = true) {
        let tab = Tab(
            spaceID: space,
            kind: kind,
            url: URL(string: "https://example.com/\(path)")!,
            order: list.nextOrder(kind: kind, in: space)
        )
        list.insert(tab, at: TabList.openIndex(for: kind, newestFirst: newestFirst))
    }
}
