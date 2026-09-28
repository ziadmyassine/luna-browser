import Foundation
import GRDB

// §6.4's History: every page the Space has visited, newest first, the way a
// browser's history page reads. The Command Bar asks the same tables a
// different question — which page the user most likely means — and ranks by
// frecency (`searchHistory`); this one is a log, so it is ordered by time.
public extension BrowserStore {

    /// The pages visited in `spaceID`, one row per page, newest visit first.
    ///
    /// `query` narrows it to pages whose title or address contains every word
    /// as a prefix, through the same index the Command Bar searches (§11.2).
    /// Only visits the user made count: a redirect or an embedded frame is a
    /// page nobody chose to look at, and its row would be noise between the
    /// pages they did.
    ///
    /// `HistoryHit.lastVisit` is the newest visit in this Space, and `score` is
    /// unused.
    func browsingHistory(matching query: String = "", limit: Int, inSpace spaceID: UUID) async throws -> [HistoryHit] {
        // A page visited a moment ago belongs at the top of the list now.
        try? await flush()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed)
        // Punctuation alone matches nothing rather than everything.
        if pattern == nil, !trimmed.isEmpty { return [] }
        let (sql, arguments): (String, StatementArguments) = if let pattern {
            (Self.matchingHistorySQL, [spaceID, pattern.rawPattern, limit])
        } else {
            (Self.recentHistorySQL, [spaceID, limit])
        }
        return try await pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                let text: String = row["url"]
                guard let url = URL(string: text) else { return nil }
                return HistoryHit(url: url, title: row["title"], score: 0, lastVisit: row["lastVisit"])
            }
        }
    }

    /// The visits the user made, as opposed to ones a page made for them.
    private static let chosenVisit = "v.type IN ('typed', 'link', 'bookmarked')"

    /// Every visit in the Space, grouped into pages. Walks the Space's visits
    /// on `visits_on_spaceID_placeId_at`, so its cost is the Space's history
    /// and not every Space's.
    private static let recentHistorySQL = """
    SELECT p.url AS url, p.title AS title, recent.lastVisit AS lastVisit
    FROM (
        SELECT v.placeId AS placeId, MAX(v.at) AS lastVisit
        FROM visits v
        WHERE v.spaceID = ? AND \(chosenVisit)
        GROUP BY v.placeId
        ORDER BY lastVisit DESC
        LIMIT ?
    ) recent
    JOIN places p ON p.id = recent.placeId
    ORDER BY recent.lastVisit DESC
    """

    /// The pages the index matches, each asked for its newest visit in the
    /// Space. A page with none there is in another Space's history and drops.
    private static let matchingHistorySQL = """
    SELECT url, title, lastVisit FROM (
        SELECT p.url AS url, p.title AS title,
               (SELECT MAX(v.at) FROM visits v
                WHERE v.spaceID = ? AND v.placeId = p.id AND \(chosenVisit)) AS lastVisit
        FROM places p JOIN placeSearch ON placeSearch.rowid = p.id
        WHERE placeSearch MATCH ?
    )
    WHERE lastVisit IS NOT NULL
    ORDER BY lastVisit DESC
    LIMIT ?
    """
}
