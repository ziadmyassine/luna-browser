//
//  Schema+Sync.swift
//  BrowserKit
//
//  `v12`, the tables iCloud sync keeps its state in (docs/plans/SYNC-PLAN.md §1).
//  Beside the rest of the schema rather than in it because `Schema` is at
//  SwiftLint's type-body limit.
//

import Foundation
import GRDB

extension Schema {

    /// `v12` — sync's bookkeeping, and the `siteSettings` flags.
    ///
    /// The flags are created here because a trigger cannot name a column that
    /// may not exist yet. A database may already hold some of them, added on
    /// first use by the earlier `ensure…Columns`; it keeps them and their
    /// answers, and the types here match what those wrote. Every table lives in
    /// `luna.sqlite`, so wiping the database wipes sync state with it.
    /// Idempotent on the live schema, like every migration.
    static func prepareForSync(_ db: Database) throws {
        try addTheSiteFlags(db)
        if try !db.columns(in: "visits").map(\.name).contains("syncOrigin") {
            // NULL for a visit made here; otherwise the HistoryEntry it came
            // from, which an incoming entry replaces its visits by.
            try db.execute(sql: "ALTER TABLE visits ADD COLUMN syncOrigin TEXT")
        }
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS visits_on_syncOrigin ON visits(syncOrigin) WHERE syncOrigin IS NOT NULL")
        for statement in SyncSQL.tables + SyncSQL.triggers { try db.execute(sql: statement) }
        try db.execute(sql: "INSERT OR IGNORE INTO syncControl (id, applyingRemote) VALUES (1, 0)")
    }

    /// The permissions (`BrowserStore.SitePermission`) are nullable: the default
    /// is the permission's, not the column's, and a `NOT NULL DEFAULT 0` would
    /// record a refusal for every site that has a zoom level set. The blocking
    /// flags were always `NOT NULL DEFAULT 0` and stay so.
    private static func addTheSiteFlags(_ db: Database) throws {
        let existing = Set(try db.columns(in: "siteSettings").map(\.name))
        let flags = [
            ("automaticPictureInPicture", "BOOLEAN"),
            ("localNetwork", "BOOLEAN"),
            ("savePasswords", "BOOLEAN"),
            ("popups", "BOOLEAN"),
            ("blockingDisabled", "BOOLEAN NOT NULL DEFAULT 0"),
            ("insecureAllowed", "BOOLEAN NOT NULL DEFAULT 0")
        ]
        for (name, type) in flags where !existing.contains(name) {
            try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN \(name) \(type)")
        }
    }
}

/// Change tracking is triggers rather than store hooks because triggers catch
/// every writer, foreign-key cascades included, and the outbox they fill
/// survives a crash (docs/plans/SYNC-PLAN.md §1).
enum SyncSQL {

    /// A table whose rows are records, and the columns another Mac would see.
    /// Everything else (`lastActiveAt`, `interactionState`, `isCollapsed`,
    /// `dataStoreIdentifier` and the like) is written on every activation or
    /// only means something on this Mac, so it never causes an outbox row.
    private struct Tracked {
        let table: String
        let recordType: String
        let zone: SyncZone
        /// The outbox key, given the row's alias: `hex(id)` for a UUID blob.
        let key: @Sendable (String) -> String
        let synced: [String]
    }

    private static let byID: @Sendable (String) -> String = { "hex(\($0).id)" }

    private static let tracked = [
        Tracked(
            table: "spaces", recordType: "Space", zone: .spaces, key: byID,
            synced: ["name", "symbolName", "gradient", "imageData", "order"]
        ),
        Tracked(
            table: "tabGroups", recordType: "TabGroup", zone: .spaces, key: byID,
            synced: ["spaceID", "name", "symbolName", "kind", "order"]
        ),
        Tracked(
            table: "tabs", recordType: "Tab", zone: .spaces, key: byID,
            synced: [
                "spaceID", "groupID", "kind", "order", "archivedAt", "url", "title",
                "customTitle", "customSymbolName", "pinnedURL"
            ]
        ),
        Tracked(
            table: "siteSettings", recordType: "SiteSetting", zone: .sites, key: { "\($0).host" },
            synced: [
                "zoom", "automaticPictureInPicture", "localNetwork", "savePasswords", "popups",
                "blockingDisabled", "insecureAllowed"
            ]
        ),
        // `DefaultsSync` mirrors the allowlisted defaults here, so a setting
        // gets the same zone guard, echo guard and turn-on seed as a row.
        Tracked(
            table: "syncedDefaults", recordType: "Setting", zone: .settings, key: { "\($0).key" },
            synced: ["value"]
        )
    ]

    /// Off while an incoming change is being applied, which is what stops the
    /// echo, and off for a zone the user has not turned on.
    private static func guarded(_ zone: SyncZone) -> String {
        "(SELECT applyingRemote FROM syncControl) = 0 AND EXISTS (SELECT 1 FROM syncZones WHERE zone = '\(zone.rawValue)' AND enabled)"
    }

    /// The same format GRDB writes a `Date` in, so `changedAt` decodes as one.
    private static let now = "strftime('%Y-%m-%d %H:%M:%f', 'now')"

