import Foundation
import GRDB

// The model types persist themselves. GRDB drives `Codable`, so every column name below
// must match a property name exactly — including `order`, which is a SQL keyword and is
// quoted wherever it appears in hand-written SQL.
extension Space: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "spaces"
}

extension Tab: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tabs"
}

extension TabGroup: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tabGroups"
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
        migrator.registerMigration("v3") { db in
            try rememberWhereATileWasPinned(db)
        }
        migrator.registerMigration("v4") { db in
            try letTheUserNameATab(db)
        }
        migrator.registerMigration("v5") { db in
            try letTheUserPictureAProfile(db)
        }
        migrator.registerMigration("v6") { db in
            try letTheUserGroupAndSaveTabs(db)
        }
        migrator.registerMigration("v7") { db in
            try giveEverySpaceItsOwnJar(db)
        }
        migrator.registerMigration("v8") { db in
            try giveEverySpaceItsOwnHistory(db)
        }
        // `v9` — `luna://newtab` is gone, so the tabs standing on it are blank
        // tabs and are written as what they are. Rewritten rather than deleted:
        // a closed tab in §6.3's archive is the user's, and a page being
        // removed is not a reason to take one away.
        migrator.registerMigration("v9") { db in
            try db.execute(sql: "UPDATE tabs SET url = 'about:blank' WHERE url = 'luna://newtab'")
        }
        // `v10` — the History page answers to its own name, so the rows still
        // standing on the address it had before it do too. `luna://archive`
        // goes on routing (§4.4), but a row is a label as much as a link and
        // this one would read `archive` under a panel titled History.
        //
        // `v9`'s rewrite again, because once was not enough: a migration runs
        // on the database and an app runs on its own copy of the rows, so an
        // older instance left open across the upgrade wrote its `luna://newtab`
        // back afterwards. Nothing can produce one now, which is what makes
        // repeating it worth doing rather than the first of several.
        migrator.registerMigration("v10") { db in
            try db.execute(sql: "UPDATE tabs SET url = 'luna://history' WHERE url = 'luna://archive'")
            try db.execute(sql: "UPDATE tabs SET url = 'about:blank' WHERE url = 'luna://newtab'")
        }
        return migrator
    }

    /// `v7` — the Profile row goes, and a Space owns its own cookie jar (§9).
    ///
    /// Space → Profile was many-to-one, and nothing in the product wanted the sharing
    /// while everything in it had to explain the sharing: the fan-out line on every card,
    /// the tooltip, three clauses in the delete dialog. One Space, one jar, one name.
    ///
    /// A shared jar is split, and one Space keeps it. Two Spaces on one profile cannot
    /// both go on addressing the same `WKWebsiteDataStore` — that is the sharing this
    /// migration exists to end — so the first by the order they are listed in keeps the
    /// identifier and stays signed in wherever it was, and the others are given fresh jars
    /// and start signed out. There is no third option: the alternative to one of them
    /// keeping it is both of them losing it. Anyone who never shared a profile, which is
    /// everyone who never went looking for the setting, sees nothing change.
    ///
    /// Favorites follow the row they are already on. They were scoped by `tabs.profileID`
    /// and every one of them also carries its home `spaceID`, so the column is dropped
    /// rather than translated: a Favorite belongs to the Space it was made in, which is
    /// what the column would have said anyway once the profile it named held exactly one
    /// Space. Arc's cap of twelve becomes twelve per Space.
    ///
    /// The two table rebuilds are why this reads as SQL rather than as GRDB's table
    /// alterations: `spaces.profileID` is a foreign key into a table that is about to stop
    /// existing, and SQLite carries foreign keys in the table definition. GRDB defers
    /// foreign-key checks to the end of a migration's transaction, which is what lets
    /// `tabs.spaceID` survive its table being replaced underneath it.
    static func giveEverySpaceItsOwnJar(_ db: Database) throws {
        guard try db.tableExists("profiles") else { return }
        try addTheJarColumns(db)
        try splitSharedJars(db)
        try dropTheProfileRow(db)
    }

    private static func addTheJarColumns(_ db: Database) throws {
        let existing = try db.columns(in: "spaces").map(\.name)
        if !existing.contains("dataStoreIdentifier") {
            try db.execute(sql: "ALTER TABLE spaces ADD COLUMN dataStoreIdentifier BLOB")
        }
        if !existing.contains("imageData") {
            try db.execute(sql: "ALTER TABLE spaces ADD COLUMN imageData BLOB")
        }
    }

    /// One jar per Space, minted in Swift because SQLite has no UUID of its own — and
    /// because "the first Space keeps it" is a decision about order, not a join.
    private static func splitSharedJars(_ db: Database) throws {
        var claimed: Set<UUID> = []
        let spaces = try Row.fetchAll(db, sql: #"SELECT id, profileID FROM spaces ORDER BY "order", name"#)
        for space in spaces {
            let id: UUID = space["id"]
            let profileID: UUID = space["profileID"]
            let profile = try Row.fetchOne(
                db,
                sql: "SELECT dataStoreIdentifier, imageData FROM profiles WHERE id = ?",
                arguments: [profileID]
            )
            let inherited: UUID? = profile?["dataStoreIdentifier"]
            // A zero identifier is the one WebKit answers with an uncatchable exception,
            // so it is never inherited — see `Space.hasUsableDataStoreIdentifier`.
            let isFirst = claimed.insert(profileID).inserted
            let jar = isFirst && inherited?.isZero == false ? (inherited ?? UUID()) : UUID()
            let image: Data? = profile?["imageData"]
            try db.execute(
                sql: "UPDATE spaces SET dataStoreIdentifier = ?, imageData = ? WHERE id = ?",
                arguments: [jar, image, id]
            )
        }
    }

    /// The rebuilds. `spaces` loses its foreign key into `profiles`, `tabs` loses the
    /// scope column Favorites no longer need, and the table itself goes.
    private static func dropTheProfileRow(_ db: Database) throws {
        try db.execute(sql: SQL.spacesWithoutAProfile)
        try db.execute(sql: SQL.copyTheSpacesOver)
        try db.execute(sql: "DROP TABLE spaces")
        try db.execute(sql: "ALTER TABLE spaces_v7 RENAME TO spaces")

        try db.execute(sql: "DROP INDEX IF EXISTS tabs_on_profileID")
        if try db.columns(in: "tabs").map(\.name).contains("profileID") {
            try db.execute(sql: "ALTER TABLE tabs DROP COLUMN profileID")
        }
        try db.execute(sql: "DROP TABLE profiles")
    }

    /// The two long statements `dropTheProfileRow` runs, named so the method reads as the
    /// four steps it is.
    private enum SQL {
        static let spacesWithoutAProfile = """
        CREATE TABLE spaces_v7 (
            id BLOB PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            symbolName TEXT NOT NULL,
            gradient TEXT NOT NULL,
            dataStoreIdentifier BLOB NOT NULL UNIQUE,
            imageData BLOB,
            "order" INTEGER NOT NULL DEFAULT 0
        )
        """
        static let copyTheSpacesOver = """
        INSERT INTO spaces_v7 (id, name, symbolName, gradient, dataStoreIdentifier, imageData, "order")
        SELECT id, name, symbolName, gradient, dataStoreIdentifier, imageData, "order" FROM spaces
        """
    }

    /// `v6` — tabs can be grouped, and a saved tab outlives its page (§3.4b).
    ///
    /// One new table and two nullable-or-defaulted columns. No backfill anywhere, and that
    /// is the design: nobody has a group yet, so `groupID` is nil for every row that
    /// existed before this ran, and nobody has closed a saved tab yet, so `isDormant` is
    /// false for all of them.
    ///
    /// The tier itself needs no column. `.pinned` already meant "the run above today's
    /// tabs" and §3.4b only gives it the behaviour its name always claimed — so a user who
    /// had deliberately placed tabs up there finds them saved, which is what putting them
    /// there was for, rather than finding an empty new section and their tabs still below it.
    ///
    /// `ON DELETE SET NULL` on `groupID`, not `CASCADE`. Deleting a group must never delete
    /// pages: ungrouping is the whole of what removing a group means, and the one command
    /// that does end the tabs (`closeGroup`) archives them itself first, in Swift, where it
    /// can be undone.
    ///
    /// Idempotent on the live schema, like every migration above it: the migrator promises
    /// this runs once, the file on disk promises nothing.
    static func letTheUserGroupAndSaveTabs(_ db: Database) throws {
        if try !db.tableExists("tabGroups") {
            try db.create(table: "tabGroups") { table in
                table.primaryKey("id", .blob)
                // A group is a set of tabs inside one Space, and its tabs cascade with
                // the Space already — so the group cannot be the one row that survives it.
                table.column("spaceID", .blob).notNull().indexed().references("spaces", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("symbolName", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("isCollapsed", .boolean).notNull().defaults(to: false)
                table.column("order", .integer).notNull().defaults(to: 0)
            }
        }
        let existing = try db.columns(in: "tabs").map(\.name)
        if !existing.contains("groupID") {
            try db.execute(sql: """
            ALTER TABLE tabs ADD COLUMN groupID BLOB REFERENCES tabGroups(id) ON DELETE SET NULL
            """)
        }
        if !existing.contains("isDormant") {
            try db.execute(sql: "ALTER TABLE tabs ADD COLUMN isDormant BOOLEAN NOT NULL DEFAULT 0")
        }
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS tabs_on_groupID ON tabs(groupID)")
    }

    /// `v5` — a profile carries the picture the user gave it (§9).
    ///
    /// One nullable blob and no backfill: nil means "no picture", which is true
    /// of every profile that existed before the column did, and the glyph on
    /// §3.5's avatar is what nil draws. The bytes are what the sidebar shows
    /// rather than what the user picked — the app crops to a square and
    /// downsamples before it gets here — so a row stays tens of kilobytes and
    /// the picture cannot outlive the profile it belongs to.
    ///
    /// Idempotent on the live schema, like every migration above it: the
    /// migrator promises this runs once, the file on disk promises nothing.
    static func letTheUserPictureAProfile(_ db: Database) throws {
        guard !(try db.columns(in: "profiles").map(\.name).contains("imageData")) else { return }
        try db.execute(sql: "ALTER TABLE profiles ADD COLUMN imageData BLOB")
    }

    /// `v4` — a tab carries the name and the icon the user gave it (§3.4a).
    ///
    /// Two nullable columns and no backfill, which is the whole design. Nil means "the user
    /// has not named this tab" and "the user has not chosen an icon", and the page's own title and
    /// the site's own favicon are the answers — which is true for every tab that existed before
    /// this column did and for every tab opened since. Seeding `customTitle` from `title` would
    /// freeze whatever the page happened to be called at migration time into a name the user never
    /// typed, and the first navigation would leave the row lying about the page it is showing.
    ///
    /// Idempotent on the live schema, like `v2` and `v3`: the migrator promises this runs once,
    /// the file on disk promises nothing.
    static func letTheUserNameATab(_ db: Database) throws {
        let existing = try db.columns(in: "tabs").map(\.name)
        if !existing.contains("customTitle") {
            try db.execute(sql: "ALTER TABLE tabs ADD COLUMN customTitle TEXT")
        }
        if !existing.contains("customSymbolName") {
            try db.execute(sql: "ALTER TABLE tabs ADD COLUMN customSymbolName TEXT")
        }
    }

    /// `v3` — a pinned tile remembers the address it was pinned at (§3.3).
    ///
    /// Nullable, and that is the whole design. Nil means "this tab has no home to go
    /// back to", which is the truth for every tab that is not a tile and for every tile
    /// that existed before this column did. Defaulting it to `url` on the way in would
    /// invent a decision the user never took — the tab's current address is wherever the
    /// site last walked, not the page they chose to keep — so the backfill below sets it
    /// only for rows that are tiles, where "the address it is showing now" is the best
    /// available reading of "the address it was pinned at", and leaves everything else nil.
    ///
    /// Idempotent on the live schema, like `v2`: the migrator promises this runs once, the
    /// file on disk promises nothing.
    static func rememberWhereATileWasPinned(_ db: Database) throws {
        guard !(try db.columns(in: "tabs").map(\.name).contains("pinnedURL")) else { return }
        try db.execute(sql: "ALTER TABLE tabs ADD COLUMN pinnedURL TEXT")
        try db.execute(sql: "UPDATE tabs SET pinnedURL = url WHERE kind = 'essential'")
    }

    /// `v2` — Favorites move from per-Space to per-Profile (§2, decision D-S2).
    ///
    /// Specified by the session layer, implemented here. A Favorite is a logged-in app tile,
    /// so it belongs to the cookie jar that holds the login, not to the tab list it happens
    /// to have been created in. Arc keys its Favorites container by profile
    /// (`topAppsContainerIDs`) and this is the same key.
    ///
    /// Nothing in this migration deletes a row. The cap trim demotes overflow to
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
        // still its home `spaceID` afterwards; only the scope has changed.
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
        // `archivedAt IS NULL` appears twice and both are load-bearing. An archived
        // Favorite is reachable: §2 says Favorites never auto-archive, but
        // `deleteSpace(_:policy: .archiveTabs)` archives one when its Profile has no
        // other Space to home it in. So:
        //
        //   · in the ranking, so an archived tile cannot displace a live one;
        //   · in the outer `WHERE`, because without it an archived row falls out of the
        //     ranked set, is caught by `NOT IN` and silently demoted — the filter that
        //     protects it from being counted would be what demotes it.
        //
        // It also makes the SQL agree with the runtime: the session holds archived tabs
        // in `session.archived` rather than in `TabList`, so `favorites(onProfile:)`
        // already never counts them.
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
