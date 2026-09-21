//
//  BrowserSessionTests.swift
//  LunaTests
//
//  The two things about the coordinator that are worth a test because they are
//  invisible when they break:
//
//  · §19.4 — a restored session holds no `TabController`, so it holds no
//    `WKWebView` and no WebContent process. A regression here costs 30 renderer
//    processes at launch and nothing on screen says so.
//  · The section/order invariant `reorderTab(_:to:kind:)` is defined against.
//
//  Neither test wakes a tab, so neither creates a web view — which is also how
//  they stay fast.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class BrowserSessionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna.sqlite"))
    }

    /// Quit with tabs across two Spaces, relaunch: order comes back and nothing
    /// is awake.
    func testRestoreBringsTabsBackFullyHibernated() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let spaces = try await store.spaces()
        let space = try XCTUnwrap(spaces.first)

        // Deliberately inserted out of order and out of section, so a session
        // that just echoes the database row order fails this.
        let today = Tab(spaceID: space.id, kind: .today, url: url("b"), order: 1)
        let pinned = Tab(spaceID: space.id, kind: .pinned, url: url("a"), order: 0)
        try await store.upsert(today)
        try await store.upsert(pinned)

        let session = try await BrowserSession.restored(store: store)

        XCTAssertEqual(session.tabs.map(\.id), [pinned.id, today.id], "pinned sorts above today")
        XCTAssertNil(session.activeTabID, "a restored session selects nothing (§19.4)")
        for tab in session.tabs {
            XCTAssertNil(session.controller(for: tab.id), "restored tabs must hold no web view")
        }
    }

    /// `reorderTab` takes a section-relative index and renumbers `order` so the
    /// next launch restores what the user sees now.
    func testReorderIsSectionRelativeAndPersists() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()
        let space = try XCTUnwrap(seeded.first)

        let first = Tab(spaceID: space.id, kind: .today, url: url("1"), order: 0)
        let second = Tab(spaceID: space.id, kind: .today, url: url("2"), order: 1)
        let anchor = Tab(spaceID: space.id, kind: .pinned, url: url("p"), order: 0)
        for tab in [first, second, anchor] { try await store.upsert(tab) }

        let session = try await BrowserSession.restored(store: store)
        session.reorderTab(second.id, to: 0, kind: .today)
        await session.persist()

        XCTAssertEqual(
            session.tabs.map(\.id),
            [anchor.id, second.id, first.id],
            "index 0 of `today` sits after the pinned section, not at the top of the list"
        )
        XCTAssertEqual(session.tab(second.id)?.order, 0)
        XCTAssertEqual(session.tab(first.id)?.order, 1)
        XCTAssertNil(session.controller(for: second.id), "reordering must not wake a tab")
    }

    /// `⌘W` archives (§6.3) and leaves something for `⌘Z` (§6.7).
    func testCloseArchivesAndIsUndoable() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()
        let space = try XCTUnwrap(seeded.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: url("gone"), order: 0)
        try await store.upsert(tab)

        let session = try await BrowserSession.restored(store: store)
        session.closeTab(tab.id)

        XCTAssertTrue(session.tabs.isEmpty)
        XCTAssertTrue(session.undoManager.canUndo, "closing a tab must be undoable")

        // Tab writes are queued, not awaited, so navigation never waits on the
        // disk (§11.5). `persist()` is the drain, and quit awaits it too.
        await session.persist()
        let live = try await store.tabs(inSpace: space.id, includeArchived: false)
        XCTAssertTrue(live.isEmpty, "an archived tab is out of the live list…")
        let all = try await store.tabs(inSpace: space.id, includeArchived: true)
        XCTAssertEqual(all.count, 1, "…but still on disk, recoverable")
        XCTAssertNotNil(all.first?.archivedAt)
    }

    /// §3.3: pinning moves the tab into the Essentials section and puts
    /// its page away. It used only to do the second half, so the row left the
    /// list, no tile appeared, and the command looked like it did nothing.
    func testPinningMovesTheTabIntoEssentials() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()
        let space = try XCTUnwrap(seeded.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: url("pin-me"), order: 0)
        try await store.upsert(tab)

        let session = try await BrowserSession.restored(store: store)
        session.pinTab(tab.id)

        XCTAssertEqual(session.tab(tab.id)?.kind, .essential, "a pinned tab is an Essential")
        XCTAssertEqual(
            session.tabs.filter { $0.kind == .essential }.map(\.id),
            [tab.id],
            "…and it is what the grid renders"
        )
        XCTAssertNil(session.controller(for: tab.id), "pinning puts the page away")

        await session.persist()
        let stored = try await store.tabs(inSpace: space.id, includeArchived: false)
        XCTAssertEqual(stored.first?.kind, .essential, "and it survives a relaunch as one")
    }

    /// §3.3: unpinning is the only way out of the grid, and it does not open
    /// the page.
    func testUnpinningReturnsTheTabToToday() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()
        let space = try XCTUnwrap(seeded.first)
        let tab = Tab(spaceID: space.id, kind: .essential, url: url("pinned"), order: 0)
        try await store.upsert(tab)

        let session = try await BrowserSession.restored(store: store)
        session.unpinTab(tab.id)

        XCTAssertEqual(session.tab(tab.id)?.kind, .today)
        XCTAssertNil(session.controller(for: tab.id), "unpinning is not opening")
    }

    /// A pinned tab cannot be closed, only unpinned (§3.3): `⌘W` on one puts
    /// the page away and leaves the tile.
    func testClosingAPinnedTabKeepsIt() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()
        let space = try XCTUnwrap(seeded.first)
        let tab = Tab(spaceID: space.id, kind: .essential, url: url("stays"), order: 0)
        try await store.upsert(tab)

        let session = try await BrowserSession.restored(store: store)
        session.closeTab(tab.id)

        XCTAssertEqual(session.tab(tab.id)?.kind, .essential, "the tile is the tab; it stays")
        XCTAssertTrue(session.archived.isEmpty)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
