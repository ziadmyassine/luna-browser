//
//  BrowserSessionSpacesTests.swift
//  LunaTests
//
//  The Space lifecycle (spec §6) and the per-Profile Favorites tier (§2).
//
//  These cover behaviour that is invisible when it breaks and expensive
//  when it does:
//
//  · Two Spaces on one Profile must resolve to the **same** `WKWebsiteDataStore`
//    — the whole point of many-Spaces-to-one-Profile, and unreachable from the
//    app until `createSpace(name:profileID:)` existed.
//  · `setProfile` must rebuild every web view. A `WKWebView`'s data store is
//    fixed at construction, so a Space that changes Profile without a rebuild
//    keeps writing the old Profile's cookies — Nook ships exactly that bug, and
//    it is silent.
//  · Deleting a Space must not destroy a tab, and must be undoable.
//
//  The per-Profile Favorites tier has its own file next door.
//
//  Two of them build real `WKWebsiteDataStore`s, because store *identity* is
//  the assertion. They are the only slow tests in the file.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionSpacesTests: XCTestCase {

    /// One per test method — XCTest builds a fresh instance for each — and
    /// `async` so the overrides stay on the main actor with the rest of the
    /// class. `setUpWithError` is nonisolated, and reaching main-actor state
    /// from it is a concurrency warning, not a convenience.
    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Goal 6 · rename, reorder, icon, gradient

    func testRenameSetIconAndSetGradientPersist() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let id = try XCTUnwrap(session.spaces.first?.id)
        let gradient = GradientPair(
            start: RGBA(r: 1, g: 0, b: 0, a: 1),
            end: RGBA(r: 0, g: 0, b: 1, a: 1)
        )

        try await session.renameSpace(id, to: "  Work  ")
        try await session.setIcon("briefcase.fill", forSpace: id)
        try await session.setGradient(gradient, forSpace: id)

        XCTAssertEqual(session.space(id)?.name, "Work", "the name is trimmed, not stored with its whitespace")
        XCTAssertEqual(session.space(id)?.symbolName, "briefcase.fill")
        XCTAssertEqual(session.space(id)?.gradient, gradient)

        let persisted = try await store.spaces().first { $0.id == id }
        XCTAssertEqual(persisted?.name, "Work", "…and it survives a relaunch")
        XCTAssertEqual(persisted?.symbolName, "briefcase.fill")
        XCTAssertEqual(persisted?.gradient, gradient)
    }

    func testRenameRefusesAnEmptyName() async throws {
        let session = try await makeSession(try makeStore())
        let id = try XCTUnwrap(session.spaces.first?.id)
        let before = session.space(id)?.name

        do {
            try await session.renameSpace(id, to: "   ")
            XCTFail("a Space with no name is an unclickable dot in the strip")
        } catch {
            XCTAssertEqual(session.space(id)?.name, before)
        }
    }

    func testReorderSpaceRenumbersEveryoneAndPersists() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let first = try XCTUnwrap(session.spaces.first?.id)
        let second = try await session.createSpace(name: "Two").id
        let third = try await session.createSpace(name: "Three").id

        try await session.reorderSpace(third, to: 0)

        XCTAssertEqual(session.spaces.map(\.id), [third, first, second])
        XCTAssertEqual(session.spaces.map(\.order), [0, 1, 2], "order is dense after a move, not sparse")
        let persisted = try await store.spaces()
        XCTAssertEqual(persisted.map(\.id), [third, first, second], "…on disk as well as on screen")
        XCTAssertEqual(persisted.map(\.order), [0, 1, 2])
    }

    // MARK: - Goal 7 · many Spaces, one Profile

    /// The proof that many-to-one is real: not that the field matches, but that
    /// WebKit hands back the *same object*, so the two Spaces genuinely share a
    /// cookie jar.
    func testTwoSpacesOnOneProfileShareOneDataStore() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let joined = try await session.createSpace(name: "Work Admin", profileID: home.profileID)
        let separate = try await session.createSpace(name: "Personal Two")

        XCTAssertEqual(joined.profileID, home.profileID)
        XCTAssertTrue(
            session.dataStore(forSpace: home.id) === session.dataStore(forSpace: joined.id),
            "two Spaces naming one Profile must resolve to one WKWebsiteDataStore"
        )
        XCTAssertFalse(
            session.dataStore(forSpace: home.id) === session.dataStore(forSpace: separate.id),
            "…and a Space on its own Profile must not"
        )
        XCTAssertEqual(
            Set(session.spaces(onProfile: home.profileID).map(\.id)),
            [home.id, joined.id],
            "the fan-out C's Settings label reads"
        )
        await removeStores(in: session)
    }

    func testCreateSpaceRefusesAProfileThatDoesNotExist() async throws {
        let session = try await makeSession(try makeStore())
        do {
            _ = try await session.createSpace(name: "Nowhere", profileID: UUID())
            XCTFail("a Space pointing at no Profile has no cookie jar to open")
        } catch {
            XCTAssertEqual(session.spaces.count, 1)
        }
    }

    // MARK: - Goal 8 · setProfile rebuilds every web view

    /// Nook sets the field, persists, and stops. Every already-loaded tab then
    /// keeps reading and writing the old cookie jar until something unloads it,
    /// and zen#15023's only user feedback is a greyed-out menu item. The
    /// assertion is object identity, because a `WKWebView`'s data store cannot
    /// be changed after construction: a controller that survived the switch is
    /// a controller still holding the old store.
    func testSetProfileDiscardsAndRecreatesEveryController() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let home = try XCTUnwrap(session.spaces.first)
        // A second Space on the same Profile, so the old Profile is not deleted
        // out from under the test when the first one leaves it.
        _ = try await session.createSpace(name: "Sibling", profileID: home.profileID)
        let target = try await session.createSpace(name: "Other")
        session.switchSpace(home.id)

        let warm = Tab(spaceID: home.id, kind: .today, url: url("warm"), order: 0)
        let cold = Tab(spaceID: home.id, kind: .today, url: url("cold"), order: 1)
        session.persistAll(session.list.insert(warm))
        session.persistAll(session.list.insert(cold))
        session.activateTab(warm.id)
        _ = session.ensureController(for: cold)

        let warmBefore = try XCTUnwrap(session.controller(for: warm.id))
        let coldBefore = try XCTUnwrap(session.controller(for: cold.id))
        let storeBefore = session.dataStore(forSpace: home.id)

        try await session.setProfile(target.profileID, forSpace: home.id)

        XCTAssertEqual(session.space(home.id)?.profileID, target.profileID)
        XCTAssertFalse(
            session.dataStore(forSpace: home.id) === storeBefore,
            "the Space must resolve to the new Profile's store"
        )
        let warmAfter = try XCTUnwrap(session.controller(for: warm.id), "a live tab comes back live")
        XCTAssertFalse(warmBefore === warmAfter, "the loaded tab's web view was rebuilt, not reused")
        let coldAfter = try XCTUnwrap(session.controller(for: cold.id), "a cold controller holds the store too")
        XCTAssertFalse(coldBefore === coldAfter)
        XCTAssertEqual(session.activeTabID, warm.id, "the selection survives the rebuild")
        // Deliberately not `removeStores`: these stores had live web views, so
        // WebKit refuses the removal and A's retry loop spends eight seconds per
        // profile backing off before queueing it — sixteen seconds of a test
        // suite to prove nothing this test is about. They are orphans the moment
        // this database is deleted, and `ProfileStore.sweepOrphans` is what
        // exists to collect them at the next launch.
        session.tearDown()
    }

    // MARK: - Goal 9 · deleting a Space never destroys tabs

    func testDeleteSpaceArchivesItsTabsAndUndoRestoresThem() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let home = try XCTUnwrap(session.spaces.first)
        let doomed = try await session.createSpace(name: "Doomed")
        let tab = Tab(spaceID: doomed.id, kind: .today, url: url("keep-me"), order: 0)
        session.persistAll(session.list.insert(tab))
        session.switchSpace(home.id)

        try await session.deleteSpace(doomed.id, policy: .archiveTabs)

        XCTAssertNil(session.space(doomed.id))
        XCTAssertEqual(session.archived.map(\.id), [tab.id], "the tab is archived, not destroyed")
        XCTAssertNotEqual(
            session.archived.first?.spaceID,
            doomed.id,
            "and re-homed, or the cascade would take its row with the Space"
        )
        await session.persist()
        let rows = try await store.tabs(inSpace: try XCTUnwrap(session.archived.first?.spaceID), includeArchived: true)
        XCTAssertTrue(rows.contains { $0.id == tab.id }, "…so ⌘⇧T still works after a relaunch")

        XCTAssertTrue(session.undoManager.canUndo)
        session.undoManager.undo()
        try await waitUntil("the Space comes back") { session.space(doomed.id) != nil }
        XCTAssertEqual(session.list[doomed.id].map(\.id), [tab.id], "and so does its tab, open")
        XCTAssertTrue(session.archived.isEmpty)
    }

    func testDeleteSpaceCanAdoptItsTabsIntoAnotherSpace() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let doomed = try await session.createSpace(name: "Doomed", profileID: home.profileID)
        let tab = Tab(spaceID: doomed.id, kind: .today, url: url("adopt-me"), order: 0)
        session.persistAll(session.list.insert(tab))
        session.switchSpace(home.id)

        try await session.deleteSpace(doomed.id, policy: .adopt(into: home.id))

        XCTAssertNil(session.space(doomed.id))
        XCTAssertTrue(session.archived.isEmpty, "adoption keeps the tab open, it does not archive it")
        XCTAssertEqual(session.tab(tab.id)?.spaceID, home.id)
        XCTAssertEqual(session.tabs.map(\.id), [tab.id])
    }

    func testDeletingTheLastSpaceIsRefused() async throws {
        let session = try await makeSession(try makeStore())
        let only = try XCTUnwrap(session.spaces.first?.id)
        do {
            try await session.deleteSpace(only, policy: .archiveTabs)
            XCTFail("a window with no Space has nothing to show")
        } catch {
            XCTAssertEqual(session.spaces.count, 1)
        }
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

    /// The undo for a Space deletion is asynchronous — `UndoManager`'s callback
    /// is synchronous and restoring rows is not — so the test waits for the
    /// result instead of assuming the next line runs after it.
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Tests that build real `WKWebsiteDataStore`s clean them off the disk
    /// afterwards; a test run must not leave cookie jars in
    /// `~/Library/WebKit/WebsiteDataStore/`.
    private func removeStores(in session: BrowserSession) async {
        // Release the web views first. `remove(forIdentifier:)` fails while one
        // is still live, and its retry loop then backs off for eight seconds
        // before giving up and queueing the identifier — which is correct in
        // the app and pure waiting in a test.
        session.tearDown()
        for profile in session.profiles.values {
            try? await session.profileStore.remove(profile)
        }
    }
}
