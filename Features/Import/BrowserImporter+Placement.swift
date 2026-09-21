//
//  BrowserImporter+Placement.swift
//  Luna — §23.2
//
//  Where an imported bookmark lands, split out of `BrowserImporter` so the
//  reading half and the writing half can each be read in one sitting.
//
//  It is the half with the decisions in it. Luna has no bookmarks table
//  (§11.1), so a bookmark becomes a `Tab`, and the tier it becomes decides
//  whether it is a Favorite tile on a Profile or a pinned row in a Space —
//  two things the user can see and one, `profileID`, that only a later
//  migration would have noticed.
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
    /// One key, the URL alone. §23.2 asks for folder path plus URL as well, so
    /// that a site bookmarked in two folders survives as two bookmarks — the
    /// right answer for something with folders. Luna has none (§11.1 lists a
    /// `bookmarks` table that is not created), so both copies land in one Space
    /// as two identical rows, which is a duplicate by any reading. The folder
    /// key was here and could never fire: it was ANDed with this one, and the
    /// URL had already rejected the second copy.
    func write(
        _ bookmarks: [ImportedBookmark],
        into spaceID: UUID,
        dryRun: Bool
    ) async throws -> (added: Int, skipped: Int) {
        let existing = try await store.tabs(inSpace: spaceID, includeArchived: true)
        var seen = Set(existing.map { Self.dedupKey($0.url) })
        var order = (existing.map(\.order).max() ?? -1) + 1

        // Favorites belong to the Profile, not to the Space, and there are
        // twelve of them. A bookmarks bar is routinely longer than that, and
        // written past the cap the rows sit over it until `v2`'s migration
        // next runs and demotes whichever twelve it likes — so the cap is
        // applied here, where the choice is the user's own order. Past it a
        // bookmark is pinned rather than dropped.
        //
        // The Space is looked up rather than passed in because a dry run is
        // handed an id nothing was created for; that case counts nothing
        // against the cap and writes nothing at all.
        let exists = try await store.spaces().contains { $0.id == spaceID }
        var favourites = exists ? try await store.favorites(inSpace: spaceID).count : 0

        var added = 0
        var skipped = 0

        for bookmark in bookmarks {
            guard seen.insert(Self.dedupKey(bookmark.url)).inserted else {
                skipped += 1
                continue
            }
            added += 1
            var kind = bookmark.placement.tabKind
            if kind == .essential, favourites >= BrowserStore.favoritesCap { kind = .pinned }
            if kind == .essential { favourites += 1 }
            guard !dryRun else { continue }

            let when = bookmark.dateAdded ?? Date()
            // ponytail: one `upsert` per bookmark, i.e. one transaction each.
            // Fine at the scale this sees — a whole Dia profile is 44 bookmarks.
            // If a 5,000-bookmark import ever turns up, `BrowserStore` wants a
            // bulk `upsert(_ tabs: [Tab])` and this loop becomes one call.
            try await store.upsert(Tab(
                spaceID: spaceID,
                kind: kind,
                url: bookmark.url,
                title: bookmark.title,
                createdAt: when,
                lastActiveAt: when,
                order: order
            ))
            order += 1
        }
        return (added, skipped)
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
