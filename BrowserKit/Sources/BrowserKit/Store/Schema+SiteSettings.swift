//
//  Schema+SiteSettings.swift
//  BrowserKit
//
//  `v14` on, the migrations about sites: registered here and defined beside
//  the rest of the schema rather than in it, because `Schema` is at
//  SwiftLint's type-body limit.
//

import Foundation
import GRDB

extension Schema {

    /// In order, after `v13`.
    static func registerSiteMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v14") { db in
            try keepSiteAnswersPerSpace(db)
        }
        migrator.registerMigration("v15") { db in
            try rememberSiteUserAgents(db)
        }
        migrator.registerMigration("v16") { db in
            try rememberClipboardAnswers(db)
        }
    }

    /// `v15` — §4.6's per-site user agent: a `WebViewFactory.UserAgentMode` raw value,
    /// or NULL for the one chosen in Settings.
    ///
    /// Not among `SyncSQL`'s synced columns: a field the CloudKit schema does not
    /// declare cannot be written, and declaring one is a Production deploy. The global
    /// choice syncs as a setting (`SyncedDefaults`).
    ///
    /// Idempotent on the live schema, like every migration here.
    static func rememberSiteUserAgents(_ db: Database) throws {
        guard try !db.columns(in: "siteSettings").map(\.name).contains("userAgent") else { return }
        try db.execute(sql: "ALTER TABLE siteSettings ADD COLUMN userAgent TEXT")
    }
}
