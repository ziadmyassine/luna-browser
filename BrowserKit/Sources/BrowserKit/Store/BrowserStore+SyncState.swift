import Foundation
import GRDB

// The coordinator's reads and writes of sync bookkeeping (docs/SYNC-PLAN.md §1, v12
// tables), and building an outgoing record from the row it stands for. Apart from
// `BrowserStore+Sync.swift`, which is the incoming half.

extension BrowserStore {

    // MARK: syncMeta

    func syncMeta(_ key: String) async throws -> Data? {
        try await pool.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncMeta WHERE key = ?", arguments: [key])
        }
    }

    func setSyncMeta(_ key: String, _ value: Data?) async throws {
        try await pool.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO syncMeta (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM syncMeta WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Zones and wiping

    func enabledSyncZones() async throws -> Set<SyncZone> {
        try await pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT zone FROM syncZones WHERE enabled").compactMap(SyncZone.init(rawValue:)))
        }
    }

    /// Forgets everything sync knows about the server except the `syncMeta` keys in
    /// `keeping`; every local row stays (§4). With `turningSyncOff`, the zones go too.
    func wipeSyncState(keeping: Set<String>, turningSyncOff: Bool) async throws {
        try await pool.write { db in
            let kept = Array(keeping)
            try db.execute(
                sql: "DELETE FROM syncMeta WHERE key NOT IN (\(kept.map { _ in "?" }.joined(separator: ", ")))",
                arguments: StatementArguments(kept)
            )
            for table in ["syncRecords", "syncOutbox", "syncParked", "syncPresence"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            if turningSyncOff { try db.execute(sql: "DELETE FROM syncZones") }
        }
    }

    /// This Mac's id in record names, made once. Read and made in one write transaction,
    /// so two callers cannot mint two.
    func syncDeviceID() async throws -> UUID {
        try await pool.write { db in
            let value = try Data.fetchOne(db, sql: "SELECT value FROM syncMeta WHERE key = ?", arguments: [SyncMetaKey.deviceID])
            if let id = value.flatMap({ String(bytes: $0, encoding: .utf8) }).flatMap(UUID.init(uuidString:)) { return id }
            let id = UUID()
            try db.execute(
                sql: "INSERT OR REPLACE INTO syncMeta (key, value) VALUES (?, ?)",
                arguments: [SyncMetaKey.deviceID, Data(id.uuidString.utf8)]
            )
            return id
        }
    }

    /// Queues every row of every zone that is on again, as turning it on did. Rows already
    /// queued keep their `changedAt`.
    func reseedSyncZones(forgettingSystemFields: Bool) async throws {
        try await pool.write { db in
            if forgettingSystemFields { try db.execute(sql: "DELETE FROM syncRecords") }
            let zones = try String.fetchAll(db, sql: "SELECT zone FROM syncZones WHERE enabled").compactMap(SyncZone.init(rawValue:))
            for zone in zones {
                for statement in SyncSQL.seed(zone) { try db.execute(sql: statement) }
            }
        }
    }

    // MARK: syncRecords and the outbox

    func storeSystemFields(of record: SyncRecord, localKey: String) async throws {
        guard let systemFields = record.systemFields else { return }
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO syncRecords (recordType, recordName, localKey, zone, systemFields, schemaVersion)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [record.recordType, record.recordName, localKey, record.zone, systemFields, record.schemaVersion]
            )
        }
    }

    func forgetSystemFields(of recordName: String) async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM syncRecords WHERE recordName = ?", arguments: [recordName])
        }
    }

    func storedRecord(named name: String) async throws -> SyncRecord? {
        try await pool.read { db in try Self.storedRecord(name, db) }
    }

    /// The last record the server returned under `name`: its system fields, no fields.
    private static func storedRecord(_ name: String, _ db: Database) throws -> SyncRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM syncRecords WHERE recordName = ?", arguments: [name]).map {
            SyncRecord(
                recordType: $0["recordType"], recordName: name, zone: $0["zone"],
                schemaVersion: $0["schemaVersion"], systemFields: $0["systemFields"]
            )
        }
    }

    /// The type and local key of a record the server has seen.
    func storedKey(of recordName: String) async throws -> (recordType: String, localKey: String)? {
        try await pool.read { db in
            try Row.fetchOne(db, sql: "SELECT recordType, localKey FROM syncRecords WHERE recordName = ?", arguments: [recordName])
                .map { ($0["recordType"], $0["localKey"]) }
        }
    }

    func outboxEntry(_ recordType: String, _ localKey: String) async throws -> SyncOutboxEntry? {
        try await pool.read { db in
            try SyncOutboxEntry.fetchOne(
                db, sql: "SELECT * FROM syncOutbox WHERE recordType = ? AND localKey = ?", arguments: [recordType, localKey]
            )
        }
    }

    /// Clears the row a finished send answered. A save clears it only while `changedAt` is
    /// no later than the `modifiedAt` it went up with: a newer edit still has to go.
    func clearOutbox(_ recordType: String, _ localKey: String, savedAt: Date?) async throws {
        try await pool.write { db in
            if let savedAt {
                try db.execute(
                    sql: "DELETE FROM syncOutbox WHERE recordType = ? AND localKey = ? AND NOT isDelete AND changedAt <= ?",
                    arguments: [recordType, localKey, savedAt]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM syncOutbox WHERE recordType = ? AND localKey = ? AND isDelete",
                    arguments: [recordType, localKey]
                )
            }
        }
    }

    // MARK: Building an outgoing record

    /// The record for a row as it is now, over the last system fields the server sent, with
    /// the outbox row's `changedAt` as its `modifiedAt`. Nil when the row is gone or the
    /// type is not one the store holds.
    func outgoingRecord(
        _ recordType: String, localKey: String, deviceID: UUID, secret: SyncSecret?
    ) async throws -> SyncRecord? {
        try await pool.read { db in
            let modifiedAt = try Date.fetchOne(
                db, sql: "SELECT changedAt FROM syncOutbox WHERE recordType = ? AND localKey = ?", arguments: [recordType, localKey]
            ) ?? Date()
            func stored(_ name: String) throws -> SyncRecord? { try Self.storedRecord(name, db) }
            switch recordType {
            case "Space", "TabGroup", "Tab":
                guard let id = SyncKeys.uuid(fromHex: localKey) else { return nil }
                return try Self.structural(recordType, id, modifiedAt: modifiedAt, stored: stored(id.uuidString), db)
            case "SiteSetting":
                guard let secret, let site = try Self.siteSetting(localKey, db) else { return nil }
                let name = secret.siteRecordName(forHost: localKey)
                return SyncMapping.record(for: site, secret: secret, modifiedAt: modifiedAt, stored: try stored(name))
            case "HistoryEntry":
                guard let entry = try Self.historyEntry(localKey, deviceID: deviceID, db) else { return nil }
                return SyncMapping.record(for: entry, modifiedAt: modifiedAt, stored: try stored(SyncKeys.historyName(deviceID, localKey)))
            case "Setting":
                guard let value = try Data.fetchOne(db, sql: "SELECT value FROM syncedDefaults WHERE key = ?", arguments: [localKey])
                else { return nil }
                let setting = SyncSetting(key: localKey, value: value)
                return SyncMapping.record(for: setting, modifiedAt: modifiedAt, stored: try stored(localKey))
            default:
                return nil
            }
        }
    }

    private static func structural(
        _ type: String, _ id: UUID, modifiedAt: Date, stored: SyncRecord?, _ db: Database
    ) throws -> SyncRecord? {
        switch type {
        case "Space": try Space.fetchOne(db, key: id).map { SyncMapping.record(for: $0, modifiedAt: modifiedAt, stored: stored) }
        case "TabGroup": try TabGroup.fetchOne(db, key: id).map { SyncMapping.record(for: $0, modifiedAt: modifiedAt, stored: stored) }
        default: try Tab.fetchOne(db, key: id).map { SyncMapping.record(for: $0, modifiedAt: modifiedAt, stored: stored) }
        }
    }

    private static func siteSetting(_ host: String, _ db: Database) throws -> SyncSiteSetting? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM siteSettings WHERE host = ?", arguments: [host]) else { return nil }
        var site = SyncSiteSetting(host: host)
        for (name, path) in SyncSiteSetting.flags { site[keyPath: path] = row[name] }
        return site
    }

    /// The newest 10 typed or bookmarked visits this Mac made (§2, `HistoryEntry.visits`).
    private static func historyEntry(_ placeKey: String, deviceID: UUID, _ db: Database) throws -> SyncHistoryEntry? {
        guard let placeID = Int64(placeKey),
              let place = try Row.fetchOne(db, sql: "SELECT url, title FROM places WHERE id = ?", arguments: [placeID]),
              let url = URL(string: place["url"]) else { return nil }
        let visits = try Row.fetchAll(
            db,
            sql: """
            SELECT spaceID, at, type FROM visits
            WHERE placeId = ? AND type IN ('typed', 'bookmarked') AND syncOrigin IS NULL AND spaceID IS NOT NULL
            ORDER BY at DESC LIMIT 10
            """,
            arguments: [placeID]
        ).map { SyncHistoryEntry.Visit(spaceID: $0["spaceID"], at: $0["at"], kind: $0["type"]) }
        guard !visits.isEmpty else { return nil }
        return SyncHistoryEntry(deviceID: deviceID, placeID: placeID, url: url, title: (place["title"] as String?) ?? "", visits: visits)
    }
}

