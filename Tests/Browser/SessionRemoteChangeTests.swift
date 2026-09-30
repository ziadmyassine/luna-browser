//
//  SessionRemoteChangeTests.swift
//  LunaTests
//
//  Changes from other Macs applied to the running session (docs/plans/SYNC-PLAN.md S10):
//  the in-memory list follows, the store write queues behind this Mac's own, and
//  the §3 rules that only the session can apply hold.
//

@testable import BrowserKit
import GRDB
import WebKit
import XCTest
@testable import Luna

@MainActor
final class SessionRemoteChangeTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The list follows

    func testARemoteRenameReorderAndNewTabUpdateTheList() async throws {
        let (store, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let first = Tab(spaceID: home.id, url: url("first"), order: 0)
        let second = Tab(spaceID: home.id, url: url("second"), order: 1)
        session.persistAll(session.list.insert(first))
        session.persistAll(session.list.insert(second))
        await session.writeChain?.value

        var renamed = home
        renamed.name = "Elsewhere"
        var movedFirst = first, movedSecond = second
        movedFirst.order = 1
        movedSecond.order = 0
        let arrived = Tab(spaceID: home.id, url: url("arrived"), order: 2)
        try await session.applyRemote(SyncChangeSet(modifications: [
            record(renamed), record(movedFirst), record(movedSecond), record(arrived)
        ]))

        XCTAssertEqual(session.space(home.id)?.name, "Elsewhere")
        XCTAssertEqual(session.tabs.map(\.id), [second.id, first.id, arrived.id])
        let stored = try await store.tabs(inSpace: home.id, includeArchived: false)
        XCTAssertEqual(Set(stored.map(\.id)), [first.id, second.id, arrived.id])
    }

    /// Straight to the store, the remote row would land first and the stale write
    /// already queued on the chain would put the old row back over it.
    func testTheStoreWriteQueuesBehindAStaleLocalWrite() async throws {
        let (store, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: home.id, url: url("tab"), order: 0)
        session.persistAll(session.list.insert(tab))
        await session.writeChain?.value
        session.enqueue { store in
            try? await Task.sleep(for: .milliseconds(200))
            try? await store.upsert(tab)
        }

        var remote = tab
        remote.customTitle = "From the other Mac"
        try await session.applyRemote(SyncChangeSet(modifications: [record(remote)]))
        await session.writeChain?.value

        XCTAssertEqual(session.tab(tab.id)?.customTitle, "From the other Mac")
        let stored = try await store.tabs(inSpace: home.id, includeArchived: false).first { $0.id == tab.id }
        XCTAssertEqual(stored?.customTitle, "From the other Mac")
    }

    // MARK: - The rules only the session can apply

    func testALiveTabKeepsItsURLButTakesTheRest() async throws {
        let (store, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: home.id, url: URL(string: "about:blank")!, title: "Here", order: 0)
        session.persistAll(session.list.insert(tab))
        session.activateTab(tab.id)
        XCTAssertNotNil(session.controller(for: tab.id))

        var remote = tab
        remote.url = url("elsewhere")
        remote.title = "There"
        remote.customTitle = "Renamed there"
        try await session.applyRemote(SyncChangeSet(modifications: [record(remote)]))

        XCTAssertEqual(session.tab(tab.id)?.url, tab.url, "an incoming URL would navigate a page in use")
        XCTAssertEqual(session.tab(tab.id)?.title, "Here")
        XCTAssertEqual(session.tab(tab.id)?.customTitle, "Renamed there")
        XCTAssertNotNil(session.controller(for: tab.id))
        let stored = try await store.tabs(inSpace: home.id, includeArchived: false).first { $0.id == tab.id }
        XCTAssertEqual(stored?.url, tab.url)
        session.tearDown()
    }

    func testARemoteSpaceDeleteTearsDownWithoutUndo() async throws {
        let (_, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let doomed = try await session.createSpace(name: "Doomed")
        let tab = Tab(spaceID: doomed.id, url: url("inside"), order: 0)
        session.persistAll(session.list.insert(tab))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "a", .value: "b"]))
        await session.dataStore(forSpace: doomed.id).httpCookieStore.setCookie(cookie)
        let jars = SystemWebsiteDataStoreRegistry()
        let hadJar = await jars.identifiers().contains(doomed.dataStoreIdentifier)
        XCTAssertTrue(hadJar, "the Space has a jar on disk to lose")
        session.undoManager.removeAllActions()

        try await session.applyRemote(SyncChangeSet(deletions: [
            SyncDeletion(recordType: "Space", recordName: doomed.id.uuidString, zone: SyncZone.spaces.rawValue)
        ]))

        XCTAssertNil(session.space(doomed.id))
        XCTAssertNil(session.tab(tab.id))
        XCTAssertEqual(session.activeSpaceID, home.id, "the window standing in it moves")
        XCTAssertFalse(session.undoManager.canUndo, "another Mac's deletion is not this Mac's to undo")
        let keptJar = await jars.identifiers().contains(doomed.dataStoreIdentifier)
        XCTAssertFalse(keptJar, "and its cookie jar is removed")
    }

    func testARemoteDeleteTearsDownALiveTab() async throws {
        let (_, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: home.id, url: URL(string: "about:blank")!, order: 0)
        session.persistAll(session.list.insert(tab))
        session.activateTab(tab.id)

        try await session.applyRemote(SyncChangeSet(deletions: [
            SyncDeletion(recordType: "Tab", recordName: tab.id.uuidString, zone: SyncZone.spaces.rawValue)
        ]))

        XCTAssertNil(session.tab(tab.id))
        XCTAssertNil(session.controller(for: tab.id), "its web view is torn down")
        XCTAssertNil(session.activeTabID)
    }

    func testAThirteenthFavoriteIsDemotedAndNotSentBack() async throws {
        let (store, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let start = Date(timeIntervalSince1970: 1_000)
        for index in 0..<BrowserStore.favoritesCap {
            let favorite = Tab(
                spaceID: home.id, kind: .essential, url: url("fav\(index)"),
                createdAt: start.addingTimeInterval(Double(index)), order: index
            )
            session.persistAll(session.list.insert(favorite))
        }
        await session.writeChain?.value
        try await store.setSyncZone(.spaces, enabled: true)
        try await clearOutbox(store)

        let extra = Tab(spaceID: home.id, kind: .essential, url: url("extra"), createdAt: Date(), order: 12)
        try await session.applyRemote(SyncChangeSet(modifications: [record(extra)]))
        await session.writeChain?.value

        XCTAssertEqual(session.list.favorites(inSpace: home.id).count, BrowserStore.favoritesCap)
        XCTAssertEqual(session.tab(extra.id)?.kind, .pinned)
        let stored = try await store.tabs(inSpace: home.id, includeArchived: false).first { $0.id == extra.id }
        XCTAssertEqual(stored?.kind, .pinned)
        let outbox = try await store.syncOutbox()
        XCTAssertTrue(outbox.isEmpty, "every Mac demotes the same tab, so nothing goes back up: \(outbox)")
    }

    func testARemoteArchiveLosesToLaterLocalActivity() async throws {
        let (store, session) = try await makeSession()
        let home = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: home.id, url: url("busy"), lastActiveAt: Date(), order: 0)
        session.persistAll(session.list.insert(tab))
        await session.writeChain?.value
        try await store.setSyncZone(.spaces, enabled: true)
        try await clearOutbox(store)

        var remote = tab
        remote.archivedAt = Date().addingTimeInterval(-3600)
        try await session.applyRemote(SyncChangeSet(modifications: [record(remote)]))
        await session.writeChain?.value

        XCTAssertNil(session.tab(tab.id)?.archivedAt, "one Mac's idle clock never archives a tab in use on another")
        XCTAssertFalse(session.archived.contains { $0.id == tab.id })
        let stored = try await store.tabs(inSpace: home.id, includeArchived: true).first { $0.id == tab.id }
        XCTAssertNil(stored?.archivedAt)
        let outbox = try await store.syncOutbox()
        XCTAssertEqual(outbox.map(\.recordType), ["Tab"], "the unarchived state is sent back")
    }

    // MARK: - Helpers

    private func makeSession() async throws -> (BrowserStore, BrowserSession) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        return (store, try await BrowserSession.restored(store: store))
    }

    private func record(_ space: Space) -> SyncRecord {
        fetched(SyncMapping.record(for: space, modifiedAt: Date(), stored: nil))
    }

    private func record(_ tab: Tab) -> SyncRecord {
        fetched(SyncMapping.record(for: tab, modifiedAt: Date(), stored: nil))
    }

    private func fetched(_ record: SyncRecord) -> SyncRecord {
        var record = record
        record.systemFields = Data([1])
        return record
    }

    private func clearOutbox(_ store: BrowserStore) async throws {
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
