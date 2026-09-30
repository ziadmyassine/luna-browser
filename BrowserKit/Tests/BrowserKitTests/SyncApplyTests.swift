@testable import BrowserKit
import Foundation
import GRDB
import Testing

/// Applying a batch of incoming records to the store (docs/plans/SYNC-PLAN.md S6).
@Suite("Sync apply (§31)")
struct SyncApplyTests {

    private static let serverFields = Data([0xC0, 0xFF, 0xEE])

    /// A record as the server hands it back: carrying system fields.
    private func fetched(_ record: SyncRecord) -> SyncRecord {
        var record = record
        record.systemFields = Self.serverFields
        return record
    }

    private func remote(_ space: Space, at date: Date = Date()) -> SyncRecord {
        fetched(SyncMapping.record(for: space, modifiedAt: date, stored: nil))
    }

    private func remote(_ group: TabGroup, at date: Date = Date()) -> SyncRecord {
        fetched(SyncMapping.record(for: group, modifiedAt: date, stored: nil))
    }

    private func remote(_ tab: Tab, at date: Date = Date()) -> SyncRecord {
        fetched(SyncMapping.record(for: tab, modifiedAt: date, stored: nil))
    }

    private func history(_ placeID: Int64, url: String, visits: [SyncHistoryEntry.Visit]) -> SyncRecord {
        let entry = SyncHistoryEntry(
            deviceID: UUID(), placeID: placeID, url: URL(string: url)!, title: "Remote", visits: visits
        )
        return fetched(SyncMapping.record(for: entry, modifiedAt: Date(), stored: nil))
    }

    private func deletion(_ type: String, _ id: UUID) -> SyncDeletion {
        SyncDeletion(recordType: type, recordName: id.uuidString, zone: SyncZone.spaces.rawValue)
    }

    private func newSpace(_ name: String = "Work") -> Space {
        Space(name: name, symbolName: "briefcase", gradient: .defaultSpace)
    }

    private func count(_ store: BrowserStore, _ sql: String, _ arguments: StatementArguments = []) async throws -> Int {
        try await store.pool.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    @Test func spacesThenGroupsThenTabsInOneBatch() async throws {
        let store = try makeTemporaryStore()
        let space = newSpace()
        let group = TabGroup(spaceID: space.id, name: "Reading")
        let tab = Tab(spaceID: space.id, url: URL(string: "https://a.example")!, title: "A", groupID: group.id)

        // Children first on purpose: the batch order must not matter.
        try await store.applyRemote(SyncChangeSet(modifications: [remote(tab), remote(group), remote(space)]))

        #expect(try await store.spaces().map(\.id) == [space.id])
        #expect(try await store.groups(inSpace: space.id).map(\.id) == [group.id])
        let tabs = try await store.tabs(inSpace: space.id, includeArchived: true)
        #expect(tabs.map(\.id) == [tab.id])
        #expect(tabs.first?.groupID == group.id)
        #expect(tabs.first?.title == "A")
        #expect(try await count(store, "SELECT COUNT(*) FROM syncParked") == 0)
    }

    @Test func aMissingParentIsParkedAndAppliedWhenItArrives() async throws {
        let store = try makeTemporaryStore()
        let space = newSpace()
        let group = TabGroup(spaceID: space.id, name: "Reading")
        let tab = Tab(spaceID: space.id, url: URL(string: "https://a.example")!, groupID: group.id)

        try await store.applyRemote(SyncChangeSet(modifications: [remote(tab), remote(group)]))
        #expect(try await count(store, "SELECT COUNT(*) FROM tabs") == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM tabGroups") == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncParked") == 2)

        try await store.applyRemote(SyncChangeSet(modifications: [remote(space)]))
        #expect(try await store.groups(inSpace: space.id).map(\.id) == [group.id])
        #expect(try await store.tabs(inSpace: space.id, includeArchived: true).map(\.groupID) == [group.id])
        #expect(try await count(store, "SELECT COUNT(*) FROM syncParked") == 0)
    }

    @Test func deletionsAreApplied() async throws {
        let store = try makeTemporaryStore()
        let space = newSpace()
        let group = TabGroup(spaceID: space.id, name: "Reading")
        let grouped = Tab(spaceID: space.id, url: URL(string: "https://a.example")!, groupID: group.id)
        let loose = Tab(spaceID: space.id, url: URL(string: "https://b.example")!)
        try await store.applyRemote(SyncChangeSet(modifications: [
            remote(space), remote(group), remote(grouped), remote(loose)
        ]))

        // A deleted group's tabs fall back to loose, as they do locally.
        try await store.applyRemote(SyncChangeSet(deletions: [deletion("TabGroup", group.id), deletion("Tab", loose.id)]))
        #expect(try await store.groups(inSpace: space.id).isEmpty)
        let left = try await store.tabs(inSpace: space.id, includeArchived: true)
        #expect(left.map(\.id) == [grouped.id])
        #expect(left.first?.groupID == nil)

        // A deleted Space takes its tabs with it.
        try await store.applyRemote(SyncChangeSet(deletions: [deletion("Space", space.id)]))
        #expect(try await store.spaces().isEmpty)
        #expect(try await count(store, "SELECT COUNT(*) FROM tabs") == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncRecords WHERE recordName = ?", [space.id.uuidString]) == 0)
    }

    @Test func aNewerPendingLocalEditIsSkipped() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.spaces, enabled: true)
        var local = try #require(try await store.spaces().first { $0.id == spaceID })
        local.name = "Mine"
        try await store.upsert(local)

