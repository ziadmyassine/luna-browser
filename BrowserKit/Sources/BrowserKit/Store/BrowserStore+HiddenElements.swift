import Foundation
import GRDB

/// The parts of pages the user has hidden for good, one row per site and selector.
///
/// Its own table rather than a column on `siteSettings`: a site has any number of
/// these, and a column holds one answer. Created with `IF NOT EXISTS` on first use, for
/// the reason `BrowserStore+SitePermissions.swift` gives for its columns — one
/// statement per process is cheaper than a schema version for a table nothing else
/// joins against.
extension BrowserStore {

    public struct HiddenElement: Equatable, Sendable {
        /// A CSS selector the page resolved to exactly one element when it was hidden.
        public var selector: String
        /// What the element was, in words, for the row that brings it back.
        public var label: String
        public var hiddenAt: Date

        public init(selector: String, label: String, hiddenAt: Date = Date()) {
            self.selector = selector
            self.label = label
            self.hiddenAt = hiddenAt
        }
    }

    /// Every site's list, oldest first — read once at launch, like the site permissions.
    public func hiddenElements() async throws -> [String: [HiddenElement]] {
        try await ensureHiddenElementsTable()
        return try await pool.read { db in
            var result: [String: [HiddenElement]] = [:]
            for row in try Row.fetchAll(
                db, sql: "SELECT host, selector, label, hiddenAt FROM hiddenElements ORDER BY hiddenAt"
            ) {
                let host: String = row["host"]
                result[host, default: []].append(
                    HiddenElement(selector: row["selector"], label: row["label"], hiddenAt: row["hiddenAt"])
                )
            }
            return result
        }
    }

    public func hideElement(_ element: HiddenElement, host: String) async throws {
        try await ensureHiddenElementsTable()
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO hiddenElements (host, selector, label, hiddenAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(host, selector) DO UPDATE SET label = excluded.label, hiddenAt = excluded.hiddenAt
                """,
                arguments: [host, element.selector, element.label, element.hiddenAt]
            )
        }
    }

    public func restoreElement(selector: String, host: String) async throws {
        try await ensureHiddenElementsTable()
        try await pool.write { db in
            try db.execute(
                sql: "DELETE FROM hiddenElements WHERE host = ? AND selector = ?",
                arguments: [host, selector]
            )
        }
    }

    private func ensureHiddenElementsTable() async throws {
        try await pool.write { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS hiddenElements (
                host TEXT NOT NULL,
                selector TEXT NOT NULL,
                label TEXT NOT NULL,
                hiddenAt DATETIME NOT NULL,
                PRIMARY KEY (host, selector)
            )
            """)
        }
    }
}
