//
//  BrowserSessionArchiveTests.swift
//  LunaTests
//
//  §6.3's archive, and the difference between the two gestures that pull a tab
//  back out of it.
//
//  `⌘⇧T` and §11's list both mean "reopen the tab I closed", and a reopened tab
//  comes back where it was left — that is what `interactionState` is for. §9's
//  Command Bar means something else: its rows are places, and its archive rows
//  sit in the same list as history's, wearing the same favicon and the same
//  title. Choosing one and landing half way down the page is a session
//  resuming behind a gesture that never asked for one.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionArchiveTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A session holding one closed tab that was carrying a session blob.
    private func sessionWithAnArchivedTab() async throws -> (BrowserSession, UUID) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let spaces = try await store.spaces()
        let space = try XCTUnwrap(spaces.first)
        let tab = Tab(
            spaceID: space.id,
            kind: .today,
            url: URL(string: "about:blank")!,
            interactionState: Data("where the page was".utf8),
            order: 0
        )
        try await store.upsert(tab)
        let session = try await BrowserSession.restored(store: store)
        session.closeTab(tab.id)
        XCTAssertNotNil(session.archived.first { $0.id == tab.id }?.interactionState)
        return (session, tab.id)
    }

    /// `⌘⇧T`'s promise: the tab comes back where it was left.
    func testReopeningAClosedTabKeepsWhereItWas() async throws {
        let (session, id) = try await sessionWithAnArchivedTab()
        session.unarchiveTab(id)
        XCTAssertNotNil(session.tab(id)?.interactionState, "a reopened tab lost its session")
    }

    /// And §9's promise: the page starts at the top.
    func testOpeningAnArchivedTabFromTheCommandBarStartsAtTheTopOfThePage() async throws {
        let (session, id) = try await sessionWithAnArchivedTab()
        session.unarchiveTab(id, resumingSession: false)
        let tab = try XCTUnwrap(session.tab(id))
        XCTAssertNil(tab.interactionState, "the bar reopened a tab half way down the page")
        XCTAssertNil(tab.archivedAt, "it is an open tab again")
        XCTAssertEqual(session.activeTabID, id)
    }
}
