//
//  ChromiumImport.swift
//  Luna — §23.2
//
//  One reader for the whole Chromium family — Dia, Arc, Chrome, Chromium,
//  Brave, Edge, Vivaldi, Opera — because they all write the same two files:
//  `Bookmarks` (JSON) and `History` (SQLite). Only the base directory differs,
//  and that is `ImportSource`'s job.
//
//  Reads a snapshot, never a live profile: see `SQLiteSnapshot.swift` for
//  the measurement that makes the copy mandatory.
//

import BrowserKit
import Foundation

/// Reads one snapshotted Chromium profile into Luna's neutral value types.
///
/// Pure in the sense that matters: no store, no AppKit, no shared state — a
/// function from files to values, which is why the tests point it at a
/// database they build themselves rather than at anyone's real profile.
struct ChromiumReader: Sendable {
    /// A directory holding copies of `Bookmarks` and `History`.
    let snapshotDirectory: URL
    /// Retained so the snapshot outlives the reader pointing into it — the
    /// snapshot deletes its directory in `deinit`, and a reader is nothing but
    /// a path into it.
    var snapshot: ImportSnapshot?

    /// How many visits cross from the reader to the writer at once. This is the
    /// memory bound for the whole import: a 200,000-visit profile never has
    /// more than this many `ImportedVisit` values alive.
    static let batchSize = 500

    /// Copies the two files this reader needs out of a live profile.
    ///
    /// Missing files are skipped rather than failing — Dia's `Default` profile
    /// on this Mac has a `History` and no `Bookmarks` at all.
    static func snapshot(profileDirectory: URL, into snapshot: ImportSnapshot) throws -> ChromiumReader {
        try snapshot.copyIn(profileDirectory.appending(path: "History"))
        try snapshot.copyIn(profileDirectory.appending(path: "Bookmarks"))
        return ChromiumReader(snapshotDirectory: snapshot.directory, snapshot: snapshot)
    }

    private func file(_ name: String) -> URL? {
        let url = snapshotDirectory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Bookmarks

    /// Flattens `Bookmarks` into a list, each entry tagged with its folder path.
    ///
    /// Returns an empty list when there is no `Bookmarks` file. Throws
    /// `ImportError.malformed` only when the file exists and is not a bookmarks
    /// tree — a truncated or corrupt file must fail this surface, not the run.
    func bookmarks() throws -> [ImportedBookmark] {
        guard let url = file("Bookmarks") else { return [] }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable("Bookmarks") }
        return try Self.flatten(bookmarksJSON: data)
    }

    /// Chromium's three fixed roots, in import order.
    static let rootTitles: [(key: String, title: String)] = [
        ("bookmark_bar", "Bookmarks Bar"),
        ("other", "Other Bookmarks"),
        ("synced", "Mobile Bookmarks")
    ]

    /// Depth cap. JSON cannot express a literal cycle, but a hand-edited or
    /// corrupt file can be arbitrarily deep, and an uncapped walk allocates a
    /// folder path per level without bound. Chromium's own UI stops being
    /// usable long before 12.
    static let maxDepth = 12

    /// `JSONSerialization`, not `Decodable`, for two reasons this file proves:
    /// `date_added` is microseconds-since-1601 written as a string
    /// (`"13429579614840426"` in Dia's file), and Chromium adds and removes
    /// keys between releases — a lenient walk survives that, a strict decode
    /// throws the user's whole bookmark tree away over one unknown field.
    static func flatten(bookmarksJSON data: Data) throws -> [ImportedBookmark] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let roots = root["roots"] as? [String: Any]
        else {
            throw ImportError.malformed("Bookmarks")
        }

