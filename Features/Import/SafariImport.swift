//
//  SafariImport.swift
//  Luna — §23.2
//
//  Safari is a different problem from the Chromium family, and the difference
//  is not the file formats — those are easy. It is TCC.
//
//  Measured on this Mac, 2026-09-17: `ls ~/Library/Safari` returns
//  "Operation not permitted" from an unsandboxed shell. That denial is TCC,
//  not the App Sandbox, so no entitlement and no signing change fixes it — the
//  user has to grant Full Disk Access in System Settings, which cannot be
//  prompted for programmatically.
//
//  So §23.2's order is the right one and this file is the second path:
//  `NetscapeBookmarks` is how a Safari user actually gets their bookmarks in
//  (File ▸ Export Bookmarks… in Safari, then pick the file). What is here runs
//  only once `isReadable()` says the directory is readable, i.e. only after the user
//  has granted access for their own reasons.
//

import BrowserKit
import Foundation

/// Reads a snapshotted `~/Library/Safari`.
struct SafariReader: Sendable {
    let snapshotDirectory: URL
    /// Retained for the same reason as `ChromiumReader.snapshot`.
    var snapshot: ImportSnapshot?

    /// Whether Safari's data is readable at all. `false` means Full Disk
    /// Access, every time — the directory always exists.
    static func isReadable() -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            atPath: ImportSource.safari.supportDirectoryURL.path
        )) != nil
    }

    static func snapshot(into snapshot: ImportSnapshot) throws -> SafariReader {
        let safari = ImportSource.safari.supportDirectoryURL
        guard isReadable() else { throw ImportError.needsFullDiskAccess("Safari") }
        try snapshot.copyIn(safari.appending(path: "History.db"))
        try snapshot.copyIn(safari.appending(path: "Bookmarks.plist"))
        return SafariReader(snapshotDirectory: snapshot.directory, snapshot: snapshot)
    }

    private func file(_ name: String) -> URL? {
        let url = snapshotDirectory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Bookmarks

    /// `Bookmarks.plist` is a binary property list whose nodes are
    /// `WebBookmarkTypeList` (a folder, with `Title` and `Children`) and
    /// `WebBookmarkTypeLeaf` (a bookmark, with `URLString` and
    /// `URIDictionary.title`). `PropertyListSerialization` reads binary and XML
    /// alike, so there is nothing to detect.
    ///
    /// `BookmarksBar` is Safari's Favorites bar and is transparent for the same
    /// reason Chromium's `bookmark_bar` is: it is the bar, not a folder in it.
    func bookmarks() throws -> [ImportedBookmark] {
        guard let url = file("Bookmarks.plist") else { return [] }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable("Bookmarks.plist") }
        return try Self.flatten(bookmarksPlist: data)
    }

    static func flatten(bookmarksPlist data: Data) throws -> [ImportedBookmark] {
        guard
            let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw ImportError.malformed("Bookmarks.plist")
        }
        var bookmarks: [ImportedBookmark] = []
        append(childrenOf: root, path: [], depth: 0, into: &bookmarks)
        return bookmarks
    }

    /// Safari's Reading List is a separate feature with no Luna equivalent yet,
    /// so it is skipped rather than flattened into bookmarks.
    private static let skippedTitles: Set<String> = ["com.apple.ReadingList"]

    private static func append(
        childrenOf node: [String: Any],
        path: [String],
        depth: Int,
        into bookmarks: inout [ImportedBookmark]
    ) {
        guard depth <= ChromiumReader.maxDepth, let children = node["Children"] as? [[String: Any]] else { return }

        for child in children {
            switch child["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                guard
                    let string = child["URLString"] as? String,
                    let url = URL(string: string),
                    url.scheme != nil
                else { continue }
                let title = ((child["URIDictionary"] as? [String: Any])?["title"] as? String) ?? ""
                bookmarks.append(ImportedBookmark(
                    url: url,
                    title: title.isEmpty ? (url.host() ?? string) : title,
                    folderPath: path,
                    placement: path.isEmpty ? .favorite : .folder
                ))
            case "WebBookmarkTypeList":
                let identifier = (child["Title"] as? String) ?? ""
                guard !skippedTitles.contains(identifier) else { continue }
                // `BookmarksBar` and `BookmarksMenu` are Safari's two roots, not
                // folders the user made; keep their contents at the top level.
                let isRoot = identifier == "BookmarksBar" || identifier == "BookmarksMenu"
                append(
                    childrenOf: child,
                    path: isRoot || identifier.isEmpty ? path : path + [identifier],
                    depth: depth + 1,
                    into: &bookmarks
                )
            default:
                continue
            }
        }
    }

    // MARK: - History

    /// Safari stamps visits in seconds since 2001 (`CFAbsoluteTime`) as a
    /// REAL, not Chromium's integer microseconds since 1601. The watermark is
    /// microseconds in both cases so the ledger holds one kind of number; the
    /// cost is a `CAST` that gives up the `visit_time` index, which is
    /// affordable because the rowid keyset does the paging anyway.
    func visitCount(after watermark: Int64) throws -> Int? {
        guard let url = file("History.db") else { return nil }
        let reader = try SQLiteReader(readOnly: url)
        defer { reader.close() }
        guard reader.hasTable("history_items"), reader.hasTable("history_visits") else { return nil }
        return try reader.query(
            "SELECT count(*) FROM history_visits WHERE CAST(visit_time * 1000000 AS INTEGER) > ?",
            bindings: [.int(watermark)]
        ) { Int($0.int(0)) }.first
    }

    /// One keyset page, same shape and same reason as `ChromiumReader`'s.
    func visitPage(after watermark: Int64, from rowID: Int64, limit: Int) throws -> VisitPage {
        guard let url = file("History.db") else { return .empty }
        let reader = try SQLiteReader(readOnly: url)
        defer { reader.close() }
        guard reader.hasTable("history_items"), reader.hasTable("history_visits") else { return .empty }

        let sql = """
        SELECT v.id, i.url, v.title, v.visit_time, v.redirect_source
        FROM history_visits v JOIN history_items i ON i.id = v.history_item
        WHERE CAST(v.visit_time * 1000000 AS INTEGER) > ? AND v.id > ?
        ORDER BY v.id
        LIMIT ?
        """

        var page = VisitPage(lastRowID: rowID)
        page.visits.reserveCapacity(limit)
        var rowCount = 0
        try reader.forEachRow(sql, bindings: [.int(watermark), .int(rowID), .int(Int64(limit))]) { row in
            rowCount += 1
            page.lastRowID = max(page.lastRowID, row.int(0))
            guard
                let string = row.text(1),
                let url = URL(string: string),
                url.scheme != nil
            else { return }
            let seconds = row.double(3)
            guard let at = ChromiumTimestamp.date(secondsSince2001: seconds) else { return }
            page.visits.append(ImportedVisit(
                url: url,
                title: row.text(2) ?? "",
                // Safari records no transition type. A visit reached through a
                // redirect is the one thing it does mark; the rest is honestly
                // just a link.
                kind: row.text(4) == nil ? .link : .redirect,
                at: at,
                sourceStamp: Int64(seconds * 1_000_000)
            ))
        }
        page.isLast = rowCount < limit
        return page
    }
}

extension SafariReader: ProfileReader {}
