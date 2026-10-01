//
//  Schema+SitePermissions.swift
//  BrowserKit
//
//  `v14`, the per-Space site answers. Beside the rest of the schema rather than
//  in it because `Schema` is at SwiftLint's type-body limit.
//

import Foundation
import GRDB

extension Schema {

    /// `v14` — the camera, the microphone, the location, the local network and pop-ups
    /// are answered per Space (`BrowserStore.SitePermission.isPerSpace`).
    ///
    /// Every answer already given is copied into every Space, so nothing the user said
    /// before the upgrade stops holding after it; the Spaces part ways from the next
    /// answer on. The columns then leave `siteSettings`, so there is one place each
    /// answer can be. `ON DELETE CASCADE`: the answers were given to a Space's cookie
    /// jar, and go with it.
    ///
    /// Not synced. `popups` and `localNetwork` were, as fields of `SiteSetting`; this
    /// Luna stops writing them there and leaves what another Mac wrote alone. See
    /// docs/DECISIONS.md, "Per-Space site answers".
    ///
    /// Idempotent on the live schema, like every migration here.
    static func keepSiteAnswersPerSpace(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS spaceSitePermissions (
            spaceID BLOB NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
            host TEXT NOT NULL,
            camera BOOLEAN,
            microphone BOOLEAN,
            location BOOLEAN,
            localNetwork BOOLEAN,
            popups BOOLEAN,
            PRIMARY KEY (spaceID, host)
        )
        """)
        let existing = Set(try db.columns(in: "siteSettings").map(\.name))
        let moving = ["camera", "microphone", "location", "localNetwork", "popups"].filter(existing.contains)
        guard !moving.isEmpty else { return }
        try db.execute(sql: """
        INSERT OR IGNORE INTO spaceSitePermissions (spaceID, host, \(moving.joined(separator: ", ")))
        SELECT spaces.id, site.host, \(moving.map { "site.\($0)" }.joined(separator: ", "))
          FROM spaces CROSS JOIN siteSettings AS site
         WHERE \(moving.map { "site.\($0) IS NOT NULL" }.joined(separator: " OR "))
        """)
        // SQLite will not drop a column a trigger names, and sync's update trigger names
        // two of these. It comes back from `SyncSQL` without them.
        try db.execute(sql: "DROP TRIGGER IF EXISTS sync_siteSettings_update")
        for name in moving {
            try db.execute(sql: "ALTER TABLE siteSettings DROP COLUMN \(name)")
        }
        for statement in SyncSQL.triggers { try db.execute(sql: statement) }
    }
}
