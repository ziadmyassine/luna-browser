//
//  BrowserStore+HistoryDeletion.swift
//  BrowserKit
//
//  Taking pages out of one Space's history (§11.3): chosen pages, a span of
//  time, or every page of one site.
//
//  A page is a `places` row every Space shares, and a Space's history is its
//  visits to it, so deleting history is deleting visits. What hangs off them
//  goes in the same transaction: the adaptive lessons (§9.3) that would keep a
//  deleted page at the top of the Command Bar, and the place itself once
//  nothing refers to it, which takes its title and address out of the search
//  index. Sync hears about it through `sync_visits_delete` (`SyncSQL`).
//

import Foundation
import GRDB

public extension BrowserStore {

    /// Every visit this Space made to these pages.
    func deleteHistory(of urls: [URL], inSpace spaceID: UUID) async throws {
        guard !urls.isEmpty else { return }
        let addresses = urls.map(\.absoluteString)
        try await deleteVisits(inSpace: spaceID) { _ in
            (
                "placeId IN (SELECT id FROM places WHERE url IN (\(databaseQuestionMarks(count: addresses.count))))",
                StatementArguments(addresses)
            )
        }
    }

    /// The Space's visits from `start` on, or all of them when `start` is nil.
    func deleteHistory(since start: Date?, inSpace spaceID: UUID) async throws {
        try await deleteVisits(inSpace: spaceID) { _ in
            guard let start else { return ("1", StatementArguments()) }
            return ("at >= ?", StatementArguments([start]))
        }
    }

    /// Every visit this Space made to any page of `site` — a registrable
    /// domain, as ``PublicSuffix/siteKey(forHost:)`` gives it — subdomains
    /// included, so forgetting `apple.com` takes `developer.apple.com` too.
    ///
    /// The hosts are matched in Swift rather than with `LIKE '%.' || site`:
    /// the suffix rule is the one that decides what a site is everywhere else
    /// (§14.3), and `LIKE` has its own ideas about `_` and case.
    func deleteHistory(ofSite site: String, inSpace spaceID: UUID) async throws {
        let site = site.lowercased()
        try await deleteVisits(inSpace: spaceID) { db in
            let hosts = try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT p.host FROM places p
                WHERE EXISTS (SELECT 1 FROM visits v WHERE v.placeId = p.id AND v.spaceID = ?)
                """,
                arguments: [spaceID]
            ).filter { PublicSuffix.siteKey(forHost: $0) == site }
            guard !hosts.isEmpty else { return nil }
            return (
                "placeId IN (SELECT id FROM places WHERE host IN (\(databaseQuestionMarks(count: hosts.count))))",
                StatementArguments(hosts)
            )
        }
    }

    /// Deletes the Space's visits that `condition` picks, then tidies what
    /// they leave behind.
    ///
    /// Flushes first: a visit still in the buffer would land after the delete
    /// and put back the page that was just taken out.
    ///
    /// The places touched go through a temporary table rather than an `IN`
    /// list, because "everything" on an imported history is tens of thousands
    /// of places and SQLite caps the number of bound variables.
    private func deleteVisits(
        inSpace spaceID: UUID,
        where condition: @escaping @Sendable (Database) throws -> (String, StatementArguments)?
    ) async throws {
        try await flush()
        try await pool.write { db in
            guard let (sql, arguments) = try condition(db) else { return }
            let filter = "spaceID = ? AND (\(sql))"
            let bound = StatementArguments([spaceID]) + arguments
            try db.execute(sql: "CREATE TEMP TABLE IF NOT EXISTS touchedPlaces (id INTEGER PRIMARY KEY)")
            try db.execute(sql: "DELETE FROM touchedPlaces")
            try db.execute(sql: "INSERT INTO touchedPlaces SELECT DISTINCT placeId FROM visits WHERE \(filter)", arguments: bound)
            try db.execute(sql: "DELETE FROM visits WHERE \(filter)", arguments: bound)
            try Self.tidyTouchedPlaces(inSpace: spaceID, db)
            try db.execute(sql: "DROP TABLE touchedPlaces")
        }
    }

    /// After a delete: a page the Space no longer has a visit to loses the
    /// Space's lessons for it, a page someone still has keeps a `lastVisit` and
    /// `visitCount` that are true of the visits left, and a page nobody has
    /// goes.
    ///
    /// A lesson goes only with the Space's last visit to the page. Clearing the
    /// last hour should not unlearn a page typed for months; deleting the page
    /// should, or `gi` would go on putting it first in the Command Bar.
    private static func tidyTouchedPlaces(inSpace spaceID: UUID, _ db: Database) throws {
        try db.execute(
            sql: """
            DELETE FROM inputHistory
            WHERE spaceID = ? AND placeId IN (SELECT id FROM touchedPlaces)
              AND NOT EXISTS (SELECT 1 FROM visits v WHERE v.placeId = inputHistory.placeId AND v.spaceID = ?)
            """,
            arguments: [spaceID, spaceID]
        )
        // `visitCount` counts this Mac's visits, as `insert` and `writeHistory` do.
        try db.execute(sql: """
        UPDATE places SET
            lastVisit = (SELECT MAX(at) FROM visits WHERE placeId = places.id),
            visitCount = (SELECT COUNT(*) FROM visits WHERE placeId = places.id AND syncOrigin IS NULL)
        WHERE id IN (SELECT id FROM touchedPlaces)
          AND EXISTS (SELECT 1 FROM visits WHERE placeId = places.id)
        """)
        try db.execute(sql: """
        DELETE FROM places
        WHERE id IN (SELECT id FROM touchedPlaces)
          AND NOT EXISTS (SELECT 1 FROM visits WHERE placeId = places.id)
          AND NOT EXISTS (SELECT 1 FROM inputHistory WHERE placeId = places.id)
        """)
    }
}
