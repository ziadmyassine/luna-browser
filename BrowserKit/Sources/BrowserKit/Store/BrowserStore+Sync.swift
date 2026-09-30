import Foundation
import GRDB

/// One local change waiting to be sent (docs/plans/SYNC-PLAN.md §1).
struct SyncOutboxEntry: Sendable, Hashable, Codable, FetchableRecord {
    var recordType: String
    var localKey: String
    var zone: String
    var isDelete: Bool
    var changedAt: Date
}

extension BrowserStore {

    func syncOutbox() async throws -> [SyncOutboxEntry] {
        try await pool.read { db in
            try SyncOutboxEntry.fetchAll(db, sql: "SELECT * FROM syncOutbox ORDER BY changedAt")
        }
    }

    /// Turns a zone on, queuing every row it already covers, or off, dropping
    /// what it had queued: with a zone off nothing of it is in the outbox, so
    /// the outbox never has to be filtered by zone.
    func setSyncZone(_ zone: SyncZone, enabled: Bool) async throws {
        try await pool.write { db in
            guard enabled else {
                try db.execute(sql: "DELETE FROM syncZones WHERE zone = ?", arguments: [zone.rawValue])
                try db.execute(sql: "DELETE FROM syncOutbox WHERE zone = ?", arguments: [zone.rawValue])
                return
            }
            let wasOn = try Bool.fetchOne(db, sql: "SELECT enabled FROM syncZones WHERE zone = ?", arguments: [zone.rawValue])
            guard wasOn != true else { return }
            try db.execute(sql: "INSERT OR REPLACE INTO syncZones (zone, enabled) VALUES (?, 1)", arguments: [zone.rawValue])
            for statement in SyncSQL.seed(zone) { try db.execute(sql: statement) }
        }
    }
}

/// A record another Mac deleted. CloudKit hands back only its type and ID.
public struct SyncDeletion: Sendable, Hashable {
    public var recordType: String
    public var recordName: String
    public var zone: String

    public init(recordType: String, recordName: String, zone: String) {
        self.recordType = recordType
        self.recordName = recordName
        self.zone = zone
    }
}

/// One fetched batch of changes from other Macs.
public struct SyncChangeSet: Sendable {
    public var modifications: [SyncRecord]
    public var deletions: [SyncDeletion]

    public init(modifications: [SyncRecord] = [], deletions: [SyncDeletion] = []) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

extension BrowserStore {

    /// Applies a fetched batch in one transaction with the echo guard up, so none of it
    /// reaches the outbox (docs/plans/SYNC-PLAN.md §1).
    ///
    /// Spaces, groups, site settings, history and the settings mirror are applied here.
    /// Devices and the secret have their own owners, and a type this Luna does not know is left alone
    /// (§31.9). A record with a newer unsent edit on this Mac is skipped, and its system
    /// fields are not stored, so the save that follows meets the server's change tag and
    /// goes through the merge (§3).
    ///
    /// - Parameter isFirstFetch: the fetch after turning sync on. iCloud wins for every
    ///   record it has, over the outbox rows turning the zone on queued, and this Mac's
    ///   untouched seed Space is dropped (§3).
    public func applyRemote(_ changes: SyncChangeSet, isFirstFetch: Bool = false) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE syncControl SET applyingRemote = 1")
            for deletion in changes.deletions { try SyncApply.delete(deletion, db) }
            for record in changes.modifications.sorted(by: SyncApply.parentsFirst) {
                _ = try SyncApply.apply(record, db, iCloudWins: isFirstFetch)
            }
            try SyncApply.unpark(db)
            if isFirstFetch { try SyncApply.dropTheSeedSpace(db, arrived: changes.modifications) }
            try db.execute(sql: "UPDATE syncControl SET applyingRemote = 0")
        }
    }
}

private enum SyncApply {

    enum Outcome { case applied, parked, skipped }

    private static let uuidKeyed = ["Space": "spaces", "TabGroup": "tabGroups", "Tab": "tabs"]
    private static let rank = ["Space": 0, "TabGroup": 1, "Tab": 2]

    static func parentsFirst(_ lhs: SyncRecord, _ rhs: SyncRecord) -> Bool {
        rank[lhs.recordType, default: 3] < rank[rhs.recordType, default: 3]
    }

