import Foundation
import GRDB

// The `syncedDefaults` mirror of the allowlisted `UserDefaults` keys (docs/SYNC-PLAN.md §5).
// The triggers on it fill the outbox, so a setting is queued like any row; the app owns the
// allowlist and the defaults themselves (`SyncedDefaults`).

extension BrowserStore {

    /// Brings the mirror to `values`, this Mac's allowlisted keys as property lists. A key
    /// the mirror has and `values` lacks was removed, and its record goes. An unchanged
    /// value writes nothing, which is what keeps an applied incoming value from echoing.
    public func recordSyncedDefaults(_ values: [String: Data]) async throws {
        try await pool.write { db in
            for key in try String.fetchAll(db, sql: "SELECT key FROM syncedDefaults") where values[key] == nil {
                try db.execute(sql: "DELETE FROM syncedDefaults WHERE key = ?", arguments: [key])
            }
            for (key, value) in values {
                try db.execute(
                    sql: """
                    INSERT INTO syncedDefaults (key, value, modifiedAt) VALUES (?, ?, ?)
                    ON CONFLICT (key) DO UPDATE SET value = excluded.value, modifiedAt = excluded.modifiedAt
                    WHERE value IS NOT excluded.value
                    """,
                    arguments: [key, value, Date()]
                )
            }
        }
    }

    /// Applies incoming Setting records to the mirror like any other record, and returns
    /// each touched key's value afterwards (nil: removed) for the app to write. A key
    /// whose newer local edit won keeps, and returns, its own value.
    public func applyRemoteSettings(_ changes: SyncChangeSet) async throws -> [(key: String, value: Data?)] {
        let isFirstFetch = try await syncMeta(SyncMetaKey.fetchedOnce) == nil
        try await applyRemote(changes, isFirstFetch: isFirstFetch)
        let keys = changes.modifications.map(\.recordName) + changes.deletions.map(\.recordName)
        return try await pool.read { db in
            try keys.map { key in
                (key, try Data.fetchOne(db, sql: "SELECT value FROM syncedDefaults WHERE key = ?", arguments: [key]))
            }
        }
    }
}
