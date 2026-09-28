import Foundation
import GRDB

/// §17.2's per-site exemptions, persisted in `siteSettings` beside the per-site zoom.
/// The two columns are created by `v12` (`Schema.prepareForSync`).
extension BrowserStore {

    public struct BlockingExemptions: Sendable {
        public var blockingDisabled: Set<String> = []
        public var insecureAllowed: Set<String> = []
    }

    public func blockingExemptions() async throws -> BlockingExemptions {
        try await pool.read { db in
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
}