    static func apply(_ record: SyncRecord, _ db: Database, iCloudWins: Bool = false) throws -> Outcome {
        try db.execute(sql: "DELETE FROM syncParked WHERE recordName = ?", arguments: [record.recordName])
        let key = localKey(of: record)
        if !iCloudWins, try pendingHereIsNewer(record, key: key, db) { return .skipped }
        let outcome = try writeRow(record, db)
        guard outcome == .applied else { return outcome }
        if let systemFields = record.systemFields {
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO syncRecords (recordType, recordName, localKey, zone, systemFields, schemaVersion)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [record.recordType, record.recordName, key, record.zone, systemFields, record.schemaVersion]
            )
        }
        // An older local edit lost to this one and has nothing left to send.
        try db.execute(
            sql: "DELETE FROM syncOutbox WHERE recordType = ? AND localKey = ?", arguments: [record.recordType, key]
        )
        return .applied
    }

    private static func writeRow(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        switch record.recordType {
        case "Space": try writeSpace(record, db)
        case "TabGroup": try writeGroup(record, db)
        case "Tab": try writeTab(record, db)
        case "SiteSetting": try writeSite(record, db)
        case "HistoryEntry": try writeHistory(record, db)
        case "Setting": try writeSetting(record, db)
        default: .skipped
        }
    }

    private static func writeSpace(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard var space = SyncMapping.space(from: record) else { return .skipped }
        // The mapping mints a jar; a Space already here keeps its own, and its logins.
        if let jar = try UUID.fetchOne(
            db, sql: "SELECT dataStoreIdentifier FROM spaces WHERE id = ?", arguments: [space.id]
        ) { space.dataStoreIdentifier = jar }
        try space.upsert(db)
        return .applied
    }

    private static func writeGroup(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard var group = SyncMapping.tabGroup(from: record)?.sanitisingKind() else { return .skipped }
        guard try exists("spaces", group.spaceID, db) else { return try park(record, db) }
        group.isCollapsed = try Bool.fetchOne(
            db, sql: "SELECT isCollapsed FROM tabGroups WHERE id = ?", arguments: [group.id]
        ) ?? false
        try group.upsert(db)
        return .applied
    }

    private static func writeTab(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard let tab = SyncMapping.tab(from: record) else { return .skipped }
        guard try exists("spaces", tab.spaceID, db), try tab.groupID.map({ try exists("tabGroups", $0, db) }) ?? true
        else { return try park(record, db) }
        try keepingLocalColumns(of: tab, db).upsert(db)
        return .applied
    }

    /// Delete beats edit, locally as on the other Mac (§3).
    static func delete(_ deletion: SyncDeletion, _ db: Database) throws {
        let type = deletion.recordType, name = deletion.recordName
        let key = try uuidKey(type, name)
            ?? String.fetchOne(db, sql: "SELECT localKey FROM syncRecords WHERE recordName = ?", arguments: [name])
            ?? name
        if let table = uuidKeyed[type], let id = UUID(uuidString: name) {
            // Foreign keys cascade to tabs, or loosen them from a group, as a local delete does.
            try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
        } else if type == "SiteSetting" {
            try db.execute(sql: "DELETE FROM siteSettings WHERE host = ?", arguments: [key])
        } else if type == "HistoryEntry" {
            try db.execute(sql: "DELETE FROM visits WHERE syncOrigin = ?", arguments: [name])
        } else if type == "Setting" {
            try db.execute(sql: "DELETE FROM syncedDefaults WHERE key = ?", arguments: [name])
        } else {
            return
        }
        try db.execute(sql: "DELETE FROM syncRecords WHERE recordName = ?", arguments: [name])
        try db.execute(sql: "DELETE FROM syncParked WHERE recordName = ?", arguments: [name])
        try db.execute(sql: "DELETE FROM syncOutbox WHERE recordType = ? AND localKey = ?", arguments: [type, key])
    }

    /// Retries parked records until a pass applies none, since a group coming out can
    /// free the tabs parked behind it.
    static func unpark(_ db: Database) throws {
        var progressed = true
        while progressed {
            progressed = false
            let parked = try Data.fetchAll(db, sql: "SELECT record FROM syncParked")
                .compactMap { try? PropertyListDecoder().decode(SyncRecord.self, from: $0) }
            for record in parked.sorted(by: parentsFirst) where try apply(record, db) == .applied {
                progressed = true
            }
        }
    }

    /// On the first fetch, when iCloud already has Spaces, this Mac's seed Space goes if
    /// nobody renamed it or put anything in it; otherwise both stay (§9).
    static func dropTheSeedSpace(_ db: Database, arrived: [SyncRecord]) throws {
        let spaces = Set(arrived.filter { $0.recordType == "Space" }.map(\.recordName))
        let seeds = try UUID.fetchAll(
            db,
            sql: """
            SELECT id FROM spaces AS s WHERE name = ?
              AND NOT EXISTS (SELECT 1 FROM tabs WHERE spaceID = s.id)
              AND NOT EXISTS (SELECT 1 FROM tabGroups WHERE spaceID = s.id)
            """,
            arguments: [BrowserStore.seedSpaceName]
        )
        // A seed iCloud already holds is a Space that synced before, not a placeholder.
        for seed in seeds where !spaces.isEmpty && !spaces.contains(seed.uuidString) {
            try db.execute(sql: "DELETE FROM spaces WHERE id = ?", arguments: [seed])
            try db.execute(
                sql: "DELETE FROM syncOutbox WHERE recordType = 'Space' AND localKey = ?", arguments: [hex(seed)]
            )
        }
    }

    // MARK: Helpers

    /// The key the triggers file this record's outbox row under. A HistoryEntry from
    /// another Mac has none, since this Mac's own are keyed by `places.id`.
    private static func localKey(of record: SyncRecord) -> String {
        if let key = uuidKey(record.recordType, record.recordName) { return key }
        if record.recordType == "SiteSetting", case .string(let host) = record["host"] { return host }
        return record.recordName
    }

    private static func uuidKey(_ type: String, _ name: String) -> String? {
        guard uuidKeyed[type] != nil, let id = UUID(uuidString: name) else { return nil }
        return hex(id)
    }

    /// SQLite's `hex(id)` of a UUID blob, uppercase, as the triggers write it.
    private static func hex(_ id: UUID) -> String {
        withUnsafeBytes(of: id.uuid) { $0.map { String(format: "%02X", $0) }.joined() }
    }

    /// A local delete not yet sent beats any incoming edit. A record without
    /// `modifiedAt` cannot show it is newer, so the local edit stands.
    private static func pendingHereIsNewer(_ record: SyncRecord, key: String, _ db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT isDelete, changedAt FROM syncOutbox WHERE recordType = ? AND localKey = ?",
            arguments: [record.recordType, key]
        ) else { return false }
        guard !(row["isDelete"] as Bool), case .date(let modifiedAt) = record["modifiedAt"] else { return true }
        return (row["changedAt"] as Date) > modifiedAt
    }

    private static func exists(_ table: String, _ id: UUID, _ db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(table) WHERE id = ?)", arguments: [id]) ?? false
    }

    private static func park(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncParked (recordType, recordName, record) VALUES (?, ?, ?)",
            arguments: [record.recordType, record.recordName, try PropertyListEncoder().encode(record)]
        )
        return .parked
    }

    /// The incoming tab with this Mac's own columns (`SyncSQL`'s local-only set) kept.
    private static func keepingLocalColumns(of incoming: Tab, _ db: Database) throws -> Tab {
        guard let local = try Tab.fetchOne(db, key: incoming.id) else { return incoming }
        var tab = incoming
        tab.faviconKey = local.faviconKey
        tab.themeColor = local.themeColor
        tab.lastActiveAt = local.lastActiveAt
        tab.parentTabID = local.parentTabID
        tab.interactionState = local.interactionState
        tab.hasUnread = local.hasUnread
        tab.isDormant = local.isDormant
        return tab
    }

    /// The whole record, not a merge: a flag it leaves out is unset. The two blocking
    /// flags are `NOT NULL`, so unset is 0 for them.
    private static func writeSite(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard let site = SyncMapping.siteSetting(from: record) else { return .skipped }
        let flags = SyncSiteSetting.flags
        let names = flags.map(\.0)
        let values: [(any DatabaseValueConvertible)?] = flags.map { name, path in
            site[keyPath: path] ?? (SyncSiteSetting.followTheNewerRecord.contains(name) ? false : nil)
        }
        try db.execute(
            sql: """
            INSERT INTO siteSettings (host, updatedAt, \(names.joined(separator: ", ")))
            VALUES (?, ?, \(names.map { _ in "?" }.joined(separator: ", ")))
            ON CONFLICT(host) DO UPDATE SET updatedAt = excluded.updatedAt,
            \(names.map { "\($0) = excluded.\($0)" }.joined(separator: ", "))
            """,
            arguments: StatementArguments([site.host, Date()] + values)
        )
        return .applied
    }

    /// Only the mirror: `UserDefaults` is the app's to write (`DefaultsSync`).
    private static func writeSetting(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard let setting = SyncMapping.setting(from: record) else { return .skipped }
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncedDefaults (key, value, modifiedAt) VALUES (?, ?, ?)",
            arguments: [setting.key, setting.value, Date()]
        )
        return .applied
    }

    /// The place is upserted without counting a visit: `visitCount` is this Mac's.
    private static func writeHistory(_ record: SyncRecord, _ db: Database) throws -> Outcome {
        guard let entry = SyncMapping.historyEntry(from: record) else { return .skipped }
        let origin = record.recordName
        try db.execute(sql: "DELETE FROM visits WHERE syncOrigin = ?", arguments: [origin])
        let known = Set(try UUID.fetchAll(db, sql: "SELECT id FROM spaces"))
        let visits = entry.visits.filter { known.contains($0.spaceID) }
        guard let newest = visits.map(\.at).max() else { return .applied }
        let placeID = try Int64.fetchOne(
            db,
            sql: """
            INSERT INTO places (url, host, title, lastVisit, visitCount) VALUES (?, ?, ?, ?, 0)
            ON CONFLICT(url) DO UPDATE SET
                title = CASE WHEN places.title = '' THEN excluded.title ELSE places.title END,
                lastVisit = MAX(places.lastVisit, excluded.lastVisit)
            RETURNING id
            """,
            arguments: [entry.url.absoluteString, entry.url.host() ?? "", entry.title, newest]
        )
        for visit in visits {
            try db.execute(
                sql: "INSERT INTO visits (placeId, at, type, spaceID, syncOrigin) VALUES (?, ?, ?, ?, ?)",
                arguments: [placeID, visit.at, visit.kind, visit.spaceID, origin]
            )
        }
        return .applied
    }
}
