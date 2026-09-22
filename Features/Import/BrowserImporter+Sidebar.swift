//
//  BrowserImporter+Sidebar.swift
//  Luna — §23.2
//
//  The other writer: the one for a source that arrives with a shape.
//
//  `BrowserImporter+Placement` flattens a bookmarks tree into one §3.4b folder
//  named after the browser, which is right for a Chromium `Bookmarks` file and
//  for a Netscape export — neither has Spaces, and a folder per folder would
//  scatter an import across a column the user has to go looking through.
//
//  Arc and Dia are not that. Arc's sidebar is Spaces holding folders holding
//  saved tabs, which is §3.4b's own shape; Dia's favourites are a profile's
//  one-click row, which is §3.3's grid scoped the way Luna scopes it. Throwing
//  either away and rebuilding it as one flat folder is work the user then has
//  to undo by hand.
//
//  Three things this file decides, all of them because Luna's shape and Arc's
//  are near but not identical:
//
//  · **A Space per Arc Space, named after the browser it came from.** `Arc —
//    School`, not `School`: `resolveTargetSpace` reuses a Space of the same
//    name, and a user with a Space called Personal — which is Luna's own seed
//    name — would have Arc's pins land in the middle of it. The prefix is the
//    same one an imported profile already wears.
//  · **One folder per Arc folder, named by its path.** A Luna folder holds
//    tabs, not other folders, so `IA ▸ Physics` becomes `IA / Physics`. Both
//    names survive and two folders called `Physics` under different parents
//    cannot collide.
//  · **Loose pins go in a folder named after the browser.** §3.4b's upper tier
//    holds folders and nothing else, so a tab that was loose in Arc's pinned
//    tier needs one, and the browser's name is what it is: the things that were
//    loose in Arc.
//

import BrowserKit
import Foundation

extension BrowserImporter {

    /// The three things an import writes under: the Space it would make, the
    /// folder its bookmarks go in, and a Space the caller named outright.
    struct Names: Sendable {
        var space: String
        var folder: String
        /// Set when the caller has already decided. A sidebar's own Spaces are
        /// not made in that case: it has said where everything goes.
        var explicit: UUID?
    }

    /// The bookmarks half, and the Space it resolved. Nil when the source had
    /// no bookmarks to give — history resolves its own Space in that case,
    /// because a browser with nothing to hand over must not leave an empty
    /// Space behind.
    func importBookmarks(
        reader: any ProfileReader,
        names: Names,
        entry: inout ImportLedger.Entry,
        into summary: inout ImportSummary,
        dryRun: Bool
    ) async -> UUID? {
        do {
            let bookmarks = try reader.bookmarks()
            guard !bookmarks.isEmpty else { return nil }
            // Arc and Dia arrive with a shape §3.4b already has — see
            // `+Sidebar.swift`. A caller that named a Space is not asking for
            // it: it has already said where everything goes.
            guard !reader.keepsItsOwnStructure || names.explicit != nil else {
                let result = try await writeSidebar(
                    bookmarks,
                    browser: names.folder,
                    ownSpaceName: names.space,
                    entry: &entry,
                    dryRun: dryRun
                )
                summary.targetSpaceID = result.firstSpace
                summary.bookmarksAdded = result.added
                summary.bookmarksSkipped = result.skipped
                summary.spacesTouched = result.spaces
                return result.firstSpace
            }
            let spaceID = try await resolveTargetSpace(
                explicit: names.explicit,
                name: names.space,
                entry: &entry,
                dryRun: dryRun
            )
            summary.targetSpaceID = spaceID
            summary.spacesTouched = 1
            let result = try await write(bookmarks, into: spaceID, folder: names.folder, dryRun: dryRun)
            summary.bookmarksAdded = result.added
            summary.bookmarksSkipped = result.skipped
            return spaceID
        } catch {
            summary.failed += 1
            summary.warnings.append(error.localizedDescription)
            return nil
        }
    }

    /// What one sidebar import did.
    struct SidebarResult: Sendable {
        var added = 0
        var skipped = 0
        /// The Space a screen should offer to show: the first the sidebar
        /// named, or the import's own when it named none.
        var firstSpace: UUID?
        var spaces = 0
    }

