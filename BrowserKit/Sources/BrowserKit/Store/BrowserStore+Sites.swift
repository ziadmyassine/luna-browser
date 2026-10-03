import Foundation
import GRDB

// §9.4's origin autofill: every site a Space has been to, with one page to
// open for it. The Command Bar holds the list in memory and matches the
// start of a host against it on the keystroke itself, because the history
// search cannot answer "which site begins with these letters": it matches a
// word anywhere in a title or an address, and its two dozen best pages for
// `lo` are all `login` pages rather than `localhost`.

/// A site the Space has visited, and the page that stands for it.
public struct VisitedSite: Sendable, Hashable {
    /// The host, lowercased and without `www.` — what a person types for it.
    public var host: String
    /// The registrable domain (`PublicSuffix.siteKey`), so `itslearning`
    /// finds `sdu.itslearning.com`. Nil for a host with none.
    public var domain: String?
    /// The site's front page when it has been visited, else its most visited
    /// page. Firefox's origin autofill opens the front page too: two letters
    /// name a site, not one of its pages.
    public var url: URL
    public var title: String
    /// Σ of §9.3's points over every visit to every page of the site.
    public var score: Double

    public init(host: String, domain: String?, url: URL, title: String, score: Double) {
        self.host = host
        self.domain = domain
        self.url = url
        self.title = title
        self.score = score
    }
}

public extension BrowserStore {

    /// The Space's sites, best first: by the points of the visits the user
    /// typed or bookmarked, then by all of them. Autofill predicts an address
    /// the user is typing, and a site reached by links all day — a feed, a
    /// mail client — is not the one they type. On a real history this put the
    /// right site first for 27 of 30 typed pages at two letters, against 21
    /// when every visit counted the same (docs/PERF.md, §9.3).
    ///
    /// A site qualifies once the user has typed or bookmarked a page of it, or
    /// followed a link to it three times: one link followed months ago is not
    /// a reason to take the top row from the search the user may have meant.
    /// Chrome completes inline only from addresses typed before, for the same
    /// reason.
    func visitedSites(inSpace spaceID: UUID) async throws -> [VisitedSite] {
        try? await flush()
        return try await pool.read { db in
            try Row.fetchAll(db, sql: Self.sitesSQL, arguments: [spaceID]).compactMap { row in
                let text: String = row["url"]
                let host: String = row["site"]
                guard let url = URL(string: text), !host.isEmpty else { return nil }
                return VisitedSite(
                    host: host,
                    domain: PublicSuffix.siteKey(forHost: host),
                    url: url,
                    title: row["title"],
                    score: row["score"]
                )
            }
        }
    }

    /// One row per host, `www.` folded in. `url` and `title` are SQLite's bare
    /// columns from the row that wins the one `MAX()`: the front page if there
    /// is one, else the page with the most points.
    ///
    /// `HAVING` and `ORDER BY` spell their sums out. A bare name there resolves
    /// to the subquery's per-page column before the result's alias, and with
    /// `visits >= 3` written that way every site of more than one page dropped
    /// out.
    private static let sitesSQL = """
    SELECT lower(CASE WHEN p.host LIKE 'www.%' THEN substr(p.host, 5) ELSE p.host END) AS site,
           p.url AS url, p.title AS title, SUM(s.points) AS score,
           MAX((p.url IN ('https://' || p.host || '/', 'http://' || p.host || '/',
                          'https://' || p.host, 'http://' || p.host)) * 1e12 + s.points) AS pick
    FROM (
        SELECT v.placeId AS id, SUM(\(Frecency.points)) AS points,
               SUM(CASE WHEN v.type IN ('typed', 'bookmarked') THEN \(Frecency.points) ELSE 0 END) AS typedPoints,
               SUM(v.type IN ('typed', 'bookmarked')) AS chosen,
               SUM(v.type IN ('typed', 'bookmarked', 'link')) AS visited
        FROM visits v
        WHERE v.spaceID = ?
        GROUP BY v.placeId
    ) s
    JOIN places p ON p.id = s.id
    WHERE p.host <> '' AND (p.url LIKE 'https://%' OR p.url LIKE 'http://%')
    GROUP BY site
    HAVING SUM(s.points) > 0 AND (SUM(s.chosen) > 0 OR SUM(s.visited) >= 3)
    ORDER BY SUM(s.typedPoints) DESC, SUM(s.points) DESC, length(site)
    """
}
