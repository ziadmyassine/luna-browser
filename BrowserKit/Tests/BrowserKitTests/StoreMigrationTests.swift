@testable import BrowserKit
import Foundation
import GRDB
import Testing

/// Open, write, close, reopen. The migrator runs on every launch, so "runs twice over a
/// database that already has data" is the case that matters (§11.1).
@Suite("Store migration & seeding (§11.1)")
struct StoreMigrationTests {

    @Test func survivesACloseAndReopen() async throws {
        let path = temporaryDatabasePath()
        let tabID = UUID()
        let spaceID: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
            spaceID = try await store.spaces()[0].id
            try await store.upsert(Tab(id: tabID, spaceID: spaceID, url: URL(string: "https://example.com")!, title: "Example"))
            try await store.recordVisit(
                url: URL(string: "https://example.com")!,
                title: "Example",
                kind: .typed,
                at: Date(),
                inSpace: spaceID
            )
            // Without this the visit is still sitting in the buffer (§11.5).
            try await store.flush()
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.spaces().count == 1)
        #expect(try await reopened.tabs(inSpace: spaceID, includeArchived: false).map(\.id) == [tabID])
        #expect(try await reopened.searchHistory("example", limit: 5, inSpace: spaceID).count == 1)
    }

    /// A buffered visit that nobody flushes is a visit that never happened.
    @Test func doesNotWriteBufferedVisitsUntilFlushed() async throws {
        let path = temporaryDatabasePath()
        let store = try BrowserStore(path: path)
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0].id
        try await store.recordVisit(
            url: URL(string: "https://buffered.example")!,
            title: "Buffered",
            kind: .typed,
            at: Date(),
            inSpace: space
        )

        // A second connection sees only what is committed.
        let other = try BrowserStore(path: path)
        #expect(try await other.searchHistory("buffered", limit: 5, inSpace: space).isEmpty)

        try await store.flush()
        #expect(try await other.searchHistory("buffered", limit: 5, inSpace: space).count == 1)
    }

    @Test func seedsExactlyOnce() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        try await store.seedIfEmpty()

        let spaces = try await store.spaces()
        #expect(spaces.count == 1)
        // The seeded Space must carry a usable identifier, or the first window has no
        // WKWebsiteDataStore to open (§5.1).
        #expect(spaces[0].hasUsableDataStoreIdentifier)
        #expect(spaces[0].symbolName.isEmpty == false)
    }

    /// Since `v8` a visit belongs to a Space, and the two Spaces must not be able
    /// to see each other's — this is the whole of §9.2's isolation, at the bottom
    /// of the stack where it can be proved without a window.
    @Test func aVisitInOneSpaceIsInvisibleFromTheOther() async throws {
        let (store, personal) = try await makeTemporaryStoreWithSpace()
        let work = Space(name: "Work", symbolName: "hammer", gradient: .defaultSpace)
        try await store.upsert(work)

        try await store.recordVisit(
            url: URL(string: "https://mail.example/inbox")!,
            title: "Private Mail",
            kind: .typed,
            at: daysAgo(1),
            inSpace: personal
        )
        try await store.flush()

        #expect(try await store.searchHistory("mail", limit: 10, inSpace: personal).count == 1)
        #expect(try await store.searchHistory("mail", limit: 10, inSpace: work.id).isEmpty)
        // And the opening list of a Space that has never been browsed is empty,
        // rather than the other Space's twenty most recent pages.
        #expect(try await store.searchHistory("", limit: 10, inSpace: work.id).isEmpty)
    }

    /// Foreign keys, not application code, keep a Space's tabs from outliving it.
    @Test func deletingASpaceTakesItsTabs() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0]
        try await store.upsert(Tab(spaceID: space.id, url: URL(string: "https://example.com")!))

        try await store.delete(spaceID: space.id)

        #expect(try await store.spaces().isEmpty)
        #expect(try await store.tabs(inSpace: space.id, includeArchived: true).isEmpty)
    }

    // MARK: - v12, sync (docs/SYNC-PLAN.md S2)

    /// A trigger cannot name a column that may not exist yet, so the flags exist
    /// from the migration on rather than being added on first use.
    @Test func v12CreatesTheSiteSettingsFlagColumnsUpFront() async throws {
        let store = try makeTemporaryStore()
        let columns = try await store.pool.read { db in
            Dictionary(uniqueKeysWithValues: try db.columns(in: "siteSettings").map { ($0.name, $0) })
        }
        // Nullable: absent is "nobody has answered", which is not a refusal.
        for name in ["automaticPictureInPicture", "localNetwork", "savePasswords", "popups"] {
            let column = try #require(columns[name], "missing \(name)")
            #expect(column.type == "BOOLEAN")
            #expect(!column.isNotNull)
        }
        for name in ["blockingDisabled", "insecureAllowed"] {
            let column = try #require(columns[name], "missing \(name)")
            #expect(column.type == "BOOLEAN")
            #expect(column.isNotNull)
            #expect(column.defaultValueSQL == "0")
        }
        // Every permission has its column from the migration, not from first use.
        for permission in BrowserStore.SitePermission.allCases {
            #expect(columns[permission.rawValue] != nil, "no column for \(permission)")
        }
    }

    @Test func v12CreatesEverySyncTableAndVisitsSyncOrigin() async throws {
        let store = try makeTemporaryStore()
        let expected: [String: Set<String>] = [
            "syncOutbox": ["recordType", "localKey", "zone", "isDelete", "changedAt"],
            "syncMeta": ["key", "value"],
            "syncRecords": ["recordType", "recordName", "localKey", "zone", "systemFields", "schemaVersion"],
            "syncParked": ["recordType", "recordName", "record"],
            "syncZones": ["zone", "enabled"],
            "syncControl": ["id", "applyingRemote"],
            "syncPresence": ["deviceID", "name", "updatedAt", "tabs"],
            "syncedDefaults": ["key", "value", "modifiedAt"]
        ]
        let (found, visitColumns, control, zones) = try await store.pool.read { db in
            var found: [String: Set<String>] = [:]
            for table in expected.keys where try db.tableExists(table) {
                found[table] = Set(try db.columns(in: table).map(\.name))
            }
            return (
                found,
                try db.columns(in: "visits").map(\.name),
                try Int.fetchAll(db, sql: "SELECT applyingRemote FROM syncControl"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncZones")
            )
        }
        #expect(found == expected)
        #expect(visitColumns.contains("syncOrigin"))
        #expect(control == [0])
        // Sync is opt-in: no zone is on until the user turns one on.
        #expect(zones == 0)
    }

    /// A database from before sync, including a flag column added the old way
    /// (`ensureBlockingColumns`) and the answers already written into it.
    @Test func aV11DatabaseMigrates() async throws {
        let path = temporaryDatabasePath()
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let pool = try DatabasePool(path: path.path)
            try Schema.migrator().migrate(pool, upTo: "v11")
            try await pool.write { db in
                try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN blockingDisabled BOOLEAN NOT NULL DEFAULT 0")
                try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN localNetwork BOOLEAN")
                try db.execute(
                    sql: "INSERT INTO siteSettings (host, updatedAt, blockingDisabled, localNetwork) VALUES (?, ?, 1, 1)",
                    arguments: ["old.example", Date()]
                )
                try db.execute(sql: "INSERT INTO places (url, host, lastVisit) VALUES ('https://old.example/', 'old.example', ?)", arguments: [Date()])
                try db.execute(sql: "INSERT INTO visits (placeId, at, type) VALUES (1, ?, 'typed')", arguments: [Date()])
            }
            try pool.close()
        }

        let store = try BrowserStore(path: path)
        #expect(try await store.blockingExemptions().blockingDisabled == ["old.example"])
        #expect(try await store.sitePermissions()[.localNetwork] == ["old.example": true])
        let (origins, columnCount) = try await store.pool.read { db in
            (
                try Row.fetchAll(db, sql: "SELECT syncOrigin FROM visits").map { $0["syncOrigin"] as String? },
                try db.columns(in: "siteSettings").count
            )
        }
        #expect(origins == [nil])
        #expect(columnCount == 9)
        // Turning sync on for the first time is what uploads old rows, not the migration.
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func migratingTwiceIsHarmless() async throws {
        let path = temporaryDatabasePath()
        let store = try BrowserStore(path: path)
        try await store.pool.write { db in try Schema.prepareForSync(db) }
        _ = try BrowserStore(path: path)
        let controlRows = try await store.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncControl")
        }
        #expect(controlRows == 1)
    }
}