/// The `syncMeta` keys (docs/SYNC-PLAN.md §1, v12 tables).
enum SyncMetaKey {
    /// `CKSyncEngine.State.Serialization`, rewritten on every state update.
    static let engineState = "engineState"
    static let deviceID = "deviceID"
    /// The account the state belongs to; another one signing in is a switch (§4).
    static let userRecordName = "userRecordName"
    static let lastSyncedAt = "lastSyncedAt"
    static let secret = "secret"
    /// Set when a fetch first completes; until then an apply is the turn-on fetch (§3).
    static let fetchedOnce = "fetchedOnce"
}

/// Outbox keys ↔ record names (docs/SYNC-PLAN.md §1, Record IDs).
enum SyncKeys {

    /// SQLite's `hex(id)` of a UUID blob, which the triggers key rows by.
    static func uuid(fromHex hex: String) -> UUID? {
        guard hex.count == 32 else { return nil }
        var dashed = hex
        for offset in [20, 16, 12, 8] { dashed.insert("-", at: dashed.index(dashed.startIndex, offsetBy: offset)) }
        return UUID(uuidString: dashed)
    }

    static func historyName(_ deviceID: UUID, _ placeKey: String) -> String {
        "\(deviceID.uuidString)-\(placeKey)"
    }

    /// The record name for an outbox row, or nil while it cannot be named: a site record
    /// before the secret has settled.
    static func recordName(_ entry: SyncOutboxEntry, deviceID: UUID, secret: SyncSecret?) -> String? {
        switch entry.recordType {
        case "Space", "TabGroup", "Tab": uuid(fromHex: entry.localKey)?.uuidString
        case "SiteSetting": secret?.siteRecordName(forHost: entry.localKey)
        case "HistoryEntry": historyName(deviceID, entry.localKey)
        default: entry.localKey
        }
    }
}
