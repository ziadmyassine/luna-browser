//
//  BrowserSessionPinningTests.swift
//  LunaTests
//
//  §3.3's tile, and the one distinction the rest of the §6 lifecycle does not
//  make: a pinned tab's page can go away for two different reasons, and the
//  tile has to come back differently depending on which one it was.
//
//    · Filed away — pinning a tab that is not on screen, or the §19.2 budget
//      reclaiming a cold one. The blob stays; clicking the tile lands where the
//      user left off.
//    · Closed — `⌘W` on the tile. The tab goes home to `pinnedURL`, the link it
//      was pinned at, with no back/forward history.
//
//  They end in the same visible state — no page, tile on screen — which is why
//  they were one call and looked right until you closed a tile and clicked it
//  again. That is what these assert.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionPinningTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The home link

    func testPinningRecordsTheLinkItWasPinnedAt() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))

        XCTAssertEqual(session.tab(id)?.pinnedURL, url("home"))
    }

    /// The tile is a place you keep, not a page you happened to leave open, so
    /// walking the site afterwards must not move where the tile goes back to.
    func testWalkingTheSiteDoesNotMoveTheTilesHome() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))
        var walked = try XCTUnwrap(session.tab(id))
        walked.url = url("home/deep/article")
        session.write(walked)

        XCTAssertEqual(session.tab(id)?.pinnedURL, url("home"))
    }

    func testUnpinningTakesTheHomeAway() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))
        session.unpinTab(id)

        XCTAssertEqual(session.tab(id)?.kind, .today)
        XCTAssertNil(session.tab(id)?.pinnedURL, "an ordinary tab's address is wherever it is")
    }

    // MARK: - The two ways a tile's page goes away

    /// `⌘W`. The tile stays — a pinned tab cannot be closed — and the tab goes
    /// home.
    func testClosingATileSendsItHomeAndDropsTheSession() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))
        var walked = try XCTUnwrap(session.tab(id))
        walked.url = url("home/deep/article")
        walked.interactionState = Data([1, 2, 3])
        session.write(walked)

        session.closeTab(id)

        let tab = try XCTUnwrap(session.tab(id), "closing a tile must not remove it")
        XCTAssertEqual(tab.kind, .essential)
        XCTAssertEqual(tab.url, url("home"))
        XCTAssertNil(tab.interactionState, "a closed page has no session left to come back to")
    }

    /// The other half, and the one that would be silently lost if both paths
    /// were the same call: a tile whose page merely went cold keeps everything.
    func testFilingATileAwayKeepsWhereYouLeftOff() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))
        var walked = try XCTUnwrap(session.tab(id))
        walked.url = url("home/deep/article")
        walked.interactionState = Data([1, 2, 3])
        session.write(walked)

        session.putPinnedTabAway(id, in: walked.spaceID)

        let tab = try XCTUnwrap(session.tab(id))
        XCTAssertEqual(tab.url, url("home/deep/article"))
        XCTAssertEqual(tab.interactionState, Data([1, 2, 3]))
    }

    /// A tile from before schema `v3` has no home, and the honest answer is the
    /// behaviour that was already there rather than an invented one.
    func testATileWithNoHomeIsFiledAwayRatherThanMoved() async throws {
        let session = try await makeSession()
        let id = try pinnedTab(in: session, at: url("home"))
        var legacy = try XCTUnwrap(session.tab(id))
        legacy.pinnedURL = nil
        legacy.url = url("home/deep/article")
        legacy.interactionState = Data([9])
        session.write(legacy)

        session.closeTab(id)

        let tab = try XCTUnwrap(session.tab(id))
        XCTAssertEqual(tab.kind, .essential)
        XCTAssertEqual(tab.url, url("home/deep/article"))
        XCTAssertEqual(tab.interactionState, Data([9]))
    }

    // MARK: - Helpers

    /// A tab pinned at `address`, with the grid's own selection rules applied —
    /// `pinTab` is the only route into §3.3 and the only thing that records a
    /// home, so nothing here shortcuts it.
    private func pinnedTab(in session: BrowserSession, at address: URL) throws -> UUID {
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: address, order: 0)
        session.persistAll(session.list.insert(tab))
        XCTAssertTrue(session.pinTab(tab.id))
        XCTAssertEqual(session.tab(tab.id)?.kind, .essential)
        return tab.id
    }

    private func makeSession() async throws -> BrowserSession {
        try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
