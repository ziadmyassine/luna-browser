import Foundation
import GRDB

// Favorites, scoped per Profile (§2, decision D-S2, schema `v2`).
//
// The tier the user calls Favorites is `.essential`, and it is the one tier that is not
// owned by a Space. A Favorite is a logged-in app tile: it belongs to the cookie jar that
// holds the login, so every Space sharing a Profile shares its Favorites, and a Space on a
// different Profile sees none of them. Arc keys its Favorites container the same way —
// `topAppsContainerIDs` is a flat profile → container pair.

public extension BrowserStore {

    /// Arc's cap, and Luna's: twelve Favorites per Profile, and zero is allowed.
    ///
    /// The cap is not arithmetic for its own sake. Arc had to retrofit lazy loading —
    /// "We used to keep your Favorites loaded at all times" — because a permanently
    /// resident global tier is a memory problem.
    static let favoritesCap = 12

    /// Every live Favorite on a Profile, across all of its Spaces, in display order.
    ///
    /// Archived ones are excluded, matching both the session — which keeps archived tabs in
    /// its archive rather than in `TabList` — and `v2`'s cap trim. A Favorite can be archived:
    /// `deleteSpace(_:policy: .archiveTabs)` archives one whose Profile has no other Space
    /// left to home it in. It is still a Favorite, it is just not on the shelf right now, so
    /// it neither shows up here nor counts against ``favoritesCap``.
    func favorites(onProfile profileID: UUID) async throws -> [Tab] {
        try await pool.read { db in
            try Tab.fetchAll(
                db,
                sql: #"""
                SELECT * FROM tabs
                WHERE profileID = ? AND kind = 'essential' AND archivedAt IS NULL
                ORDER BY "order", createdAt
                """#,
                arguments: [profileID]
            )
        }
    }
}

// MARK: - Test seams
//
// Internal, reachable only through `@testable import`. The migration they exercise is the one
// thing in this milestone that touches the owner's real data, so it is worth being able to
// replay it, inspect the live schema, and read every row back including the archived ones.

extension BrowserStore {

    /// Replays `v2`'s statements against an already-migrated database, to prove they are
    /// idempotent rather than merely recorded as having run.
    func rerunFavoritesMigration() async throws {
        try await pool.write { db in try Schema.scopeFavoritesToProfiles(db) }
    }

    func tabColumnNames() async throws -> [String] {
        try await pool.read { db in try db.columns(in: "tabs").map(\.name) }
    }

    func indexNames(on table: String) async throws -> [String] {
        try await pool.read { db in try db.indexes(on: table).map(\.name) }
    }

    func allTabsForTesting() async throws -> [Tab] {
        try await pool.read { db in try Tab.fetchAll(db, sql: "SELECT * FROM tabs") }
    }

    /// Reads through the `archive` view, not the table, so a schema change that the view
    /// fails to pick up shows up as a test failure rather than as a decode crash in the app.
    func archivedTabsForTesting() async throws -> [Tab] {
        try await pool.read { db in try Tab.fetchAll(db, sql: "SELECT * FROM archive") }
    }

    /// Puts a v1-shaped row back: `profileID` unset everywhere, as it is before `v2` runs.
    func clearTabProfileIDs() async throws {
        try await pool.write { db in try db.execute(sql: "UPDATE tabs SET profileID = NULL") }
    }
}
