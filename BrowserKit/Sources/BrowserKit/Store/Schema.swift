import Foundation
import GRDB

// The model types persist themselves. GRDB drives `Codable`, so every column name below
// must match a property name exactly — including `order`, which is a SQL keyword and is
// quoted wherever it appears in hand-written SQL.
extension Profile: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "profiles"
}

extension Space: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "spaces"
}

extension Tab: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tabs"
}

/// The database schema (§11.1), versioned from day one.
///
/// Every change ships as a new `registerMigration` block, never as an edit to `v1`:
/// retrofitting migrations onto a database that already exists on someone's Mac is misery.
enum Schema {

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createProfilesSpacesTabs(db)
            try createHistory(db)
            try createCommandBarAndSiteSettings(db)
        }
        migrator.registerMigration("v2") { db in
            try scopeFavoritesToProfiles(db)
        }
        return migrator
    }

    /// `v2` — Favorites move from per-Space to per-Profile (§2, decision D-S2).
    ///
    /// Specified by the session layer, implemented here. A Favorite is a logged-in app tile,
    /// so it belongs to the cookie jar that holds the login, not to the tab list it happens
    /// to have been created in. Arc keys its Favorites container by profile
    /// (`topAppsContainerIDs`) and this is the same key.
    ///
    /// **Nothing in this migration deletes a row.** The cap trim *demotes* overflow to
    /// `pinned` instead, because two Spaces on one Profile pool their favourites and a user
    /// who has never seen a cap should not lose tiles to one being introduced.
    ///
    /// Safely re-runnable. GRDB records `v2` and runs each migration inside a transaction, so
    /// a half-applied migration cannot be committed — but the column add is still guarded on
    /// the live schema and every statement below is idempotent on its own, because "this can
    /// only run once" is a promise about the migrator, not about the file on disk.
    static func scopeFavoritesToProfiles(_ db: Database) throws {
        let existing = try db.columns(in: "tabs").map(\.name)
        if !existing.contains("profileID") {
            // `ON DELETE CASCADE`: a Favorite cannot outlive the cookie jar that holds its
            // login — the tile would open a logged-out page in a profile that no longer exists.
            try db.execute(sql: """
            ALTER TABLE tabs ADD COLUMN profileID BLOB REFERENCES profiles(id) ON DELETE CASCADE
            """)
        }
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS tabs_on_profileID ON tabs(profileID)")

        // A favourite belongs to the Profile of the Space it was created in. That Space is
        // still its home `spaceID` afterwards; only the *scope* has changed.
        try db.execute(sql: """
        UPDATE tabs
           SET profileID = (SELECT profileID FROM spaces WHERE spaces.id = tabs.spaceID)
         WHERE kind = 'essential' AND profileID IS NULL
        """)
        // Nothing else carries one. `pinned` stays per Space and `today` is per Space by
        // definition, so a stray value here would be a second, disagreeing source of truth.
        try db.execute(sql: "UPDATE tabs SET profileID = NULL WHERE kind <> 'essential'")

        // Arc caps Favorites at 12 per Profile. Pooling two Spaces' favourites can exceed it,
        // so keep the twelve most recently active and demote the rest to pinned tabs in the
        // Space they already live in. Demote, never delete: §13.7's whole argument is that
        // this is the cheap place to beat Vivaldi, which closes tabs with no undo.
        //
        // **`archivedAt IS NULL` appears twice, and both are load-bearing.**
        //
        // An archived Favorite is a reachable state, not a theoretical one: §2 says Favorites
        // never *auto*-archive, but `deleteSpace(_:policy: .archiveTabs)` archives one when its
        // Profile has no other Space left to home it in. So:
        //
        //   · in the ranking, so an archived tile cannot displace a live one out of the twelve;
        //   · in the outer `WHERE`, because without it an archived row falls out of the ranked
        //     set and is therefore caught by `NOT IN` and silently demoted — the filter that
        //     protects it from being counted would be the very thing that demotes it.
        //
        // This also makes the SQL agree with the runtime, which is the real requirement: the
        // session holds archived tabs in `session.archived` rather than in `TabList`, so
        // `favorites(onProfile:)` already never counts them. A migration that disagreed with
        // the code reading its output is worse than either rule on its own.
        try db.execute(sql: """
        UPDATE tabs SET kind = 'pinned', profileID = NULL
         WHERE kind = 'essential'
           AND archivedAt IS NULL
           AND id NOT IN (
             SELECT id FROM (
               SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY profileID ORDER BY lastActiveAt DESC, createdAt DESC
                          ) AS tier
                 FROM tabs WHERE kind = 'essential' AND archivedAt IS NULL
             ) WHERE tier <= 12
           )
        """)
        // The demotion leaves gaps in `order` within the Space it demoted into. `TabList`
        // renumbers on load, exactly as `spaces()` does, so a gap is not a defect here.
    }

    private static func createProfilesSpacesTabs(_ db: Database) throws {
        try db.create(table: "profiles") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull()
            // Unique: two profiles sharing one WKWebsiteDataStore is not isolation (§5.1).
            table.column("dataStoreIdentifier", .blob).notNull().unique()
        }

        try db.create(table: "spaces") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull()
            table.column("symbolName", .text).notNull()
            table.column("gradient", .jsonText).notNull()
            table.column("profileID", .blob).notNull().references("profiles")
            table.column("order", .integer).notNull().defaults(to: 0)
        }

        try db.create(table: "tabs") { table in
            table.primaryKey("id", .blob)
            // Cascade: `delete(spaceID:)` is one statement, and the tabs cannot outlive it.
            table.column("spaceID", .blob).notNull().indexed().references("spaces", onDelete: .cascade)
            table.column("kind", .text).notNull()
            table.column("url", .text).notNull()
            table.column("title", .text).notNull()
            table.column("faviconKey", .text)
            table.column("themeColor", .jsonText)
            table.column("createdAt", .datetime).notNull()
            table.column("lastActiveAt", .datetime).notNull()
            table.column("archivedAt", .datetime)
            // A child outliving its parent is fine; it just stops being indented (§6.5).
            table.column("parentTabID", .blob).references("tabs", onDelete: .setNull)
            table.column("interactionState", .blob)
            table.column("hasUnread", .boolean).notNull().defaults(to: false)
            table.column("order", .integer).notNull().defaults(to: 0)
        }

        // §11.1 lists `archive` alongside `tabs`. It is a view, not a table: an archived tab
        // is still a tab (§6.3 keeps its title/url/favicon), and a second copy of that row is
        // a second truth to keep in sync. `⌘⇧A` (§6.4) reads this.
        try db.execute(sql: "CREATE VIEW archive AS SELECT * FROM tabs WHERE archivedAt IS NOT NULL")
    }

    private static func createHistory(_ db: Database) throws {
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

    private static func createCommandBarAndSiteSettings(_ db: Database) throws {
        // §9.3 adaptive input history: (typed string → chosen URL), use_count = use_count * 0.9 + 1.
        // The table lands in v1 because migrations are cheap to write and expensive to retrofit;
        // nothing reads it until the Command Bar does.
        try db.create(table: "inputHistory") { table in
            table.column("typed", .text).notNull()
            table.column("placeId", .integer).notNull().references("places", onDelete: .cascade)
            table.column("useCount", .double).notNull().defaults(to: 0)
            table.primaryKey(["typed", "placeId"])
        }

        try db.create(table: "siteSettings") { table in
            table.primaryKey("host", .text)
            table.column("zoom", .double).notNull().defaults(to: 1)
            table.column("updatedAt", .datetime).notNull()
        }
    }
}
