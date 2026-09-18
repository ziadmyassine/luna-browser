//
//  BrowserSessionFavoritesTests.swift
//  LunaTests
//
//  Favorites are per **Profile**, not per Space (spec §2, decision D-S2, and
//  the owner's locked wording: "per-profile favourites, but per-space pinned").
//
//  This is the biggest model change in the Spaces wave and the one with the
//  least prior art to lean on. Arc keys its Favorites container by profile — a
//  flat `topAppsContainerIDs` profile → container pair — and caps the tier at
//  twelve; Zen strips a tab's workspace id when it is promoted to Essential,
//  which lands near the same place from the other side. Luna's `TabList` was
//  keyed by Space with `.essential` inside it, so Favorites were per Space and
//  `TODO.md` §46 claimed they were global. Both were wrong.
//
//  The behaviour these assert, in one line each: two Spaces on one Profile see
//  the same tiles, a Space on another Profile does not, the cap is the
//  Profile's, and nothing — deleting a Space, moving a tab across a Profile
//  boundary — silently throws a tile away.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionFavoritesTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Goal 10 · Favorites are per Profile

    func testFavoritesAreSharedAcrossSpacesOnOneProfile() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let sibling = try await session.createSpace(name: "Sibling", profileID: home.profileID)
        let stranger = try await session.createSpace(name: "Stranger")
        session.switchSpace(home.id)

        let tab = Tab(spaceID: home.id, kind: .today, url: url("favourite"), order: 0)
        session.persistAll(session.list.insert(tab))
        XCTAssertTrue(session.pinTab(tab.id))

        XCTAssertEqual(session.favorites(onProfile: home.profileID).map(\.id), [tab.id])
        XCTAssertTrue(session.favorites(onProfile: stranger.profileID).isEmpty)

        session.switchSpace(sibling.id)
        XCTAssertEqual(
            session.tabs.filter { $0.kind == .essential }.map(\.id),
            [tab.id],
            "a Space sharing the Profile shows the same tile"
        )
        session.switchSpace(stranger.id)
        XCTAssertTrue(
            session.tabs.filter { $0.kind == .essential }.isEmpty,
            "a Space on another Profile does not — the tile's login is not in that cookie jar"
        )
    }

    /// Arc's cap, allowing zero. Refusing is the behaviour: evicting the oldest
    /// tile to make room would throw away a login the user put there.
    func testFavoritesAreCappedAtTwelvePerProfile() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let sibling = try await session.createSpace(name: "Sibling", profileID: home.profileID)
        session.switchSpace(home.id)

        // Split across both Spaces on the Profile: the cap is the Profile's.
        for index in 0..<BrowserSession.favoritesCap {
            let spaceID = index.isMultiple(of: 2) ? home.id : sibling.id
            let tab = Tab(spaceID: spaceID, kind: .today, url: url("fav-\(index)"), order: index)
            session.persistAll(session.list.insert(tab))
            XCTAssertTrue(session.pinTab(tab.id), "tile \(index) is within the cap")
        }
        let extra = Tab(spaceID: home.id, kind: .today, url: url("thirteen"), order: 99)
        session.persistAll(session.list.insert(extra))

        XCTAssertFalse(session.pinTab(extra.id), "the thirteenth is refused")
        XCTAssertEqual(session.favorites(onProfile: home.profileID).count, BrowserSession.favoritesCap)
        XCTAssertEqual(session.tab(extra.id)?.kind, .today, "and it is left exactly where it was")
        XCTAssertEqual(
            session.favorites(onProfile: home.profileID).map(\.order),
            Array(0..<BrowserSession.favoritesCap),
            "Favorites are numbered across the Profile, not restarted per Space"
        )
    }

    /// Favorites survive the Space they happened to be created in.
    func testDeletingASpaceKeepsTheProfilesFavorites() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let doomed = try await session.createSpace(name: "Doomed", profileID: home.profileID)
        let tab = Tab(spaceID: doomed.id, kind: .today, url: url("tile"), order: 0)
        session.persistAll(session.list.insert(tab))
        XCTAssertTrue(session.pinTab(tab.id))
        session.switchSpace(home.id)

        try await session.deleteSpace(doomed.id, policy: .archiveTabs)

        XCTAssertEqual(
            session.favorites(onProfile: home.profileID).map(\.id),
            [tab.id],
            "a tile is the Profile's; deleting the Space it was made in must not archive it"
        )
        XCTAssertEqual(session.tab(tab.id)?.spaceID, home.id)
        XCTAssertTrue(session.archived.isEmpty)
    }

    /// Crossing a Profile boundary demotes a tile rather than smuggling it into
    /// another cookie jar's tier — and the caller is told, in Arc's words.
    func testMovingAFavoriteAcrossProfilesDemotesItAndIsWarnedAbout() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let stranger = try await session.createSpace(name: "Stranger")
        session.switchSpace(home.id)
        let tab = Tab(spaceID: home.id, kind: .today, url: url("tile"), order: 0)
        session.persistAll(session.list.insert(tab))
        XCTAssertTrue(session.pinTab(tab.id))

        XCTAssertTrue(session.moveCrossesProfileBoundary(tab.id, toSpace: stranger.id))
        XCTAssertTrue(BrowserSession.crossProfileMoveWarning.contains("logged out"))
        session.moveTab(tab.id, toSpace: stranger.id)

        XCTAssertEqual(session.tab(tab.id)?.kind, .pinned)
        XCTAssertTrue(session.favorites(onProfile: home.profileID).isEmpty)
        XCTAssertTrue(session.favorites(onProfile: stranger.profileID).isEmpty)
        XCTAssertNil(session.controller(for: tab.id), "the web view dies at the boundary, so cookies cannot cross")
    }

    /// The `v2` migration has to be safe to meet twice — a re-opened database
    /// runs the migrator again, and a user who downgrades and upgrades meets it
    /// a third time.
    func testTheSchemaSurvivesBeingOpenedTwice() async throws {
        let path = directory.appending(path: "luna.sqlite")
        let first = try BrowserStore(path: path)
        let session = try await makeSession(first)
        let home = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: home.id, kind: .essential, url: url("tile"), order: 0)
        try await first.upsert(tab)

        let second = try BrowserStore(path: path)
        let reopened = try await BrowserSession.restored(store: second)
        XCTAssertEqual(reopened.favorites(onProfile: home.profileID).map(\.id), [tab.id])
    }

    // MARK: - Helpers

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna.sqlite"))
    }

    private func makeSession(_ store: BrowserStore) async throws -> BrowserSession {
        try await BrowserSession.restored(store: store)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
