//
//  DropMarkTests.swift
//  LunaTests
//
//  §6.6's mark for a file or a link dragged over the window: where it shows,
//  that it answers with the place the page will open, and that the page then
//  opens there.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class DropMarkTests: XCTestCase {

    private var directory: URL!
    private let space = UUID()

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-dropmark-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The column

    /// Off the rows, the mark stands where a new tab opens — the head of
    /// today's tabs — and says so by answering nil.
    func testOffTheRowsTheMarkStandsWhereANewTabOpens() throws {
        let controller = try list()
        XCTAssertNil(controller.markDrop(atY: nil, in: controller.table))
        let mark = controller.gapPillRect(forGapRow: try XCTUnwrap(controller.gapRow), inside: nil, in: controller.table)
        XCTAssertEqual(mark.minY, controller.pillBox(ofRow: try headRow(of: controller)).minY, accuracy: 0.51)
        XCTAssertFalse(controller.dropMark.isHidden, "nothing marks where it will open")
    }

    /// Over the rows it follows the pointer, and answers with that landing.
    func testOverTheRowsTheMarkFollowsThePointer() throws {
        let controller = try list()
        let third = try XCTUnwrap(controller.list.row(of: try XCTUnwrap(controller.list.listed[safe: 2]).id))
        let box = controller.table.rect(ofRow: third)
        let landing = try XCTUnwrap(controller.markDrop(atY: box.minY + 2, in: controller.table))
        XCTAssertEqual(landing, SidebarDestination(kind: .today, groupID: nil, index: 2))
        XCTAssertEqual(controller.gapRow, third)
    }

    /// Gone with the drag, and the list is a list again.
    func testTheMarkGoesWithTheDrag() throws {
        let controller = try list()
        controller.markDrop(atY: nil, in: controller.table)
        controller.clearDropMark()
        XCTAssertFalse(controller.isDragging)
        XCTAssertNil(controller.gapRow)
    }

    /// A lift's gap is the lift's: a file dragged in mid-lift draws nothing.
    func testALiftKeepsItsGap() throws {
        let controller = try list()
        controller.beginDrag(atRow: 2)
        controller.setGap(row: 3)
        XCTAssertNil(controller.markDrop(atY: nil, in: controller.table))
        XCTAssertEqual(controller.gapRow, 3)
        XCTAssertFalse(controller.isMarkingDrop)
    }

    // MARK: - The page opens there

    func testPagesDroppedOnTheMarkOpenThereInOrder() async throws {
        let session = try await session()
        let home = try XCTUnwrap(session.spaces.first).id
        for index in 0 ..< 3 {
            let tab = Tab(spaceID: home, kind: .today, url: URL(string: "https://example.com/\(index)")!, order: index)
            session.persistAll(session.list.insert(tab))
        }
        let before = session.tabs.filter { $0.kind == .today }.map(\.id)
        let pages = [URL(string: "https://a.example/")!, URL(string: "https://b.example/")!]

        let opened = session.openTabs(pages, at: SidebarDestination(kind: .today, groupID: nil, index: 2))

        let today = session.tabs.filter { $0.kind == .today }.map(\.id)
        XCTAssertEqual(today, Array(before.prefix(2)) + opened + before.dropFirst(2))
        XCTAssertFalse(session.undoManager.canUndo && session.undoManager.undoActionName == "Move Tab",
                       "opening a page there was filed as a move to undo")
    }

    /// Several pages let go of in the saved tier are one new folder.
    func testPagesDroppedInTheSavedTierAreOneFolder() async throws {
        let session = try await session()
        let pages = [URL(string: "https://a.example/")!, URL(string: "https://b.example/")!]

        let opened = session.openTabs(pages, at: SidebarDestination(kind: .pinned, groupID: nil, index: 0))

        let groups = Set(opened.compactMap { session.tab($0)?.groupID })
        XCTAssertEqual(groups.count, 1, "each page made its own folder")
        XCTAssertEqual(opened.compactMap { session.tab($0)?.kind }, [.pinned, .pinned])
    }

    // MARK: - The bar

    func testTheBarMarksTheEndOfTheRunOffIt() async throws {
        let session = try await session()
        let window = UUID()
        session.openWindow(window)
        let home = try XCTUnwrap(session.spaces.first).id
        for index in 0 ..< 2 {
            let tab = Tab(spaceID: home, kind: .today, url: URL(string: "https://example.com/\(index)")!, order: index)
            session.persistAll(session.list.insert(tab))
        }
        let strip = TopBarTabStrip(session: session, windowID: window)
        strip.frame = NSRect(x: 0, y: 0, width: 1400, height: Tokens.Metric.topBarHeight)
        strip.reload()
        strip.layoutSubtreeIfNeeded()

        XCTAssertNil(strip.markDrop(at: nil))
        XCTAssertFalse(strip.dropMark.isHidden)
        let last = try XCTUnwrap(strip.blockFrames.last)
        XCTAssertGreaterThanOrEqual(strip.dropMark.frame.minX, last.maxX - 0.5, "the mark is not at the end of the run")

        strip.clearDropMark()
        XCTAssertTrue(strip.dropMark.isHidden)
        XCTAssertNil(strip.dropGap)
    }

    // MARK: - Fixtures

    private func list() throws -> TabListController {
        let tabs = (0 ..< 4).map { index in
            Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/\(index)")!, title: "Tab \(index)", order: index)
        }
        let controller = TabListController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 400)
        controller.show(saved: [], today: tabs.map(SidebarSlot.tab), essentials: [], activeTabID: tabs[0].id)
        controller.table.layoutSubtreeIfNeeded()
        return controller
    }

    /// The row of the first of today's tabs.
    private func headRow(of controller: TabListController) throws -> Int {
        try XCTUnwrap(controller.list.row(of: try XCTUnwrap(controller.list.listed.first).id))
    }

    private func session() async throws -> BrowserSession {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        return try await BrowserSession.restored(store: store)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