    /// An upsert, not `INSERT OR REPLACE`: GRDB writes rows with `INSERT … ON CONFLICT
    /// DO UPDATE`, and that statement's conflict handling overrides an `OR REPLACE` in
    /// any trigger it fires, so a second edit of a row still in the outbox failed.
    private static func record(_ type: String, key: String, zone: SyncZone, isDelete: Bool) -> String {
        """
        INSERT INTO syncOutbox (recordType, localKey, zone, isDelete, changedAt)
        VALUES ('\(type)', \(key), '\(zone.rawValue)', \(isDelete ? 1 : 0), \(now))
        ON CONFLICT (recordType, localKey) DO UPDATE SET isDelete = excluded.isDelete, changedAt = excluded.changedAt;
        """
    }

    static var triggers: [String] {
        var statements = tracked.flatMap { item in
            let upsert = record(item.recordType, key: item.key("NEW"), zone: item.zone, isDelete: false)
            let columns = item.synced.map { "\"\($0)\"" }
            // GRDB's upsert sets every column, so `UPDATE OF` alone fires on a
            // write that changed nothing another Mac would see.
            let changed = columns.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR ")
            return [
                """
                CREATE TRIGGER IF NOT EXISTS sync_\(item.table)_insert AFTER INSERT ON \(item.table)
                WHEN \(guarded(item.zone)) BEGIN \(upsert) END
                """,
                """
                CREATE TRIGGER IF NOT EXISTS sync_\(item.table)_update
                AFTER UPDATE OF \(columns.joined(separator: ", ")) ON \(item.table)
                WHEN \(guarded(item.zone)) AND (\(changed)) BEGIN \(upsert) END
                """,
                """
                CREATE TRIGGER IF NOT EXISTS sync_\(item.table)_delete AFTER DELETE ON \(item.table)
                WHEN \(guarded(item.zone))
                BEGIN \(record(item.recordType, key: item.key("OLD"), zone: item.zone, isDelete: true)) END
                """
            ]
        }
        // A HistoryEntry is a place, sent when this Mac types or bookmarks
        // its way to it. A visit with a `syncOrigin` came from another Mac.
        statements.append("""
        CREATE TRIGGER IF NOT EXISTS sync_visits_insert AFTER INSERT ON visits
        WHEN \(guarded(.history)) AND NEW.type IN ('typed', 'bookmarked') AND NEW.syncOrigin IS NULL
        BEGIN \(record("HistoryEntry", key: "CAST(NEW.placeId AS TEXT)", zone: .history, isDelete: false)) END
        """)
        return statements
    }

    /// What turning `zone` on queues: every row it covers, except that history
    /// goes back only 90 days (docs/plans/SYNC-PLAN.md §1).
    static func seed(_ zone: SyncZone) -> [String] {
        let rows = tracked.filter { $0.zone == zone }.map { item in
            """
            INSERT OR IGNORE INTO syncOutbox (recordType, localKey, zone, isDelete, changedAt)
            SELECT '\(item.recordType)', \(item.key("r")), '\(zone.rawValue)', 0, \(now) FROM \(item.table) AS r
            """
        }
        guard zone == .history else { return rows }
        return rows + ["""
        INSERT OR IGNORE INTO syncOutbox (recordType, localKey, zone, isDelete, changedAt)
        SELECT DISTINCT 'HistoryEntry', CAST(placeId AS TEXT), '\(SyncZone.history.rawValue)', 0, \(now) FROM visits
        WHERE type IN ('typed', 'bookmarked') AND syncOrigin IS NULL
          AND at >= strftime('%Y-%m-%d %H:%M:%f', 'now', '-90 days')
        """]
    }

    static let tables = [
        // One row per record with a local change not yet sent, however often
        // the record changes.
        """
        CREATE TABLE IF NOT EXISTS syncOutbox (
            recordType TEXT NOT NULL,
            localKey TEXT NOT NULL,
            zone TEXT NOT NULL,
            isDelete BOOLEAN NOT NULL,
            changedAt DATETIME NOT NULL,
            PRIMARY KEY (recordType, localKey)
        )
        """,
        "CREATE TABLE IF NOT EXISTS syncMeta (key TEXT PRIMARY KEY NOT NULL, value BLOB)",
        """
        CREATE TABLE IF NOT EXISTS syncRecords (
            recordType TEXT NOT NULL,
            recordName TEXT PRIMARY KEY NOT NULL,
            localKey TEXT NOT NULL,
            zone TEXT NOT NULL,
            systemFields BLOB NOT NULL,
            -- The stored half of §31.9's "write max(own, stored)", which has to
            -- hold for every save and not only one that meets a conflict.
            schemaVersion INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS syncParked (
            recordType TEXT NOT NULL,
            recordName TEXT PRIMARY KEY NOT NULL,
            record BLOB NOT NULL
        )
        """,
        "CREATE TABLE IF NOT EXISTS syncZones (zone TEXT PRIMARY KEY NOT NULL, enabled BOOLEAN NOT NULL)",
        // One row, read by every trigger's guard.
        """
        CREATE TABLE IF NOT EXISTS syncControl (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            applyingRemote INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS syncPresence (
            deviceID TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            updatedAt DATETIME NOT NULL,
            tabs BLOB NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS syncedDefaults (
            key TEXT PRIMARY KEY NOT NULL,
            value BLOB,
            modifiedAt DATETIME NOT NULL
        )
        """
    ]
}