        var theirs = local
        theirs.name = "Theirs"
        try await store.applyRemote(SyncChangeSet(modifications: [remote(theirs, at: Date().addingTimeInterval(-60))]))
        #expect(try await store.spaces().first?.name == "Mine")
        #expect(try await store.syncOutbox().map(\.recordType) == ["Space"])
        // Left for the merge, which needs the save to meet the server's newer change tag.
        #expect(try await count(store, "SELECT COUNT(*) FROM syncRecords") == 0)

        // A later edit from elsewhere wins, and the local one is no longer waiting to go.
        try await store.applyRemote(SyncChangeSet(modifications: [remote(theirs, at: Date().addingTimeInterval(60))]))
        #expect(try await store.spaces().first?.name == "Theirs")
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func historyReplacesVisitsBySyncOrigin() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let url = "https://remote.example/page"
        let two = history(42, url: url, visits: [
            .init(spaceID: spaceID, at: daysAgo(2), kind: "typed"),
            .init(spaceID: spaceID, at: daysAgo(1), kind: "bookmarked")
        ])
        try await store.applyRemote(SyncChangeSet(modifications: [two]))
        let origin = two.recordName
        #expect(try await count(store, "SELECT COUNT(*) FROM visits WHERE syncOrigin = ?", [origin]) == 2)
        // A place another Mac visited is not a visit this Mac made.
        #expect(try await count(store, "SELECT visitCount FROM places WHERE url = ?", [url]) == 0)
        #expect(try await store.searchHistory("remote", limit: 5, inSpace: spaceID).map(\.url.absoluteString) == [url])

        var one = history(42, url: url, visits: [.init(spaceID: spaceID, at: daysAgo(0), kind: "typed")])
        one.recordName = origin
        try await store.applyRemote(SyncChangeSet(modifications: [one]))
        #expect(try await count(store, "SELECT COUNT(*) FROM visits WHERE syncOrigin = ?", [origin]) == 1)

