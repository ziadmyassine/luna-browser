//
//  Schema+Extensions.swift
//  BrowserKit
//
//  `v11`, the installed-extension tables (§16.3, §16.6). Beside the rest of
//  the schema rather than in it because `Schema` is at SwiftLint's type-body
//  limit.
//

import Foundation
import GRDB

extension ExtensionRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "extensions"
}

extension ExtensionSpaceRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "extensionSpaces"
}

extension Schema {

    /// `v11` — one row per installed extension, and one per extension per Space
    /// it has ever been answered for: whether it runs there, and what the user
    /// granted and refused there.
    ///
    /// Grants are per Space because each Space has its own controller (docs/EXTENSIONS.md
    /// §3.1), and they are stored at all because WebKit keeps none across launches
    /// (`WKWebExtensionContext.h`). One JSON column rather than a row per grant:
    /// they are only ever read and written as a set, at load and on a decision.
    /// Both cascade, so uninstalling or deleting a Space leaves no strays.
    static func rememberInstalledExtensions(_ db: Database) throws {
        try db.create(table: "extensions") { table in
            table.primaryKey("id", .text)
            table.column("source", .text).notNull()
            table.column("installedAt", .datetime).notNull()
        }
        try db.create(table: "extensionSpaces") { table in
            table.column("extensionID", .text).notNull().references("extensions", onDelete: .cascade)
            table.column("spaceID", .blob).notNull().indexed().references("spaces", onDelete: .cascade)
            table.column("isEnabled", .boolean).notNull()
            table.column("grants", .jsonText).notNull()
            table.primaryKey(["extensionID", "spaceID"])
        }
    }
}
