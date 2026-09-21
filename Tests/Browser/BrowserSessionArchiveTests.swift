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

    // MARK: - Where it comes back

    /// A session holding one closed tab that had been filed in a §3.4b folder.
    private func sessionWithATabClosedOutOfAFolder(
        kind: TabKind
    ) async throws -> (session: BrowserSession, tab: UUID, group: UUID) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        let id = session.newTab(url: URL(string: "https://example.com/kept")!)
        let group = try XCTUnwrap(session.createGroup(name: "Reading", kind: kind, containing: [id]))
        XCTAssertEqual(session.tab(id)?.groupID, group)
        // A saved row takes two presses: the first ends the page and dims the
        // row, the second lets the row go. Either way the tab ends up archived.
        session.closeTab(id)
        if session.tab(id) != nil { session.closeTab(id) }
        XCTAssertNotNil(session.archived.first { $0.id == id }, "the tab never reached the archive")
        return (session, id, group)
    }

    /// The bar hands back a page, not the filing it was in. Searching for a
    /// site you closed out of a folder and being given the folder's own row
    /// back is the state you had just finished leaving — dimmed, two levels in,
    /// and one press from being let go.
    func testTheCommandBarBringsAClosedTabBackOutOfItsFolder() async throws {
        for kind in [TabKind.pinned, .today] {
            let (session, id, group) = try await sessionWithATabClosedOutOfAFolder(kind: kind)
            session.unarchiveTab(id, resumingSession: false)
            let tab = try XCTUnwrap(session.tab(id), "\(kind) lost the tab entirely")
            XCTAssertNil(tab.groupID, "\(kind): the bar put the tab back in the folder it came out of")
            XCTAssertEqual(tab.kind, .today, "\(kind): the tab came back saved rather than open")
            XCTAssertFalse(tab.isDormant, "\(kind): the tab came back already closed once")
            XCTAssertFalse(
                session.members(ofGroup: group).contains { $0.id == id },
                "\(kind): the folder is holding it again"
            )
        }
    }

    /// `⌘⇧T` is the other gesture and still means undo: it puts the tab back
    /// exactly where it was taken from, folder included.
    func testReopeningTheLastClosedTabPutsItBackInItsFolder() async throws {
        let (session, id, group) = try await sessionWithATabClosedOutOfAFolder(kind: .today)
        session.reopenLastArchived()
        XCTAssertEqual(session.tab(id)?.groupID, group, "undo did not put the tab back where it was")
    }
}
