//
//  BrowserStore+Bookmarks.swift
//  BrowserKit
//
//  §11.1's `bookmarks` table (`v18`): the folder tree an import arrived with.
//  The sidebar keeps §3.4b's one level of folders and the imported pages stay
//  `Tab` rows in them; this is only where each page sat in the source, so the
//  HTML export (§23.4) can write the tree back out. See docs/DECISIONS.md,
//  "The imported bookmark tree".
//

import Foundation
import GRDB

/// One leaf of an imported tree: a page and the folders above it, outermost first.
/// An empty `folderPath` is the source's bookmarks bar.
public struct Bookmark: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bookmarks"

    public var spaceID: UUID
    public var url: URL
    public var title: String
    /// Stored as JSON rather than joined: a folder may be called `A/B`.
    public var folderPath: [String]
    public var dateAdded: Date?

    public init(spaceID: UUID, url: URL, title: String, folderPath: [String], dateAdded: Date? = nil) {
        self.spaceID = spaceID
        self.url = url
        self.title = title
        self.folderPath = folderPath
        self.dateAdded = dateAdded
    }
}

extension Schema {

    /// `v18` — keyed on the whole leaf, so a page filed in two folders is two rows and a
    /// re-import is a no-op. Not synced: no CloudKit record type declares it, and
    /// declaring one is a Production deploy. Goes with its Space.
    static func rememberTheBookmarksTree(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS bookmarks (
            spaceID BLOB NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            folderPath TEXT NOT NULL,
            dateAdded DATETIME,
            PRIMARY KEY (spaceID, url, folderPath)
        )
        """)
    }
}

public extension BrowserStore {

    /// Records leaves, ignoring any already there. Returns how many were new.
    @discardableResult
    func recordBookmarks(_ bookmarks: [Bookmark]) async throws -> Int {
        try await pool.write { db in
            var added = 0
            for bookmark in bookmarks {
                try bookmark.insert(db, onConflict: .ignore)
                added += db.changesCount
            }
            return added
        }
    }

    /// A Space's tree, in the order it was recorded.
    func bookmarks(inSpace spaceID: UUID) async throws -> [Bookmark] {
        try await pool.read { db in
            try Bookmark.fetchAll(db, sql: "SELECT * FROM bookmarks WHERE spaceID = ? ORDER BY rowid", arguments: [spaceID])
        }
    }
}