        var bookmarks: [ImportedBookmark] = []
        for (key, title) in rootTitles {
            guard let node = roots[key] as? [String: Any] else { continue }
            // The bookmarks bar is the top level, not a folder inside one:
            // its loose URLs are the sites reached in one click, so they become
            // Favorites (§11.4) rather than rows three levels down inside a
            // wrapper the user never made. "Other" and "Mobile" keep theirs —
            // those really are separate collections.
            let isBar = key == "bookmark_bar"
            append(
                childrenOf: node,
                path: isBar ? [] : [title],
                depth: 0,
                placement: isBar ? .favorite : .folder,
                into: &bookmarks
            )
        }
        return bookmarks
    }

    private static func append(
        childrenOf node: [String: Any],
        path: [String],
        depth: Int,
        placement: BookmarkPlacement,
        into bookmarks: inout [ImportedBookmark]
    ) {
        guard depth <= maxDepth, let children = node["children"] as? [[String: Any]] else { return }

        for child in children {
            let name = (child["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch child["type"] as? String {
            case "url":
                guard
                    let string = child["url"] as? String,
                    let url = URL(string: string),
                    url.scheme != nil
                else { continue }
                bookmarks.append(ImportedBookmark(
                    url: url,
                    title: name.isEmpty ? (url.host() ?? string) : name,
                    dateAdded: (child["date_added"] as? String).flatMap {
                        ChromiumTimestamp.date(microsecondsSince1601: $0)
                    },
                    folderPath: path,
                    // A URL one level inside a bar folder is in a folder the
                    // user made; only the bar's own top level is a Favorite.
                    placement: placement
                ))
            case "folder":
                append(
                    childrenOf: child,
                    path: path + [name.isEmpty ? "Folder" : name],
                    depth: depth + 1,
                    placement: .folder,
                    into: &bookmarks
                )
            default:
                continue
            }
        }
    }

    // MARK: - History

    /// How many visits are newer than `watermark`, for the progress bar.
    /// `nil` when this profile has no readable history.
    func visitCount(after watermark: Int64) throws -> Int? {
        guard let url = file("History") else { return nil }
        let reader = try SQLiteReader(readOnly: url)
        defer { reader.close() }
        guard reader.hasTable("urls"), reader.hasTable("visits") else { return nil }
        // The same join and the same `hidden` filter as `streamVisits`, or the
        // progress bar counts rows the import will never write and stops short
        // of the end.
        let counts = try reader.query(
            """
            SELECT count(*) FROM visits v JOIN urls u ON u.id = v.url
            WHERE v.visit_time > ? AND u.hidden = 0
            """,
            bindings: [.int(watermark)]
        ) { Int($0.int(0)) }
        return counts.first
    }

    /// One keyset page of visits newer than `watermark`.
    ///
    /// A page of values rather than a streaming callback, because the caller is
    /// an actor: a closure handed to a `nonisolated` reader would have to cross
    /// the isolation boundary, and under Swift 6 that is a data race the
    /// compiler refuses. Pages are `Sendable`, so nothing crosses but data.
    ///
    /// Keyset-paginated on `visits.id` rather than `LIMIT`/`OFFSET`: keyset is
    /// one index seek per page where `OFFSET` re-scans everything before it and
    /// turns a large profile into quadratic work. `watermark` is fixed for the
    /// run, so `visit_time > ?` and `id > ?` give a stable total order, and the
    /// watermark is the whole idempotency story for history (`ImportLedger`).
    func visitPage(after watermark: Int64, from rowID: Int64, limit: Int) throws -> VisitPage {
        guard let url = file("History") else { return .empty }
        let reader = try SQLiteReader(readOnly: url)
        defer { reader.close() }
        guard reader.hasTable("urls"), reader.hasTable("visits") else { return .empty }

        let sql = """
        SELECT v.id, u.url, u.title, v.visit_time, v.transition
        FROM visits v JOIN urls u ON u.id = v.url
        WHERE v.visit_time > ? AND v.id > ? AND u.hidden = 0
        ORDER BY v.id
        LIMIT ?
        """

        var page = VisitPage(lastRowID: rowID)
        page.visits.reserveCapacity(limit)
        var rowCount = 0
        try reader.forEachRow(sql, bindings: [.int(watermark), .int(rowID), .int(Int64(limit))]) { row in
            rowCount += 1
            page.lastRowID = max(page.lastRowID, row.int(0))
            // A row with an unparseable URL or an impossible timestamp is
            // dropped, not fatal — but it still advances the cursor, or the
            // page would repeat forever.
            if let visit = Self.visit(from: row) { page.visits.append(visit) }
        }
        page.isLast = rowCount < limit
        return page
    }

    private static func visit(from row: SQLiteReader.Row) -> ImportedVisit? {
        guard
            let string = row.text(1),
            let url = URL(string: string),
            url.scheme != nil
        else { return nil }
        let stamp = row.int(3)
        guard let at = ChromiumTimestamp.date(microsecondsSince1601: stamp) else { return nil }
        return ImportedVisit(
            url: url,
            title: row.text(2) ?? "",
            kind: visitKind(transition: row.int(4)),
            at: at,
            sourceStamp: stamp
        )
    }

    /// Chromium's `visits.transition` is a bitfield: the low byte is the core
    /// type, the top two bits mark a redirect. Values confirmed against Dia's
    /// live profile, where cores 0/1/8/7/4/2/3 and 3,236 redirect rows appear.
    static func visitKind(transition: Int64) -> VisitKind {
        let coreMask: Int64 = 0xFF
        let redirectMask: Int64 = 0xC000_0000
        if transition & redirectMask != 0 { return .redirect }
        switch transition & coreMask {
        // TYPED, GENERATED, KEYWORD, KEYWORD_GENERATED — all omnibox intent.
        case 1, 5, 9, 10: return .typed
        case 2: return .bookmarked // AUTO_BOOKMARK
        case 3, 4: return .embed // AUTO_SUBFRAME, MANUAL_SUBFRAME
        default: return .link
        }
    }
}

/// What `run` needs from a source. Two conformances — Chromium and Safari —
/// which is exactly why it exists: `run` would otherwise be written twice, and
/// the second copy is where the bugs go.
///
/// Every member returns values. Nothing takes a closure, because the caller is
/// an actor and a callback would have to cross its isolation boundary.
protocol ProfileReader: Sendable {
    func bookmarks() throws -> [ImportedBookmark]
    /// `nil` when this source has no readable history at all, which is
    /// different from having none newer than `watermark`.
    func visitCount(after watermark: Int64) throws -> Int?
    func visitPage(after watermark: Int64, from rowID: Int64, limit: Int) throws -> VisitPage
}

extension ChromiumReader: ProfileReader {}
