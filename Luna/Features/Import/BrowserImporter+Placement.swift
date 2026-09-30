//
//  BrowserImporter+Placement.swift
//  Luna — §23.2
//
//  Where an imported bookmark lands, split out of `BrowserImporter` so the
//  reading half and the writing half can each be read in one sitting.
//
//  It is the half with the decisions in it. Luna has no bookmarks table
//  (§11.1), so a bookmark becomes a `Tab` — a saved one, in a §3.4b folder
//  named after the browser it came from.
//
//  The folder is this file's answer to "where did my bookmarks go": loose in
//  the Space's two tiers they mix with what the user saved themselves. A
//  folder keeps the import together, names it, and can be folded shut or
//  taken apart in one gesture by anyone who does not want it.
//

import BrowserKit
import Foundation

extension BrowserImporter {

    // MARK: - Writing

    /// Deduplicates, then writes. This is the whole idempotency story for
    /// bookmarks, and it reads from the store rather than the ledger on
    /// purpose: a user who deleted the ledger, or who imports the same sites
    /// from two browsers, still gets no duplicates.
    ///
    /// One key, the URL alone, not §23.2's folder path plus URL: Luna has no
    /// bookmark folders (§11.1's `bookmarks` table is not created), so a site
    /// bookmarked in two folders would land as two identical rows in one
    /// Space, which is a duplicate by any reading.
    /// - Parameter folder: what the §3.4b folder is called — the browser the
    ///   bookmarks came from, not the profile inside it. Two profiles of the
    ///   same browser share one folder, which is what "my Chrome bookmarks"
    ///   means to the person reading the column.
    func write(
        _ bookmarks: [ImportedBookmark],
        into spaceID: UUID,
        folder folderName: String,
        dryRun: Bool
    ) async throws -> (added: Int, skipped: Int) {
        let existing = try await store.tabs(inSpace: spaceID, includeArchived: true)
        var seen = Set(existing.map { Self.dedupKey($0.url) })

        // Nothing is created for a dry run, so there is no folder to put
        // anything in and no order to carry — it counts and returns.
        let group = dryRun ? nil : try await folder(named: folderName, inSpace: spaceID)
        var order = group.map { group in
            (existing.filter { $0.groupID == group.id }.map(\.order).max() ?? -1) + 1
        } ?? 0

        var added = 0
        var skipped = 0

        for bookmark in bookmarks {
            guard seen.insert(Self.dedupKey(bookmark.url)).inserted else {
                skipped += 1
                continue
            }
            added += 1
            guard !dryRun, let group else { continue }

            let when = bookmark.dateAdded ?? Date()
            // ponytail: one `upsert` per bookmark, i.e. one transaction each.
            // Fine at the scale this sees — a whole Dia profile is 44 bookmarks.
            // If a 5,000-bookmark import ever turns up, `BrowserStore` wants a
            // bulk `upsert(_ tabs: [Tab])` and this loop becomes one call.
            //
            // Saved, every one of them, and a tile none of them. §3.4b's rule
            // is that a folder's tier is its tabs' tier and that §3.3's grid
            // holds one tab per tile, so a bookmark that became a Favorite
            // would be outside the folder the user was told to look in, even
            // for the bar's first dozen. Dragging a row into the grid is one
            // gesture.
            try await store.upsert(Tab(
                spaceID: spaceID,
                kind: .pinned,
                url: bookmark.url,
                title: bookmark.title,
                createdAt: when,
                lastActiveAt: when,
                order: order,
                groupID: group.id
            ))
            order += 1
        }
        return (added, skipped)
    }

    /// The folder an import lands in, made once and found again after that.
    ///
    /// Not private: `+Sidebar.swift` is the other writer and asks for several
    /// of these per Space.
    ///
    /// Found by name, because that is what a second import of the same browser
    /// has to land in — a new folder each time would be the "Dia, Dia 2, Dia 3"
    /// that `resolveTargetSpace` already refuses for Spaces. A user who renamed
    /// it gets a new one, and that is the honest answer: the folder they
    /// renamed is theirs now.
    ///
    /// It stands in §3.4b's saved tier, at the end of it. The slot is numbered
    /// against the loose saved tabs and the saved folders together, because
    /// §3.4b shares one run of indices between them.
    func folder(named name: String, inSpace spaceID: UUID) async throws -> TabGroup {
        let groups = try await store.groups(inSpace: spaceID)
        if let existing = groups.first(where: { $0.name == name && $0.kind == .pinned }) { return existing }
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: false)
        let slots = tabs.filter { $0.kind == .pinned && $0.groupID == nil }.map(\.order)
            + groups.filter { $0.kind == .pinned }.map(\.order)
        // The same glyph the imported Space wears, which is the one the
        // Settings row the user pressed wears too. It is not one of
        // `GroupMenu.symbols`, so the icon submenu ticks nothing until they
        // pick one — honest, and better than starting on a plain folder that
        // says nothing about where these came from.
        let group = TabGroup(
            spaceID: spaceID,
            name: name,
            symbolName: "square.and.arrow.down",
            kind: .pinned,
            order: (slots.max() ?? -1) + 1
        )
        try await store.upsert(group)
        return group
    }

    /// Two URLs are the same bookmark when they differ only by a trailing slash
    /// or by the case of the scheme or host. Anything more aggressive —
    /// dropping `www.`, sorting query items — starts merging pages that are
    /// genuinely different, which is worse than one duplicate row.
    static func dedupKey(_ url: URL) -> String {
        var string = url.absoluteString
        if string.hasSuffix("/") { string.removeLast() }
        guard var components = URLComponents(string: string) else { return string.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? string
    }

    // MARK: - Target Space

    func resolveTargetSpace(
        explicit: UUID?,
        name: String,
        entry: inout ImportLedger.Entry,
        dryRun: Bool
    ) async throws -> UUID {
        if let explicit { return explicit }

        let spaces = try await store.spaces()
        // A Space the user has deleted since the last import drops its stale
        // record rather than being resurrected.
        if let remembered = entry.spaceID, spaces.contains(where: { $0.id == remembered }) {
            return remembered
        }
        // Reusing a Space of the same name keeps repeated imports from
        // accumulating "Dia", "Dia 2", "Dia 3".
        if let match = spaces.first(where: { $0.name == name }) {
            entry.spaceID = match.id
            return match.id
        }

        // A dry run creates nothing at all. It reports the id it would have
        // used so a screen can still say where things would land.
        guard !dryRun else { return UUID() }

        // `seedIfEmpty` is a no-op once anything exists; it is here so an
        // import during onboarding — before the user has opened a window —
        // lands in a database that has been stood up.
        try await store.seedIfEmpty()
        let space = Space(
            name: name,
            symbolName: "square.and.arrow.down",
            gradient: .defaultSpace,
            order: (spaces.map(\.order).max() ?? -1) + 1
        )
        try await store.upsert(space)
        entry.spaceID = space.id
        return space.id
    }
}
