//
//  BrowserSessionAdoptionTests.swift
//  LunaTests
//
//  What a running session does about rows somebody else wrote to the store —
//  §23.2's importer during §30.17's first run, which is the only writer that
//  does this today.
//
//  The case that was missing is the ordinary one: an import reuses a Space
//  whenever it has imported from that browser before, or finds one already
//  carrying the name it would have used. Those bookmarks land in a Space the
//  session is already showing, and a sweep that only looked for *new* Spaces
//  left them invisible until the next launch.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionAdoptionTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-adoption-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A tab written into a Space the session already holds shows up.
    func testTabsWrittenIntoAKnownSpaceAreAdopted() async throws {
        let store = try makeStore()
        let session = try await BrowserSession.restored(store: store)
        let spaceID = try XCTUnwrap(session.spaces.first?.id)
        let arrival = Tab(spaceID: spaceID, kind: .pinned, url: url("imported"), title: "Imported")
        try await store.upsert(arrival)

        try await session.adoptSpacesWrittenElsewhere()

        XCTAssertNotNil(session.list.tab(arrival.id), "a tab written into an open Space stayed invisible")
    }

    /// And a whole Space still arrives with its tabs, which is the case that
    /// already worked and must go on working.
    func testAWholeSpaceStillArrivesWithItsTabs() async throws {
        let store = try makeStore()
        let session = try await BrowserSession.restored(store: store)
        let profileID = try XCTUnwrap(session.spaces.first?.profileID)
        let space = Space(name: "Dia — Main", symbolName: "square", gradient: .defaultSpace, profileID: profileID)
        try await store.upsert(space)
        let arrival = Tab(spaceID: space.id, kind: .pinned, url: url("elsewhere"), title: "Elsewhere")
        try await store.upsert(arrival)

        try await session.adoptSpacesWrittenElsewhere()

        XCTAssertTrue(session.spaces.contains { $0.id == space.id })
        XCTAssertNotNil(session.list.tab(arrival.id))
    }

    /// Nothing the session already holds is touched. The sweep runs while the
    /// browser is up, so a row it replaced would be a live web view torn down
    /// by a refresh it had nothing to do with.
    func testAdoptingTwiceChangesNothing() async throws {
        let store = try makeStore()
        let session = try await BrowserSession.restored(store: store)
        let spaceID = try XCTUnwrap(session.spaces.first?.id)
        try await store.upsert(Tab(spaceID: spaceID, kind: .pinned, url: url("once"), title: "Once"))

        try await session.adoptSpacesWrittenElsewhere()
        let after = session.list[spaceID].map(\.id)
        try await session.adoptSpacesWrittenElsewhere()

        XCTAssertEqual(session.list[spaceID].map(\.id), after, "the second sweep duplicated a row")
        XCTAssertEqual(session.spaces.count, 1)
    }

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna.sqlite"))
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
