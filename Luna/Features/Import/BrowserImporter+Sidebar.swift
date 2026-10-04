//
//  BrowserImporter+Sidebar.swift
//  Luna — §23.2
//
//  The writer for a source that arrives with a shape: Arc's sidebar is §3.4b's
//  Spaces, folders and saved tabs, Dia's favourites are §3.3's grid, and
//  flattening either into one folder as `+Placement` does is work the user
//  then undoes by hand.
//
//  · A Space per Arc Space, named `Arc — School`, not `School`:
//    `resolveTargetSpace` reuses a Space of the same name, so Arc's Personal
//    would land inside Luna's own seed Space.
//  · One folder per Arc folder, named by its path: a Luna folder holds only
//    tabs, so `IA ▸ Physics` becomes `IA / Physics` and cannot collide.
//  · Loose pins go in a folder named after the browser, because §3.4b's upper
//    tier holds folders and nothing else.//
//  Which of those each bookmark becomes, or whether it comes at all, is the
//  mapping step's answer (`ImportMapping`); the list above is its default.
//

import BrowserKit
import Foundation

extension BrowserImporter {

    /// What an import writes under: the Space it would make, the folder its
    /// bookmarks go in, a Space the caller named outright, and the mapping
    /// step's answers.
    struct Names: Sendable {
        /// Where a bookmark with no Space of its own goes. Dia's are all of
        /// these: the profile is the Space, so the sidebar names none.
        var space: String
        /// The browser's display name. Prefixes every Space a sidebar makes,
        /// and names the folder loose items land in.
        var folder: String
        /// Set when the caller has already decided. A sidebar's own Spaces are
        /// not made in that case: it has said where everything goes.
        var explicit: UUID?
        /// Nil takes the like-for-like defaults.
        var mapping: ImportMapping?
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
            let read = try reader.bookmarks()
            let mapping = names.mapping ?? ImportMapping(counts: ImportMapping.counts(of: read))
            // Skipped before anything resolves a Space, so an import whose
            // every category was skipped makes none.
            let bookmarks = read.filter {
                mapping.placement(of: $0.category, folderPath: $0.folderPath, browser: names.folder) != nil
            }
            guard !bookmarks.isEmpty else { return nil }
            // Arc and Dia arrive with a shape §3.4b already has — see
            // `+Sidebar.swift`. A caller that named a Space is not asking for
            // it: it has already said where everything goes.
            guard !reader.keepsItsOwnStructure || names.explicit != nil else {
                let result = try await writeSidebar(
                    bookmarks,
                    mapping: mapping,
                    names: names,
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
    func writeSidebar(
        _ bookmarks: [ImportedBookmark],
        mapping: ImportMapping,
        names: Names,
        entry: inout ImportLedger.Entry,
        dryRun: Bool
    ) async throws -> SidebarResult {
        let browser = names.folder
        let ownSpaceName = names.space
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
            let counts = try await write(theirs, intoSpace: spaceID, mapping: mapping, browser: browser, dryRun: dryRun)
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

    /// One Space's worth, each bookmark where the mapping sends it.
    private func write(
        _ bookmarks: [ImportedBookmark],
        intoSpace spaceID: UUID,
        mapping: ImportMapping,
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
            guard let placement = mapping.placement(
                of: bookmark.category,
                folderPath: bookmark.folderPath,
                browser: browser
            ) else {
                continue
            }
            guard seen.insert(Self.dedupKey(bookmark.url)).inserted else {
                skipped += 1
                continue
            }
            added += 1
            guard !dryRun else { continue }

            // Over the cap a tile becomes a row in the browser's folder rather
            // than being dropped — the same answer `v2`'s trim gives, taken on
            // the way in so the grid is never briefly wrong.
            let isTile = placement == .favorite && tiles < BrowserStore.favoritesCap
            if isTile { tiles += 1 }
            let folder: String? = switch placement {
            case .favorite: isTile ? nil : browser
            case let .folder(name): name
            }
            try await place(bookmark, inSpace: spaceID, asTile: isTile, folder: folder)
        }
        return (added, skipped)
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