    /// Writes a sidebar, Space by Space.
    ///
    /// - Parameters:
    ///   - browser: the browser's display name. Prefixes every Space it makes,
    ///     and names the folder the loose pins land in.
    ///   - ownSpaceName: where a bookmark with no Space of its own goes — the
    ///     Space this import would have made anyway. Dia's favourites are all
    ///     of these: the profile is the Space, so the sidebar names none.
    func writeSidebar(
        _ bookmarks: [ImportedBookmark],
        browser: String,
        ownSpaceName: String,
        entry: inout ImportLedger.Entry,
        dryRun: Bool
    ) async throws -> SidebarResult {
        var result = SidebarResult()
        // Grouped in first-seen order, so the Space a screen offers to show is
        // the one the source lists first rather than whichever the dictionary
        // hashed to the front.
        for name in Self.spaceOrder(of: bookmarks) {
            let theirs = bookmarks.filter { $0.spaceName == name }
            let spaceName = name.map { "\(browser) — \($0)" } ?? ownSpaceName
            // `entry.spaceID` remembers one Space, so only the import's own
            // may claim it — otherwise a second run of a two-Space sidebar
            // would remember whichever Space it wrote last.
            let spaceID: UUID
            if name == nil {
                spaceID = try await resolveTargetSpace(
                    explicit: nil,
                    name: spaceName,
                    entry: &entry,
                    dryRun: dryRun
                )
            } else {
                var ignored = ImportLedger.Entry()
                spaceID = try await resolveTargetSpace(
                    explicit: nil,
                    name: spaceName,
                    entry: &ignored,
                    dryRun: dryRun
                )
            }
            let counts = try await write(theirs, intoSpace: spaceID, browser: browser, dryRun: dryRun)
            result.added += counts.added
            result.skipped += counts.skipped
            result.spaces += 1
            if result.firstSpace == nil { result.firstSpace = spaceID }
        }
        return result
    }

    /// The source's Spaces in the order it listed them, with `nil` — the
    /// import's own Space — wherever it first appeared.
    private static func spaceOrder(of bookmarks: [ImportedBookmark]) -> [String?] {
        var order: [String?] = []
        for bookmark in bookmarks where !order.contains(bookmark.spaceName) {
            order.append(bookmark.spaceName)
        }
        return order
    }

    /// One Space's worth: its tiles, then its folders.
    private func write(
        _ bookmarks: [ImportedBookmark],
        intoSpace spaceID: UUID,
        browser: String,
        dryRun: Bool
    ) async throws -> (added: Int, skipped: Int) {
        let existing = try await store.tabs(inSpace: spaceID, includeArchived: true)
        var seen = Set(existing.map { Self.dedupKey($0.url) })
        // Counted against what is already there, because §11.4's cap is per
        // Space and a second import must not push it over.
        var tiles = try await store.favorites(inSpace: spaceID).count
        var added = 0
        var skipped = 0

        for bookmark in bookmarks {
            guard seen.insert(Self.dedupKey(bookmark.url)).inserted else {
                skipped += 1
                continue
            }
            added += 1
            guard !dryRun else { continue }

            // Over the cap a tile becomes a saved row rather than being
            // dropped — the same answer `v2`'s trim gives, taken on the way in
            // so the grid is never briefly wrong.
            let isTile = bookmark.placement == .favorite && tiles < BrowserStore.favoritesCap
            if isTile { tiles += 1 }
            let folder = isTile ? nil : try await folderName(for: bookmark, browser: browser)
            try await place(bookmark, inSpace: spaceID, asTile: isTile, folder: folder)
        }
        return (added, skipped)
    }

    /// A Luna folder holds tabs and not other folders, so an Arc folder's whole
    /// path is its name — and a bookmark that was loose in the pinned tier goes
    /// in the one named after the browser.
    private func folderName(for bookmark: ImportedBookmark, browser: String) async throws -> String {
        bookmark.folderPath.isEmpty ? browser : bookmark.folderPath.joined(separator: " / ")
    }

    private func place(
        _ bookmark: ImportedBookmark,
        inSpace spaceID: UUID,
        asTile: Bool,
        folder name: String?
    ) async throws {
        var group: TabGroup?
        if let name { group = try await folder(named: name, inSpace: spaceID) }
        let when = bookmark.dateAdded ?? Date()
        let kind: TabKind = asTile ? .essential : .pinned
        let order = try await nextOrder(kind: kind, group: group?.id, inSpace: spaceID)
        try await store.upsert(Tab(
            spaceID: spaceID,
            kind: kind,
            url: bookmark.url,
            title: bookmark.title,
            createdAt: when,
            lastActiveAt: when,
            order: order,
            groupID: group?.id
        ))
    }

    /// The end of whichever run this tab is joining. Re-read per tab rather
    /// than counted up front: a sidebar writes into several folders at once and
    /// each has its own run of indices.
    private func nextOrder(kind: TabKind, group: UUID?, inSpace spaceID: UUID) async throws -> Int {
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        let run = tabs.filter { $0.kind == kind && $0.groupID == group }
        return (run.map(\.order).max() ?? -1) + 1
    }
}
