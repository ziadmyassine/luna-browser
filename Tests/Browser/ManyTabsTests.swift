//
//  ManyTabsTests.swift
//  LunaTests
//
//  Several marked tabs moved at once (`BrowserSession+ManyTabs.swift`): they
//  land side by side in their own order wherever they came from, into a folder
//  or the folder tier as one, and one ⌘Z puts them all back.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class ManyTabsTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-many-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func todaySlots(_ session: BrowserSession) -> [UUID] {
        session.list.slots(inSpace: session.activeSpaceID, kind: .today).map(\.id)
    }

    /// Two tabs from either side of the landing go in together, in the order
    /// given — the list gives them in row order.
    func testMarkedTabsLandSideBySide() async throws {
        let session = try await makeSession()
        for name in ["a", "b", "c", "d", "e"] { session.newTab(url: url(name)) }
        let start = todaySlots(session)

        // Among the three that stay, before the last of them.
        session.moveTabs([start[0], start[3]], to: SidebarDestination(kind: .today, groupID: nil, index: 2))

        XCTAssertEqual(todaySlots(session), [start[1], start[2], start[0], start[3], start[4]])
    }

    func testMarkedTabsGoIntoAFolderAtItsEnd() async throws {
        let session = try await makeSession()
        let first = session.newTab(url: url("a"))
        let second = session.newTab(url: url("b"))
        let third = session.newTab(url: url("c"))
        let folder = try XCTUnwrap(session.createGroup(name: "Work", containing: [first]))

        session.moveTabs([third, second], toGroup: folder)

        XCTAssertEqual(session.members(ofGroup: folder).map(\.id), [first, third, second])
    }

    /// The folder tier holds folders, so tabs dropped loose there are one new
    /// folder holding all of them.
    func testMarkedTabsDroppedInTheFolderTierMakeOneFolder() async throws {
        let session = try await makeSession()
        let first = session.newTab(url: url("a"))
        let second = session.newTab(url: url("b"))

        session.moveTabs([second, first], to: SidebarDestination(kind: .pinned, groupID: nil, index: 0))

        let folder = try XCTUnwrap(session.tab(first)?.groupID)
        XCTAssertEqual(session.members(ofGroup: folder).map(\.id), [second, first])
        XCTAssertEqual(session.group(folder)?.kind, .pinned)
    }

    func testOneUndoPutsThemAllBack() async throws {
        let session = try await makeSession()
        for name in ["a", "b", "c", "d"] { session.newTab(url: url(name)) }
        let start = todaySlots(session)
        session.undoManager.removeAllActions()

        session.moveTabs([start[0], start[1]], to: SidebarDestination(kind: .today, groupID: nil, index: 2))
        XCTAssertNotEqual(todaySlots(session), start)

        session.undoManager.undo()
        XCTAssertEqual(todaySlots(session), start)
    }

    // MARK: - Close Other Tabs, Close Tabs Below

    /// `closableTabs`' rule: the day's tabs go, in a folder or not; a tile and
    /// a saved row stay.
    func testCloseOtherTabsKeepsTilesAndSavedRows() async throws {
        let session = try await makeSession()
        let tile = session.newTab(url: url("tile"))
        XCTAssertTrue(session.pinTab(tile))
        let saved = session.newTab(url: url("saved"))
        XCTAssertNotNil(session.createGroup(name: "Kept", kind: .pinned, containing: [saved]))
        let kept = session.newTab(url: url("kept"))
        let loose = session.newTab(url: url("loose"))
        let grouped = session.newTab(url: url("grouped"))
        XCTAssertNotNil(session.createGroup(name: "Today", containing: [grouped]))
        XCTAssertEqual(session.tab(saved)?.kind, .pinned)

        session.closeOtherTabs(than: [kept])

        for id in [tile, saved, kept] { XCTAssertNotNil(session.tab(id)) }
        for id in [loose, grouped] { XCTAssertNil(session.tab(id)) }
    }

    func testCloseOtherTabsKeepsEveryMarkedTab() async throws {
        let session = try await makeSession()
        for name in ["a", "b", "c", "d"] { session.newTab(url: url(name)) }
        let start = todaySlots(session)

        session.closeOtherTabs(than: [start[0], start[2]])

        XCTAssertEqual(todaySlots(session), [start[0], start[2]])
    }

    /// Below the last of the tabs, a folder's tabs included; the ones above stay.
    func testCloseTabsBelowClosesTheDaysTabsUnderTheLastOne() async throws {
        let session = try await makeSession()
        for name in ["a", "b", "c", "d", "e"] { session.newTab(url: url(name)) }
        let start = todaySlots(session)
        XCTAssertNotNil(session.createGroup(name: "Below", containing: [start[4]]))

        session.closeTabsBelow([start[0], start[2]])

        XCTAssertEqual(todaySlots(session), Array(start[0 ... 2]))
        XCTAssertNil(session.tab(start[4]))
    }

    /// The menu was opened on a tab to keep it, so that tab is the one on
    /// screen once the one that was there has gone.
    func testClosingAroundATabGoesToIt() async throws {
        let session = try await makeSession()
        let kept = session.newTab(url: url("kept"))
        session.newTab(url: url("shown"))

        session.closeOtherTabs(than: [kept])

        XCTAssertEqual(session.activeTabID, kept)
    }

    /// One ⌘Z brings them all back where they were, and each is on the
    /// shelf ⌘⇧T reopens from.
    func testOneUndoBringsBackEveryTabClosedAroundOne() async throws {
        let session = try await makeSession()
        for name in ["a", "b", "c", "d"] { session.newTab(url: url(name)) }
        let start = todaySlots(session)
        session.undoManager.removeAllActions()

        session.closeTabsBelow([start[1]])
        XCTAssertEqual(Set(session.archivedInActiveSpace.map(\.id)), Set(start[2...]))

        session.undoManager.undo()
        XCTAssertEqual(todaySlots(session), start)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }
}
