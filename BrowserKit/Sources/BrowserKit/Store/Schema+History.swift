//
//  Schema+History.swift
//  BrowserKit
//
//  History's tables: `v1`'s, and `v8`, the migration that gave history a Space.
//  Beside the rest of the schema rather than inside it because `Schema` is at
//  SwiftLint's type-body limit and a migration is a self-contained lump of SQL.
//

import Foundation
import GRDB

extension Schema {

    /// `v1`'s history: pages, visits to them, and the index over both.
    static func createHistory(_ db: Database) throws {
        try db.create(table: "places") { table in
            // INTEGER PRIMARY KEY, i.e. the rowid — FTS5 external content indexes it directly.
            table.autoIncrementedPrimaryKey("id")
            table.column("url", .text).notNull().unique()
            table.column("host", .text).notNull().indexed()
            table.column("title", .text).notNull().defaults(to: "")
            table.column("lastVisit", .datetime).notNull().indexed()
            table.column("visitCount", .integer).notNull().defaults(to: 0)
        }
        // §9.3 ranks from the 10 most recent visits per place, so frecency is derived from
        // this table rather than cached on `places`. A stored score is a score that goes stale.

        try db.create(table: "visits") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("placeId", .integer).notNull().references("places", onDelete: .cascade)
            table.column("at", .datetime).notNull()
            table.column("type", .text).notNull()
            table.column("fromVisitId", .integer).references("visits", onDelete: .setNull)
        }
        // Exactly the access pattern of the frecency window: partition by place, newest first.
        try db.create(index: "visits_on_placeId_at", on: "visits", columns: ["placeId", "at"])

        // §11.2. `synchronize` installs the triggers that keep the index honest; without it
        // every write path has to remember to reindex, and one day one of them will not.
        try db.create(virtualTable: "placeSearch", using: FTS5()) { table in
            table.synchronize(withTable: "places")
            table.column("title")
            table.column("url")
        }
    }

    /// `v8` — a visit remembers the Space it happened in, and so does an adaptive
    /// lesson (§9.2, §9.3). With a cookie jar per Space (`v7`), a history shared
    /// across Spaces tells one Space which accounts another is signed into.
    ///
    /// Rows already on disk say nothing about where they came from, so they go
    /// to the first Space in the sidebar: where a single-Space database did all
    /// its browsing, and the only answer that keeps the history.
    ///
    /// `visits.spaceID` is nullable because SQLite will not add a `NOT NULL`
    /// column that references another table, and `ON DELETE SET NULL` because a
    /// deleted Space must not take a year of history down with it. A visit left
    /// without a Space appears in no Space's list.
    static func giveEverySpaceItsOwnHistory(_ db: Database) throws {
        let home = try UUID.fetchOne(db, sql: #"SELECT id FROM spaces ORDER BY "order", name LIMIT 1"#)
        try scopeVisitsToASpace(db, home: home)
        try scopeAdaptiveHistoryToASpace(db, home: home)
    }

    private static func scopeVisitsToASpace(_ db: Database, home: UUID?) throws {
        guard try !db.columns(in: "visits").map(\.name).contains("spaceID") else { return }
        try db.execute(sql: "ALTER TABLE visits ADD COLUMN spaceID BLOB REFERENCES spaces(id) ON DELETE SET NULL")
        if let home {
            try db.execute(sql: "UPDATE visits SET spaceID = ?", arguments: [home])
        }
        // The frecency window, filtered by Space before it is partitioned: one
        // Space's visits to one place, newest first.
        try db.create(index: "visits_on_spaceID_placeId_at", on: "visits", columns: ["spaceID", "placeId", "at"])
    }

    /// Rebuilt rather than altered: the Space joins the primary key, so the same
    /// string typed in two Spaces is two lessons, and SQLite cannot add a column
    /// to a key in place.
    private static func scopeAdaptiveHistoryToASpace(_ db: Database, home: UUID?) throws {
        guard try !db.columns(in: "inputHistory").map(\.name).contains("spaceID") else { return }
        try db.create(table: "inputHistoryV8") { table in
            table.column("typed", .text).notNull()
            table.column("placeId", .integer).notNull().references("places", onDelete: .cascade)
            table.column("spaceID", .blob).notNull().references("spaces", onDelete: .cascade)
            table.column("useCount", .double).notNull().defaults(to: 0)
            table.primaryKey(["typed", "placeId", "spaceID"])
        }
        if let home {
            try db.execute(
                sql: """
                INSERT INTO inputHistoryV8 (typed, placeId, spaceID, useCount)
                SELECT typed, placeId, ?, useCount FROM inputHistory
                """,
                arguments: [home]
            )
        }
        try db.drop(table: "inputHistory")
        try db.rename(table: "inputHistoryV8", to: "inputHistory")
    }
}
