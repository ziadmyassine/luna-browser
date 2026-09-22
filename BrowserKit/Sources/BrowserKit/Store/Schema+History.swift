//
//  Schema+History.swift
//  BrowserKit
//
//  `v8`, which is the migration that gave history a Space. It lives beside the
//  rest of the schema rather than inside it because `Schema` is at SwiftLint's
//  type-body limit and a migration is a self-contained lump of SQL.
//

import Foundation
import GRDB

extension Schema {

    /// `v8` — a visit remembers the Space it happened in, and so does an adaptive
    /// lesson (§9.2, §9.3).
    ///
    /// `v7` gave every Space its own cookie jar, which made the leak this closes
    /// visible: you are signed into one account in Work and another in Personal,
    /// and the Command Bar was still offering every Space's history to both. A
    /// jar that holds your logins and a history that names them are the same
    /// secret told two ways.
    ///
    /// Everything already on disk was recorded while history was one shared pile,
    /// and nothing in it says where it came from. It is given to the first Space
    /// in the sidebar, which is where a database that has only ever had one Space
    /// did all of its browsing, and is the only answer that does not throw the
    /// history away. A second Space starts empty and fills up as it is used.
    ///
    /// `visits.spaceID` is nullable because SQLite will not add a `NOT NULL`
    /// column that references another table, and `ON DELETE SET NULL` because a
    /// deleted Space must not take a year of history down with it. A visit left
    /// without a Space appears in no Space's list, which is the right answer for a
    /// Space that no longer exists.
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
        // The frecency window, now that it is filtered before it is partitioned:
        // one Space's visits to one place, newest first.
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
