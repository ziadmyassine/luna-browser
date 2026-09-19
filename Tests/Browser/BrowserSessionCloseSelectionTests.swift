//
//  BrowserSessionCloseSelectionTests.swift
//  LunaTests
//
//  Where the selection lands when `⌘W` closes the tab you are looking at.
//
//  It used to be "the most recently used tab in the Space", which answers a
//  different question. §3.4 stacks today's tabs newest-first, so the recent one
//  is very often the row *above* — closing down a list walked it backwards —
//  and closing a run of tabs from the top threw the selection somewhere in the
//  middle, where the next `⌘W` closed a tab the user was not looking at.
//
//  The list's own order is the only thing the user can see, so these assert
//  against that: the row below, and the row above only when there is no below.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionCloseSelectionTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Close the tab at the top and the one under it takes over.
    func testClosingATabSelectsTheRowBelowIt() async throws {
        let session = try await makeSession()
        let rows = try seed(session, count: 3)
        session.activateTab(rows[0])

        session.closeTab(rows[0])

        XCTAssertEqual(session.activeTabID, rows[1], "the selection skipped the row under the one that closed")
    }

    /// And from the middle, so this cannot pass by accident on "the first tab".
    func testClosingFromTheMiddleAlsoGoesDown() async throws {
        let session = try await makeSession()
        let rows = try seed(session, count: 4)
        session.activateTab(rows[1])

        session.closeTab(rows[1])

        XCTAssertEqual(session.activeTabID, rows[2])
    }

    /// The last row has nothing under it, so it is the one place the selection
    /// goes up — anything else would leave the list with nothing selected.
    func testClosingTheLastRowFallsBackToTheOneAbove() async throws {
        let session = try await makeSession()
        let rows = try seed(session, count: 3)
        session.activateTab(rows[2])

        session.closeTab(rows[2])

        XCTAssertEqual(session.activeTabID, rows[1])
    }

    /// Closing a tab that is **not** the one showing must not move the
    /// selection at all — the row below it is the answer to a question nobody
    /// asked.
    func testClosingABackgroundTabLeavesTheSelectionAlone() async throws {
        let session = try await makeSession()
        let rows = try seed(session, count: 3)
        session.activateTab(rows[0])

        session.closeTab(rows[2])

        XCTAssertEqual(session.activeTabID, rows[0])
    }

    /// Walking `⌘W` down from the top closes the list in order. This is the one
    /// that failed before: with the recent tab as the answer, the second close
    /// took a tab from further down and the list came apart from both ends.
    func testClosingRepeatedlyWalksDownTheList() async throws {
        let session = try await makeSession()
        let rows = try seed(session, count: 4)
        session.activateTab(rows[0])

        var order: [UUID] = []
        for _ in 0 ..< 3 {
            let showing = try XCTUnwrap(session.activeTabID)
            order.append(showing)
            session.closeTab(showing)
        }

        XCTAssertEqual(order, Array(rows.prefix(3)))
        XCTAssertEqual(session.tabs.map(\.id), [rows[3]])
    }

    // MARK: - Helpers

    /// `count` today tabs, in list order top to bottom. They are inserted at
    /// the end of the section rather than through `newTab`, whose §3.4 rule is
    /// that a new tab goes to the *top* — which would return them reversed and
    /// make every expectation here read backwards.
    private func seed(_ session: BrowserSession, count: Int) throws -> [UUID] {
        let space = try XCTUnwrap(session.spaces.first)
        let tabs = (0 ..< count).map {
            Tab(spaceID: space.id, kind: .today, url: url("page-\($0)"), order: $0)
        }
        for tab in tabs { session.persistAll(session.list.insert(tab)) }
        XCTAssertEqual(session.tabs.map(\.id), tabs.map(\.id), "the seed is not in the order the list shows")
        return tabs.map(\.id)
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
