import Foundation
import GRDB

/// One row of §9.3's adaptive input history: a string the user typed, and the URL
/// they chose while it was on screen.
public struct InputHistoryEntry: Sendable, Hashable {
    public var typed: String
    public var url: URL
    /// §9.3: bumped by `useCount * 0.9 + 1` on each use, so it converges on 10.
    public var useCount: Double

    public init(typed: String, url: URL, useCount: Double) {
        self.typed = typed
        self.url = url
        self.useCount = useCount
    }
}

// §11.1 created `inputHistory` in v1 and nothing read it. This is its reader and
// its writer, and the whole of the store's involvement in §9.3's adaptive half.
//
// The `useCount` arithmetic is deliberately not here. §9.3's recurrence is a
// ranking rule, it lives with the rest of the ranking in `UI/CommandBar`, and it
// is applied against an in-memory copy of this table — because §9.7 gives the
// Command Bar one frame per keystroke and that is not enough to ask SQLite. The
// table is small (one row per string the user actually typed and chose from), so
// the Command Bar loads it once and writes through.
public extension BrowserStore {

    /// One Space's lessons. Called once when the Command Bar first opens.
    ///
    /// Scoped since `v8`: an adaptive match ranks above everything else in the
    /// bar, so a lesson learned in one Space would put the other Space's page at
    /// the top of the list on the first keystroke (§9.2, §9.3).
    func inputHistory(inSpace spaceID: UUID) async throws -> [InputHistoryEntry] {
        try await pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT i.typed AS typed, p.url AS url, i.useCount AS useCount
                FROM inputHistory i JOIN places p ON p.id = i.placeId
                WHERE i.spaceID = ?
                """,
                arguments: [spaceID]
            ).compactMap { row in
                let text: String = row["url"]
                guard let url = URL(string: text) else { return nil }
                return InputHistoryEntry(typed: row["typed"], url: url, useCount: row["useCount"])
            }
        }
    }

    /// Persists one pair's use count.
    ///
    /// Creates the `places` row when the chosen URL has never been visited: the
    /// choice happens before the navigation it starts, so on the first pick there
    /// is nothing for `inputHistory.placeId` to reference yet. A place with no
    /// visits is in no Space's history, so this cannot promote anything on its own.
    func setInputUseCount(typed: String, url: URL, useCount: Double, inSpace spaceID: UUID) async throws {
        try await pool.write { db in
            let placeID = try Int64.fetchOne(
                db,
                sql: """
                INSERT INTO places (url, host, title, lastVisit, visitCount) VALUES (?, ?, '', ?, 0)
                ON CONFLICT(url) DO UPDATE SET url = places.url
                RETURNING id
                """,
                arguments: [url.absoluteString, url.host() ?? "", Date()]
            )
            guard let placeID else { return }
            try db.execute(
                sql: """
                INSERT INTO inputHistory (typed, placeId, spaceID, useCount) VALUES (?, ?, ?, ?)
                ON CONFLICT(typed, placeId, spaceID) DO UPDATE SET useCount = excluded.useCount
                """,
                arguments: [typed, placeID, spaceID, useCount]
            )
        }
    }
}
