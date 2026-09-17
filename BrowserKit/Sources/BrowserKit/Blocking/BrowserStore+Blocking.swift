import Foundation
import GRDB

/// §17.2's per-site exemptions, persisted in `siteSettings` beside the per-site zoom.
///
/// The two columns are added here rather than in `Schema.migrator()` because `Store/` is
/// not this milestone's to edit. `ALTER TABLE ... ADD COLUMN` is what a migration would
/// have emitted anyway, and it is idempotent because the column list is checked first.
/// ponytail: fold this into a `v2` migration next time anyone touches `Schema.swift`;
/// until then it is one statement that runs once per process and then never again.
extension BrowserStore {

    public struct BlockingExemptions: Sendable {
        public var blockingDisabled: Set<String> = []
        public var insecureAllowed: Set<String> = []
    }

    public func blockingExemptions() async throws -> BlockingExemptions {
        try await ensureBlockingColumns()
        return try await pool.read { db in
            var result = BlockingExemptions()
            for row in try Row.fetchAll(
                db,
                sql: "SELECT host, blockingDisabled, insecureAllowed FROM siteSettings "
                    + "WHERE blockingDisabled = 1 OR insecureAllowed = 1"
            ) {
                let host: String = row["host"]
                if row["blockingDisabled"] as Bool? == true { result.blockingDisabled.insert(host) }
                if row["insecureAllowed"] as Bool? == true { result.insecureAllowed.insert(host) }
            }
            return result
        }
    }

    public func setBlockingDisabled(_ disabled: Bool, host: String) async throws {
        try await setBlockingFlag(column: "blockingDisabled", value: disabled, host: host)
    }

    public func setInsecureAllowed(_ allowed: Bool, host: String) async throws {
        try await setBlockingFlag(column: "insecureAllowed", value: allowed, host: host)
    }

    private func setBlockingFlag(column: String, value: Bool, host: String) async throws {
        try await ensureBlockingColumns()
        // `zoom` has a NOT NULL default, so the row can be created by the upsert without
        // knowing anything about zoom. The column name is a literal from this file, never
        // user input, so interpolating it is not an injection path.
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO siteSettings (host, updatedAt, \(column)) VALUES (?, ?, ?)
                ON CONFLICT(host) DO UPDATE SET \(column) = excluded.\(column), updatedAt = excluded.updatedAt
                """,
                arguments: [host, Date(), value]
            )
        }
    }

    /// Checked rather than remembered: an extension cannot add stored state to the actor,
    /// and `PRAGMA table_info` is microseconds against the two writes a user ever makes.
    private func ensureBlockingColumns() async throws {
        try await pool.write { db in
            let existing = Set(try db.columns(in: "siteSettings").map(\.name))
            for column in ["blockingDisabled", "insecureAllowed"] where !existing.contains(column) {
                try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN \(column) BOOLEAN NOT NULL DEFAULT 0")
            }
        }
    }
}
