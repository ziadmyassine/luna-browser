import Foundation
import GRDB

/// How a visit happened. The weights in `Frecency` hang off these cases (§9.3), and
/// §31.5 syncs only `.typed` and `.bookmarked` — link visits never leave the Mac.
public enum VisitKind: String, Sendable, Codable {
    case typed, link, bookmarked, redirect, embed
}

/// One ranked history result for the Command Bar (§9.2).
public struct HistoryHit: Sendable, Hashable {
    public var url: URL
    public var title: String
    public var score: Double

    public init(url: URL, title: String, score: Double) {
        self.url = url
        self.title = title
        self.score = score
    }
}

/// Luna's SQLite store: Spaces, tabs and history behind one actor (§11).
///
/// Every method is `async`: the actor delegates straight to GRDB's async pool APIs and
/// suspends rather than blocking, so it hands its executor back and GRDB's own readers
/// run concurrently. A store that blocked its actor thread on SQLite would serialise the
/// whole app behind the slowest query, which is the opposite of the point.
///
/// Visit writes are buffered and flushed as one transaction (§11.5) — `recordVisit` never
/// touches the disk, so navigation never waits on it. Call ``flush()`` before quitting.
public actor BrowserStore {

    // Internal, not private, for exactly one reason: `BrowserStore+InputHistory`
    // is a separate file (§9.3's adaptive history, which nothing in wave 1 read)
    // and a `private` member is file-scoped. Still unreachable outside the module.
    let pool: DatabasePool
    private var pendingVisits: [PendingVisit] = []
    private var flushTask: Task<Void, Never>?

    private struct PendingVisit: Sendable {
        var url: URL
        var title: String
        var kind: VisitKind
        var at: Date
        /// Which Space's history this visit belongs to (§9.2). Nil only for a
        /// visit whose Space is unknown, which nothing in the app produces and
        /// an import of somebody else's history could.
        var spaceID: UUID?
    }

    public init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        pool = try DatabasePool(path: path.path)
        try Schema.migrator().migrate(pool)
    }

    // MARK: - Spaces, tabs

    /// Every Space in display order, with `order` renumbered to `0..<n` when it has drifted.
    ///
    /// The self-heal is the point (§6.2). Every delete leaves a gap and every
    /// insert-in-the-middle leaves a collision; reordering is the biggest hole in the
    /// prior art — Nook persists an index and has no reorder function, Ora has no order
    /// field, Refrax sorts by `position` and never writes it. Renumbering on load makes
    /// a reorder "write the new indices and reload" rather than "and now repair
    /// everything downstream".
    ///
    /// Ties break on name so two rows sharing an `order` renumber deterministically rather
    /// than swapping places on alternate launches.
    ///
    /// The common case stays a pure read: the write only happens when the persisted order
    /// actually differs from `0..<n`.
    public func spaces() async throws -> [Space] {
        let stored = try await pool.read { db in
            try Space.fetchAll(db, sql: #"SELECT * FROM spaces ORDER BY "order", name"#)
        }
        let persisted = try await repairingUnusableIdentifiers(in: stored)
        let healed = persisted.enumerated().map { index, space -> Space in
            var renumbered = space
            renumbered.order = index
            return renumbered
        }
        guard healed != persisted else { return persisted }

        let drifted = healed.filter { space in
            persisted.contains { $0.id == space.id && $0.order != space.order }
        }
        try await pool.write { db in
            for space in drifted { try space.update(db) }
        }
        return healed
    }

    public func tabs(inSpace spaceID: UUID, includeArchived: Bool) async throws -> [Tab] {
        try await pool.read { db in
            try Tab.fetchAll(
                db,
                sql: #"""
                SELECT * FROM tabs
                WHERE spaceID = ? AND (? OR archivedAt IS NULL)
                ORDER BY "order", createdAt
                """#,
                arguments: [spaceID, includeArchived]
            )
        }
    }

    public func upsert(_ tab: Tab) async throws {
        try await pool.write { db in try tab.upsert(db) }
    }

    /// Persists a Space, refusing the one identifier WebKit cannot be handed (§3.1).
    ///
    /// The write side of the all-zero guard. `dataStoreForIdentifier:` throws an Objective-C
    /// exception on a zero UUID and Swift cannot catch it, so the cheapest place to stop a
    /// bad value is before it reaches the disk that a later launch will read it back from.
    public func upsert(_ space: Space) async throws {
        guard space.hasUsableDataStoreIdentifier else {
            throw BrowserStoreError.invalidDataStoreIdentifier(spaceID: space.id)
        }
        try await pool.write { db in
            // The `UNIQUE` index cannot be relied on to raise here: GRDB's upsert names no
            // conflict target, so SQLite answers a collision on any unique index by
            // updating the row it hit — and a duplicate jar would overwrite another Space
            // rather than fail. See `BrowserStoreError.dataStoreIdentifierTaken`.
            let owner = try UUID.fetchOne(
                db,
                sql: "SELECT id FROM spaces WHERE dataStoreIdentifier = ? AND id <> ?",
                arguments: [space.dataStoreIdentifier, space.id]
            )
            if let owner {
                throw BrowserStoreError.dataStoreIdentifierTaken(spaceID: space.id, by: owner)
            }
            try space.upsert(db)
        }
    }

    public func delete(tabID: UUID) async throws {
        _ = try await pool.write { db in try Tab.deleteOne(db, key: tabID) }
    }

    /// Deletes a Space. Its tabs go with it — the foreign key cascades (§11.1).
    public func delete(spaceID: UUID) async throws {
        _ = try await pool.write { db in try Space.deleteOne(db, key: spaceID) }
    }

    /// One default Space, so a first run is never an empty window.
    ///
    /// Asks before it opens a transaction it will not use. Every launch
    /// calls this and every launch but the first has nothing to do, and a
    /// `write` block that decides to do nothing has still taken SQLite's write
    /// lock and paid for a transaction, on a launch that was only ever going to
    /// read two counts. The guard is repeated inside the
    /// write because the read is not the decision: two processes opening the
    /// same fresh database would both see it empty.
    public func seedIfEmpty() async throws {
        let seeded = try await pool.read { db in try Space.fetchCount(db) > 0 }
        guard !seeded else { return }
        try await pool.write { db in
            guard try Space.fetchCount(db) == 0 else { return }
            try Space(
                name: "Personal",
                symbolName: "moon.stars.fill",
                gradient: .defaultSpace
            ).insert(db)
        }
    }

    // MARK: - History

    /// Buffers a visit. Returns immediately; the write lands on the next flush (§11.5).
    ///
    /// - Parameter spaceID: the Space the page was opened in. It decides whose
    ///   history the page joins, and a visit without one joins nobody's — see
    ///   `Schema.giveEverySpaceItsOwnHistory`.
    public func recordVisit(url: URL, title: String, kind: VisitKind, at: Date, inSpace spaceID: UUID?) throws {
        pendingVisits.append(PendingVisit(url: url, title: title, kind: kind, at: at, spaceID: spaceID))
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.flushAfterDelay()
        }
    }

    /// Writes buffered visits now. Call it on quit: a buffered visit is not on disk yet.
    public func flush() async throws {
        flushTask?.cancel()
        flushTask = nil
        try await writePendingVisits()
    }

    /// Ranked history for the Command Bar (§9.2, §9.3). An empty query returns the most
    /// recently visited places, ranked the same way, which is `⌘T`'s opening state.
    ///
    /// - Parameter spaceID: the only Space whose visits count. A page visited in
    ///   another Space is not in this Space's history and does not appear here at
    ///   any rank — the jar that holds the login and the list that names it stay
    ///   together (§9.2).
    public func searchHistory(_ query: String, limit: Int, inSpace spaceID: UUID) async throws -> [HistoryHit] {
        // A URL typed a moment ago has to be rankable now; a failed flush must not also
        // fail the search, which can still answer from what is already on disk.
        try? await flush()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed)
        // A query made only of punctuation tokenizes to nothing. Falling back to "recent"
        // there would answer a typed query with unrelated rows; an empty query is the only
        // thing that earns the recency list.
        if pattern == nil, !trimmed.isEmpty { return [] }
        let sql = Frecency.rankingSQL(candidates: pattern == nil ? Frecency.recentCandidates : Frecency.matchCandidates)
        // Bound in the order the statement reads: the candidate pool's own arguments
        // first, because `WITH candidates AS (…)` comes before the ranking that
        // filters it, then the Space, then the row limit.
        let arguments: StatementArguments = pattern.map { [$0.rawPattern, spaceID, limit] } ?? [spaceID, spaceID, limit]

        return try await pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                let text: String = row["url"]
                guard let url = URL(string: text) else { return nil }
                return HistoryHit(url: url, title: row["title"], score: row["score"])
            }
        }
    }

    // MARK: - Write batching

    private func flushAfterDelay() async {
        flushTask = nil
        try? await writePendingVisits()
    }

    private func writePendingVisits() async throws {
        guard !pendingVisits.isEmpty else { return }
        let batch = pendingVisits
        pendingVisits.removeAll()
        do {
            try await pool.write { db in
                for visit in batch { try Self.insert(visit, into: db) }
            }
        } catch {
            // A broken write must not eat history: put the batch back for the next flush.
            pendingVisits.insert(contentsOf: batch, at: 0)
            throw error
        }
    }

    private static func insert(_ visit: PendingVisit, into db: Database) throws {
        let placeID = try Int64.fetchOne(
            db,
            sql: """
            INSERT INTO places (url, host, title, lastVisit, visitCount) VALUES (?, ?, ?, ?, 1)
            ON CONFLICT(url) DO UPDATE SET
                title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE places.title END,
                lastVisit = MAX(places.lastVisit, excluded.lastVisit),
                visitCount = places.visitCount + 1
            RETURNING id
            """,
            arguments: [visit.url.absoluteString, visit.url.host() ?? "", visit.title, visit.at]
        )
        guard let placeID else { return }
        try db.execute(
            sql: "INSERT INTO visits (placeId, at, type, spaceID) VALUES (?, ?, ?, ?)",
            arguments: [placeID, visit.at, visit.kind.rawValue, visit.spaceID]
        )
    }
}

/// §9.3's ranking, in SQL because it has to rank and truncate before crossing the boundary.
///
/// `score = Σ (visitTypeWeight × recencyWeight)` over a place's 10 most recent visits.
/// The sum is deliberately not averaged: a mean would make one typed visit tie a hundred of
/// them, which is the frequency half of "frecency" thrown away (§9.3's "normalised by
/// sampled visit count" is Firefox's mean × visit_count, and the plain sum says the same
/// thing with less arithmetic).
private enum Frecency {

    /// Firefox-derived visit-type weights; redirect and embed are worth nothing on purpose.
    private static let points = """
    (CASE v.type WHEN 'typed' THEN 200.0 WHEN 'bookmarked' THEN 140.0 WHEN 'link' THEN 120.0 ELSE 0.0 END)
    * (CASE
        WHEN julianday('now') - julianday(v.at) <= 4 THEN 1.0
        WHEN julianday('now') - julianday(v.at) <= 14 THEN 0.7
        WHEN julianday('now') - julianday(v.at) <= 31 THEN 0.5
        WHEN julianday('now') - julianday(v.at) <= 90 THEN 0.3
        ELSE 0.1
      END)
    """

    /// FTS5 over title + URL (§11.2), prefix-matched so it answers mid-keystroke.
    static let matchCandidates = """
    SELECT p.id AS id, p.url AS url, p.title AS title, p.lastVisit AS lastVisit
    FROM places p JOIN placeSearch ON placeSearch.rowid = p.id
    WHERE placeSearch MATCH ?
    """

    /// The empty-query pool. Capped: ranking every place a user ever visited to show ten
    /// rows is work nobody sees.
    ///
    /// Filtered by Space here and not only in the ranking below, because the cap is
    /// what makes it necessary: 200 rows off the top of a shared `lastVisit` can be
    /// 200 rows belonging to the other Space, and `⌘T` would open on nothing.
    static let recentCandidates = """
    SELECT p.id AS id, p.url AS url, p.title AS title, p.lastVisit AS lastVisit
    FROM places p
    WHERE EXISTS (SELECT 1 FROM visits v WHERE v.placeId = p.id AND v.spaceID = ?)
    ORDER BY p.lastVisit DESC LIMIT 200
    """

    /// One index seek per candidate for its ten newest visits in the Space
    /// (`visits_on_spaceID_placeId_at`), not a window over every visit joined
    /// back to the candidates. SQLite cannot index that join, so it rescanned
    /// the whole ranked set for each candidate: a one-letter query matches
    /// most of an imported history, and at 11,000 matches over 71,000 visits
    /// the old form took 384 s for one keystroke where this one takes 45 ms.
    ///
    /// A place with no visit in the Space scores NULL and is dropped, as the
    /// inner join dropped it; one with only zero-point visits keeps its 0.
    static func rankingSQL(candidates: String) -> String {
        """
        WITH candidates AS (\(candidates)),
        scored AS (
            SELECT c.url AS url, c.title AS title, c.lastVisit AS lastVisit,
                   (SELECT SUM(points) FROM (
                        SELECT \(points) AS points
                        FROM visits v
                        WHERE v.spaceID = ? AND v.placeId = c.id
                        ORDER BY v.at DESC
                        LIMIT 10
                   )) AS score
            FROM candidates c
        )
        SELECT url, title, score
        FROM scored
        WHERE score IS NOT NULL
        ORDER BY score DESC, lastVisit DESC
        LIMIT ?
        """
    }
}