        try await store.applyRemote(SyncChangeSet(deletions: [
            SyncDeletion(recordType: "HistoryEntry", recordName: origin, zone: SyncZone.history.rawValue)
        ]))
        #expect(try await count(store, "SELECT COUNT(*) FROM visits") == 0)
    }

    @Test func aVisitForAnUnknownSpaceIsDropped() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let record = history(7, url: "https://remote.example", visits: [
            .init(spaceID: spaceID, at: daysAgo(1), kind: "typed"),
            .init(spaceID: UUID(), at: daysAgo(1), kind: "typed")
        ])
        try await store.applyRemote(SyncChangeSet(modifications: [record]))
        #expect(try await count(store, "SELECT COUNT(*) FROM visits") == 1)
        #expect(try await count(store, "SELECT COUNT(*) FROM visits WHERE spaceID = ?", [spaceID]) == 1)
    }

    @Test func anIncomingSpaceGetsAFreshDataStoreIdentifier() async throws {
        let (store, localID) = try await makeTemporaryStoreWithSpace()
        let space = newSpace()
        try await store.applyRemote(SyncChangeSet(modifications: [remote(space)]))
        let jars = Dictionary(uniqueKeysWithValues: try await store.spaces().map { ($0.id, $0.dataStoreIdentifier) })
        let jar = try #require(jars[space.id])
        #expect(!jar.isZero)
        #expect(jar != jars[localID])

        // An update keeps this Mac's jar: changing it would lose the Space's logins.
        var renamed = space
        renamed.name = "Renamed"
        try await store.applyRemote(SyncChangeSet(modifications: [remote(renamed)]))
        let after = try #require(try await store.spaces().first { $0.id == space.id })
        #expect(after.name == "Renamed")
        #expect(after.dataStoreIdentifier == jar)
    }

    @Test func anUpdateKeepsThisMacsLocalColumns() async throws {
        let store = try makeTemporaryStore()
        let space = newSpace()
        var tab = Tab(spaceID: space.id, url: URL(string: "https://a.example")!)
        try await store.applyRemote(SyncChangeSet(modifications: [remote(space), remote(tab)]))
        var local = try #require(try await store.tabs(inSpace: space.id, includeArchived: true).first)
        local.interactionState = Data([9])
        local.lastActiveAt = daysAgo(3)
        try await store.upsert(local)
        // Read back: the column keeps milliseconds.
        local = try #require(try await store.tabs(inSpace: space.id, includeArchived: true).first)

        tab.title = "Retitled"
        try await store.applyRemote(SyncChangeSet(modifications: [remote(tab)]))
        let after = try #require(try await store.tabs(inSpace: space.id, includeArchived: true).first)
        #expect(after.title == "Retitled")
        #expect(after.interactionState == Data([9]))
        #expect(after.lastActiveAt == local.lastActiveAt)
    }

    @Test func nothingReachesTheOutbox() async throws {
        let (store, localID) = try await makeTemporaryStoreWithSpace()
        for zone in SyncZone.allCases { try await store.setSyncZone(zone, enabled: true) }
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }

        let space = newSpace()
        let group = TabGroup(spaceID: space.id, name: "Reading")
        let tab = Tab(spaceID: space.id, url: URL(string: "https://a.example")!)
        let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))
        let site = fetched(SyncMapping.record(
            for: SyncSiteSetting(host: "example.com", localNetwork: true, blockingDisabled: true),
            secret: secret, modifiedAt: Date(), stored: nil
        ))
        let visits = history(3, url: "https://remote.example", visits: [.init(spaceID: localID, at: Date(), kind: "typed")])
        try await store.applyRemote(SyncChangeSet(modifications: [remote(space), remote(group), remote(tab), site, visits]))
        try await store.applyRemote(SyncChangeSet(deletions: [deletion("Tab", tab.id)]))

        #expect(try await store.syncOutbox().isEmpty)
        #expect(try await count(store, "SELECT applyingRemote FROM syncControl") == 0)
        #expect(try await store.sitePermissions()[.localNetwork]?["example.com"] == true)
        #expect(try await store.blockingExemptions().blockingDisabled.contains("example.com"))
        #expect(try await count(store, "SELECT COUNT(*) FROM syncRecords WHERE localKey = 'example.com'") == 1)
    }

    @Test func theSchemaVersionIsStored() async throws {
        let store = try makeTemporaryStore()
        var record = remote(newSpace())
        record.schemaVersion = 3
        try await store.applyRemote(SyncChangeSet(modifications: [record]))
        let name = record.recordName
        // `Row` is not `Sendable`, so the columns are read before the closure returns.
        let row = try await store.pool.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM syncRecords WHERE recordName = ?", arguments: [name]).map { row in
                (row["schemaVersion"] as Int64?, row["systemFields"] as Data?, row["zone"] as String?, row["recordType"] as String?)
            }
        }
        let stored = try #require(row)
        #expect(stored.0 == 3)
        #expect(stored.1 == Self.serverFields)
        #expect(stored.2 == "Spaces")
        #expect(stored.3 == "Space")
    }

    // MARK: The seed Space (docs/plans/SYNC-PLAN.md §9)

    private func seededStore() async throws -> (BrowserStore, UUID) {
        let (store, seed) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.spaces, enabled: true)
        return (store, seed)
    }

    @Test func theFirstFetchDropsAnUntouchedSeedSpace() async throws {
        let (store, seed) = try await seededStore()
        let theirs = newSpace("Personal")
        try await store.applyRemote(SyncChangeSet(modifications: [remote(theirs)]), isFirstFetch: true)
        #expect(try await store.spaces().map(\.id) == [theirs.id])
        // Never sent: it was only ever this Mac's placeholder.
        #expect(try await store.syncOutbox().isEmpty)
        _ = seed
    }

    @Test func aSeedSpaceInUseIsKept() async throws {
        // Renamed.
        let (renamedStore, renamedID) = try await seededStore()
        var renamed = try #require(try await renamedStore.spaces().first)
        renamed.name = "Home"
        try await renamedStore.upsert(renamed)
        try await renamedStore.applyRemote(SyncChangeSet(modifications: [remote(newSpace())]), isFirstFetch: true)
        #expect(try await renamedStore.spaces().contains { $0.id == renamedID })

        // With a tab in it.
        let (usedStore, usedID) = try await seededStore()
        try await usedStore.upsert(Tab(spaceID: usedID, url: URL(string: "https://a.example")!))
        try await usedStore.applyRemote(SyncChangeSet(modifications: [remote(newSpace())]), isFirstFetch: true)
        #expect(try await usedStore.spaces().count == 2)

        // Not the first fetch.
        let (laterStore, _) = try await seededStore()
        try await laterStore.applyRemote(SyncChangeSet(modifications: [remote(newSpace())]))
        #expect(try await laterStore.spaces().count == 2)

        // iCloud has no Spaces.
        let (emptyStore, _) = try await seededStore()
        try await emptyStore.applyRemote(SyncChangeSet(), isFirstFetch: true)
        #expect(try await emptyStore.spaces().count == 1)

        // iCloud already has this very Space, from an earlier time sync was on.
        let (againStore, againID) = try await seededStore()
        let own = try #require(try await againStore.spaces().first)
        try await againStore.applyRemote(SyncChangeSet(modifications: [remote(own), remote(newSpace())]), isFirstFetch: true)
        #expect(try await againStore.spaces().contains { $0.id == againID })
    }
}
