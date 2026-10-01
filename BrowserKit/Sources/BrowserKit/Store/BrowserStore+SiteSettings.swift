import Foundation
import GRDB

/// The per-site choices that are about how Luna shows a site rather than what the site
/// may do: §18.2's zoom. They live in the `siteSettings` row beside the shared answers
/// and hold in every Space, the way a site's text size does not change with who is
/// signed in to it.
extension BrowserStore {

    /// Every site with a zoom of its own. `zoom` is `NOT NULL DEFAULT 1` since `v1`, so
    /// 1 is what "no zoom of its own" looks like in the table.
    public func siteZooms() async throws -> [String: Double] {
        try await pool.read { db in
            var result: [String: Double] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT host, zoom FROM siteSettings WHERE zoom != 1") {
                result[row["host"]] = row["zoom"]
            }
            return result
        }
    }

    /// Nil goes back to 1 rather than deleting the row, which may carry other answers.
    /// A site with no row and no zoom is left without one.
    public func setSiteZoom(_ zoom: Double?, host: String) async throws {
        try await pool.write { db in
            guard let zoom else {
                try db.execute(
                    sql: "UPDATE siteSettings SET zoom = 1, updatedAt = ? WHERE host = ? AND zoom != 1",
                    arguments: [Date(), host]
                )
                return
            }
            try db.execute(
                sql: """
                INSERT INTO siteSettings (host, updatedAt, zoom) VALUES (?, ?, ?)
                ON CONFLICT(host) DO UPDATE SET zoom = excluded.zoom, updatedAt = excluded.updatedAt
                """,
                arguments: [host, Date(), zoom]
            )
        }
    }
}
