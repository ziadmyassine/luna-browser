import Foundation
import GRDB

/// One local change waiting to be sent (docs/SYNC-PLAN.md §1).
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
