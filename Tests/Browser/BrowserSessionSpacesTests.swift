//
//  BrowserSessionSpacesTests.swift
//  LunaTests
//
//  The Space lifecycle (spec §6) and the per-Profile Favorites tier (§2).
//
//  These cover behaviour that is invisible when it breaks:
//
//  · Two Spaces on one Profile must resolve to the same `WKWebsiteDataStore`
//    — the whole point of many-Spaces-to-one-Profile, and unreachable from the
//    app until `createSpace(name:)` existed.
//  · `setProfile` must rebuild every web view. A `WKWebView`'s data store is
//    fixed at construction, so a Space that changes Profile without a rebuild
//    keeps writing the old Profile's cookies — Nook ships exactly that bug, and
//    it is silent.
//  · Deleting a Space must not destroy a tab, and must be undoable.
//
//  The per-Profile Favorites tier has its own file next door.
//
//  Two of them build real `WKWebsiteDataStore`s, because store identity is
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

    /// §6.2's cap, at the layer nothing gets past: a name arrives from an
    /// import or a paste as well as from a field, and only the field has a
    /// formatter on it.
    func testALongNameIsCappedRatherThanRefused() async throws {
        let store = try makeStore()
        let session = try await makeSession(store)
        let id = try XCTUnwrap(session.spaces.first?.id)
        let long = String(repeating: "a", count: BrowserSession.spaceNameCap * 3)

        try await session.renameSpace(id, to: long)
        XCTAssertEqual(session.space(id)?.name.count, BrowserSession.spaceNameCap)

        let made = try await session.createSpace(name: long)
        XCTAssertEqual(made.name.count, BrowserSession.spaceNameCap, "a new Space is capped the same way")

        let persisted = try await store.spaces().first { $0.id == id }
        XCTAssertEqual(persisted?.name.count, BrowserSession.spaceNameCap, "…and the short one is what is stored")
    }

    /// The cap counts what a reader sees, not what the encoder writes. A flag
    /// is one character and several code units, and a name cut by code unit
    /// ends in half an emoji.
    func testTheCapCountsCharactersRatherThanBytes() async throws {
        let session = try await makeSession(try makeStore())
        let id = try XCTUnwrap(session.spaces.first?.id)
        let flags = String(repeating: "🇩🇰", count: BrowserSession.spaceNameCap + 4)

        try await session.renameSpace(id, to: flags)
        let name = try XCTUnwrap(session.space(id)?.name)
        XCTAssertEqual(name.count, BrowserSession.spaceNameCap)
        XCTAssertTrue(name.hasSuffix("🇩🇰"), "the last flag was cut in half")
    }

    /// A name that is only long because of what is around it keeps all of
    /// itself: the trim happens first, so the cap is spent on the name.
    func testWhitespaceIsNotSpentAgainstTheCap() async throws {
        let session = try await makeSession(try makeStore())
        let id = try XCTUnwrap(session.spaces.first?.id)
        let padded = String(repeating: " ", count: 40) + "Work" + String(repeating: " ", count: 40)

        try await session.renameSpace(id, to: padded)
        XCTAssertEqual(session.space(id)?.name, "Work")
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

    /// §8.2, as the owner settled it: a new Space is neutral, and colour is
    /// something the user asks for.
    ///
    /// This test used to assert the opposite — three Spaces, three pairs off
    /// the palette — and that was the shipped behaviour for exactly as long as
    /// it took to see it: the sidebar changed colour on its own, on a window
    /// nobody had asked to look different, and the only way back was a menu
    /// there was no reason to open. `Tokens.Gradient.next(after:)` still hands
    /// out twelve distinct pairs and `SpaceGradientTests` still proves it; what
    /// changed is that nothing calls it until the user picks one.
    func testNewSpacesAreNeutralUntilTheUserPicksAColour() async throws {
        let session = try await makeSession(try makeStore())
        let made = try await [
            session.createSpace(name: "One"),
            session.createSpace(name: "Two"),
            session.createSpace(name: "Three")
        ]

        for space in made {
            XCTAssertTrue(
                Tokens.Gradient.isNeutral(space.gradient),
                "a Space nobody has coloured washes to nothing"
            )
            XCTAssertFalse(
                Tokens.Gradient.spacePalette.contains(space.gradient),
                "and it is not quietly holding one of the twelve"
            )
        }
    }

    /// The other half of the same decision: the twelve are still reachable, and
    /// `setGradient` is how a Space gets one.
    func testAUserChosenGradientSticks() async throws {
        let session = try await makeSession(try makeStore())
        let space = try await session.createSpace(name: "One")
        let chosen = Tokens.Gradient.spacePalette[4]

        try await session.setGradient(chosen, forSpace: space.id)

        XCTAssertEqual(session.spaces.first { $0.id == space.id }?.gradient, chosen)
    }

    // MARK: - Goal 7 · one Space, one cookie jar

    /// What `v7` replaced goals 7 and 8 with. It used to be provable that two
    /// Spaces sharing a Profile resolved to *one* `WKWebsiteDataStore`, and
    /// that re-pointing a Space rebuilt every web view in it so no loaded tab
    /// went on writing to the old jar. Nothing can share and nothing can be
    /// re-pointed now, so the property worth holding is the other one: no two
    /// Spaces ever resolve to the same store.
    func testEverySpaceResolvesToAStoreOfItsOwn() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let second = try await session.createSpace(name: "Work")
        let third = try await session.createSpace(name: "Personal Two")

        let stores = [home.id, second.id, third.id].map { ObjectIdentifier(session.dataStore(forSpace: $0)) }
        XCTAssertEqual(Set(stores).count, 3, "two Spaces resolved to one cookie jar")
        XCTAssertEqual(Set([home, second, third].map(\.dataStoreIdentifier)).count, 3)
        await removeStores(in: session)
    }

    /// The identifier is minted per Space and persisted, because WebKit will
    /// not hand the mapping back (§5.1).
    func testANewSpaceIsSignedOutOfEverything() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let fresh = try await session.createSpace(name: "Fresh")

        XCTAssertNotEqual(fresh.dataStoreIdentifier, home.dataStoreIdentifier)
        XCTAssertTrue(fresh.hasUsableDataStoreIdentifier)
        await removeStores(in: session)
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
        let doomed = try await session.createSpace(name: "Doomed")
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

    // MARK: - Goal 6 · walking between Spaces opens nothing

    /// Coming back to a Space the user had emptied must show it empty. Its
    /// rows are a §3.3 tile and a §3.4b row that has been closed once, and both
    /// are places rather than pages: the fallback used to take the newest row
    /// of any kind, so the walk itself loaded one.
    func testComingBackToAnEmptiedSpaceOpensNothing() async throws {
        let session = try await makeSession(try makeStore())
        let home = try XCTUnwrap(session.spaces.first)
        let other = try await session.createSpace(name: "Other")
        var kept = Tab(spaceID: other.id, kind: .pinned, url: url("kept"), order: 0)
        kept.isDormant = true
        session.persistAll(session.list.insert(Tab(
            spaceID: other.id,
            kind: .essential,
            url: url("tile"),
            order: 0
        )))
        session.persistAll(session.list.insert(kept))
        session.switchSpace(home.id)

        session.switchSpace(other.id)

        XCTAssertNil(session.activeTabID, "walking into a Space opened something in it")
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
        for space in session.spaces {
            try? await session.profileStore.remove(space)
        }
    }
}
