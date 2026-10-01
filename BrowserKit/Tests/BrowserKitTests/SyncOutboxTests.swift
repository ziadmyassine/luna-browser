@testable import BrowserKit
import Foundation
import GRDB
import Testing

/// The triggers that turn local writes into `syncOutbox` rows (docs/plans/SYNC-PLAN.md S3).
@Suite("Sync outbox triggers (§31)")
struct SyncOutboxTests {

    /// The outbox keys a UUID row by `hex(id)`, which is uppercase.
    private func key(_ id: UUID) -> String {
        withUnsafeBytes(of: id.uuid) { $0.map { String(format: "%02X", $0) }.joined() }
    }

    private func clearOutbox(_ store: BrowserStore) async throws {
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }
    }

    /// A store with one Space and the Spaces zone on, and an empty outbox.
    private func storeWithSpacesOn() async throws -> (BrowserStore, Space) {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.spaces, enabled: true)
        try await clearOutbox(store)
        let space = try #require(try await store.spaces().first { $0.id == spaceID })
        return (store, space)
    }

    /// The zones the store keeps are the CloudKit zones, by the same names.
    @Test func theStoreUsesSyncZoneNames() async throws {
        let (store, _) = try await makeTemporaryStoreWithSpace()
        for zone in SyncZone.allCases { try await store.setSyncZone(zone, enabled: true) }
        let stored = try await store.pool.read { db in try String.fetchAll(db, sql: "SELECT zone FROM syncZones") }
        #expect(Set(stored) == Set(SyncZone.allCases.map(\.rawValue)))
        let queued = try await store.syncOutbox()
        #expect(!queued.isEmpty)
        #expect(queued.allSatisfy { SyncZone(rawValue: $0.zone) != nil })
    }

    @Test func renamingASpaceGivesOneRow() async throws {
        let (store, space) = try await storeWithSpacesOn()
        var renamed = space
        renamed.name = "Work"
        try await store.upsert(renamed)

        let outbox = try await store.syncOutbox()
        #expect(outbox.count == 1)
        #expect(outbox.first?.recordType == "Space")
        #expect(outbox.first?.localKey == key(space.id))
        #expect(outbox.first?.zone == "Spaces")
        #expect(outbox.first?.isDelete == false)
    }

    /// GRDB's upsert is `INSERT … ON CONFLICT DO UPDATE`, whose conflict handling
    /// overrides an `OR REPLACE` in a trigger it fires, so a second edit of a row
    /// still waiting in the outbox used to fail.
    @Test func aSecondEditBeforeSendingKeepsOneRow() async throws {
        let (store, space) = try await storeWithSpacesOn()
        var renamed = space
        for name in ["Work", "Play"] {
            renamed.name = name
            try await store.upsert(renamed)
        }
        #expect(try await store.syncOutbox().count == 1)
    }

    /// Tabs are written on every activation; only what another Mac would see counts.
    @Test func aChangeToOnlyLocalColumnsGivesNone() async throws {
        let (store, space) = try await storeWithSpacesOn()
        var tab = Tab(spaceID: space.id, url: URL(string: "https://example.com")!, title: "Example")
        try await store.upsert(tab)
        try await clearOutbox(store)

        tab.lastActiveAt = Date().addingTimeInterval(60)
        tab.interactionState = Data([1, 2, 3])
        tab.hasUnread = true
        tab.isDormant = true
        try await store.upsert(tab)
        #expect(try await store.syncOutbox().isEmpty)

        tab.title = "Renamed"
        try await store.upsert(tab)
        #expect(try await store.syncOutbox().map(\.recordType) == ["Tab"])
    }

    @Test func applyingRemoteGivesNone() async throws {
        let (store, space) = try await storeWithSpacesOn()
        try await store.pool.write { db in
            try db.execute(sql: "UPDATE syncControl SET applyingRemote = 1")
            var renamed = space
            renamed.name = "From another Mac"
            try renamed.update(db)
            try Tab(spaceID: space.id, url: URL(string: "https://example.com")!).insert(db)
            try db.execute(sql: "UPDATE syncControl SET applyingRemote = 0")
        }
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func theZoneOffGivesNone() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        try await store.upsert(Tab(spaceID: spaceID, url: URL(string: "https://example.com")!))
        try await store.setSitePermission(.savePasswords, allowed: false, host: "example.com")
        try await store.recordVisit(
            url: URL(string: "https://example.com")!, title: "", kind: .typed, at: Date(), inSpace: spaceID
        )
        try await store.flush()
        #expect(try await store.syncOutbox().isEmpty)

        // On and then off again stops it too, and takes what was pending with it.
        try await store.setSyncZone(.spaces, enabled: true)
        try await store.setSyncZone(.spaces, enabled: false)
        try await store.upsert(Tab(spaceID: spaceID, url: URL(string: "https://example.org")!))
        #expect(try await store.syncOutbox().isEmpty)
    }

    /// SQLite fires delete triggers for a foreign-key cascade, which is the point.
    @Test func deletingASpaceAddsDeletesForItsTabs() async throws {
        let (store, space) = try await storeWithSpacesOn()
        let group = TabGroup(spaceID: space.id, name: "Reading")
        try await store.upsert(group)
        let tabs = [
            Tab(spaceID: space.id, url: URL(string: "https://a.example")!),
            Tab(spaceID: space.id, url: URL(string: "https://b.example")!, groupID: group.id)
        ]
        for tab in tabs { try await store.upsert(tab) }
        try await clearOutbox(store)

        try await store.delete(spaceID: space.id)

        let outbox = try await store.syncOutbox()
        #expect(outbox.allSatisfy { $0.isDelete })
        #expect(Set(outbox.map { "\($0.recordType) \($0.localKey)" }) == Set(
            ["Space \(key(space.id))", "TabGroup \(key(group.id))"] + tabs.map { "Tab \(key($0.id))" }
        ))
    }

    @Test func aSiteSettingGivesASiteRow() async throws {
        let store = try makeTemporaryStore()
        try await store.setSyncZone(.sites, enabled: true)
        try await store.setBlockingDisabled(true, host: "example.com")
        let outbox = try await store.syncOutbox()
        #expect(outbox.map(\.recordType) == ["SiteSetting"])
        #expect(outbox.map(\.localKey) == ["example.com"])
        #expect(outbox.map(\.zone) == ["Sites"])
    }

    @Test func aTypedVisitGivesAHistoryRowAndALinkVisitNone() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.history, enabled: true)
        try await store.recordVisit(
            url: URL(string: "https://link.example")!, title: "", kind: .link, at: Date(), inSpace: spaceID
        )
        try await store.flush()
        #expect(try await store.syncOutbox().isEmpty)

        try await store.recordVisit(
            url: URL(string: "https://typed.example")!, title: "", kind: .typed, at: Date(), inSpace: spaceID
        )
        try await store.flush()
        let placeID = try await store.pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM places WHERE url = 'https://typed.example'")
        }
        let outbox = try await store.syncOutbox()
        #expect(outbox.map(\.recordType) == ["HistoryEntry"])
        #expect(outbox.map(\.localKey) == [placeID.map { String($0) }])
        #expect(outbox.map(\.zone) == ["History"])

        // A visit that arrived from another Mac is not sent back.
        try await clearOutbox(store)
        try await store.pool.write { db in
            try db.execute(
                sql: "INSERT INTO visits (placeId, at, type, spaceID, syncOrigin) VALUES (?, ?, 'typed', ?, 'other-1')",
                arguments: [placeID, Date(), spaceID]
            )
        }
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func turningAZoneOnSeedsEveryRow() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let group = TabGroup(spaceID: spaceID, name: "Reading")
        try await store.upsert(group)
        let tab = Tab(spaceID: spaceID, url: URL(string: "https://a.example")!, archivedAt: Date())
        try await store.upsert(tab)
        try await store.setSitePermission(.savePasswords, allowed: false, host: "bank.example")
        let visits: [(String, VisitKind, Double)] = [
            ("https://recent.example", .typed, 10),
            ("https://old.example", .typed, 100),
            ("https://linked.example", .link, 1),
            ("https://marked.example", .bookmarked, 89)
        ]
        for (url, kind, days) in visits {
            try await store.recordVisit(
                url: URL(string: url)!, title: "", kind: kind, at: daysAgo(days), inSpace: spaceID
            )
        }
        try await store.flush()
        #expect(try await store.syncOutbox().isEmpty)

        try await store.setSyncZone(.spaces, enabled: true)
        #expect(Set(try await store.syncOutbox().map { "\($0.recordType) \($0.localKey)" }) == [
            "Space \(key(spaceID))", "TabGroup \(key(group.id))", "Tab \(key(tab.id))"
        ])

        try await clearOutbox(store)
        try await store.setSyncZone(.sites, enabled: true)
        #expect(try await store.syncOutbox().map(\.localKey) == ["bank.example"])

        // History: only places with a typed or bookmarked visit in the last 90 days.
        try await clearOutbox(store)
        try await store.setSyncZone(.history, enabled: true)
        let expected = try await store.pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT CAST(id AS TEXT) FROM places WHERE url IN ('https://recent.example', 'https://marked.example')"
            )
        }
        let history = try await store.syncOutbox()
        #expect(history.allSatisfy { $0.recordType == "HistoryEntry" && !$0.isDelete })
        #expect(Set(history.map(\.localKey)) == Set(expected))
        #expect(history.count == 2)
    }
}
