//
//  BrowserImporter.swift
//  Luna — §23.2, §23.4, §11.5
//
//  The engine behind §30.17's import screen. It detects nothing and renders
//  nothing: a screen calls `ImportSourceDetector.detect()` for the list, then
//  `run(_:dryRun:progress:)` for one chosen source and profile.
//
//  Three rules this file exists to keep:
//
//  1. **Idempotent.** Running an import twice must not double anything.
//     Bookmarks are deduplicated against the target Space by URL, read from the
//     store rather than remembered. History is deduplicated by a per-profile
//     watermark in `ImportLedger` — a second run asks the source only for
//     visits newer than the newest one already taken, which is normally none.
//  2. **Never blocking, never hogging the store.** Everything here runs on
//     `BrowserImporter`'s own actor, never the main actor, and visits cross to
//     `BrowserStore` in batches of 500 with a `flush()` between them (§11.5) —
//     so the store's actor is entered and left per batch rather than held for
//     the length of the import.
//  3. **Malformed input is the normal case.** A truncated `Bookmarks`, a locked
//     or corrupt `History`, a bookmarks tree deeper than anything sane: each
//     fails its own surface, is counted in `ImportSummary.failed` with a line
//     in `warnings`, and the rest of the import still lands.
//
//  Not imported, deliberately: **passwords** (§23.2 — Keychain-encrypted and
//  out of scope) and **extensions** (§30.18's copy warning — there is no store
//  and no parity guarantee, so no string here may promise them).
//

import BrowserKit
import Foundation

actor BrowserImporter {
    private let store: BrowserStore
    private let ledger: ImportLedger

    init(store: BrowserStore, ledger: ImportLedger = .standard) {
        self.store = store
        self.ledger = ledger
    }

    // MARK: - What a screen calls

    /// Imports one profile, or — with `dryRun` — reports exactly what it would
    /// import and writes nothing.
    ///
    /// The dry run is not a separate code path: it walks the same readers and
    /// the same deduplication and skips only the writes. A preview that took a
    /// different route would preview the wrong thing.
    @discardableResult
    func run(
        _ request: ImportRequest,
        dryRun: Bool = false,
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async throws -> ImportSummary {
        progress?(ImportProgress(phase: .copying, completed: 0, total: nil))
        // The snapshot is retained by the reader: it deletes its directory in
        // `deinit`, and the reader is only a path into it.
        let snapshot = try ImportSnapshot()
        let reader = try makeReader(request, snapshot: snapshot)
        return try await run(
            reader: reader,
            ledgerKey: ImportLedger.key(request),
            spaceName: request.spaceName,
            surfaces: request.surfaces,
            targetSpaceID: request.targetSpaceID,
            dryRun: dryRun,
            progress: progress
        )
    }

    /// The same import against an already-built reader. Separated because it is
    /// what makes this testable without a browser installed, and because a
    /// folder the user picked by hand is a reader too.
    @discardableResult
    func run(
        reader: any ProfileReader,
        ledgerKey: String,
        spaceName: String,
        surfaces: ImportSurfaces = .all,
        targetSpaceID: UUID? = nil,
        dryRun: Bool = false,
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async throws -> ImportSummary {
        var summary = ImportSummary(isDryRun: dryRun)
        var entry = ledger.entry(ledgerKey)

        // Bookmarks first: bounded, and what the user actually looks for. A
        // history import cancelled halfway has still delivered them.
        if surfaces.contains(.bookmarks) {
            progress?(ImportProgress(phase: .bookmarks, completed: 0, total: nil))
            do {
                let bookmarks = try reader.bookmarks()
                // No bookmarks, no Space. History in Luna is global (§11.1's
                // `places`/`visits` have no space column), so a history-only
                // import needs no Space at all and must not leave an empty one.
                if !bookmarks.isEmpty {
                    let spaceID = try await resolveTargetSpace(
                        explicit: targetSpaceID,
                        name: spaceName,
                        entry: &entry,
                        dryRun: dryRun
                    )
                    summary.targetSpaceID = spaceID
                    let result = try await write(bookmarks, into: spaceID, dryRun: dryRun)
                    summary.bookmarksAdded = result.added
                    summary.bookmarksSkipped = result.skipped
                }
            } catch {
                summary.failed += 1
                summary.warnings.append(error.localizedDescription)
            }
        }

        if surfaces.contains(.history) {
            await importHistory(reader: reader, entry: &entry, dryRun: dryRun, into: &summary, progress: progress)
        }

        progress?(ImportProgress(phase: .finishing, completed: summary.visitsAdded, total: nil))
        if !dryRun { ledger.save(entry, for: ledgerKey) }
        return summary
    }

    private func importHistory(
        reader: any ProfileReader,
        entry: inout ImportLedger.Entry,
        dryRun: Bool,
        into summary: inout ImportSummary,
        progress: (@Sendable (ImportProgress) -> Void)?
    ) async {
        let watermark = entry.historyWatermark
        let total = (try? reader.visitCount(after: watermark)) ?? nil
        progress?(ImportProgress(phase: .history, completed: 0, total: total))

        var added = 0
        var highest = watermark
        var cursor: Int64 = 0
        do {
            while true {
                if Task.isCancelled { throw CancellationError() }
                let page = try reader.visitPage(
                    after: watermark,
                    from: cursor,
                    limit: ChromiumReader.batchSize
                )
                cursor = page.lastRowID
                highest = max(highest, page.visits.map(\.sourceStamp).max() ?? highest)

                if !dryRun {
                    // One store transaction per page, not per visit (§11.5):
                    // `recordVisit` buffers and `flush` commits the batch, so
                    // the store's actor is entered and left per page rather
                    // than held for the whole import.
                    for visit in page.visits {
                        try await store.recordVisit(
                            url: visit.url,
                            title: visit.title,
                            kind: visit.kind,
                            at: visit.at
                        )
                    }
                    try await store.flush()
                }
                added += page.visits.count
                progress?(ImportProgress(phase: .history, completed: added, total: total))
                if page.isLast { break }
            }
            // Advanced even on a partial run, so resuming picks up where this
            // stopped instead of re-reading everything.
            entry.historyWatermark = highest
        } catch is CancellationError {
            entry.historyWatermark = highest
            summary.warnings.append(String(localized: "Import stopped early. Run it again to continue."))
        } catch {
            summary.failed += 1
            summary.warnings.append(error.localizedDescription)
        }

        summary.visitsAdded = added
        // What an earlier run already took. On a second run this is the whole
        // profile and `visitsAdded` is zero — the idempotency claim as a number
        // the user can read.
        let everything = ((try? reader.visitCount(after: 0)) ?? nil) ?? added
        summary.visitsSkipped = max(0, everything - added)
    }

    // MARK: - Netscape HTML (§23.2 generic, and the only route into Safari)

    /// Imports a bookmarks HTML file the user exported from another browser.
    @discardableResult
    func importBookmarks(
        htmlAt url: URL,
        into targetSpaceID: UUID? = nil,
        dryRun: Bool = false
    ) async throws -> ImportSummary {
        guard let html = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        let bookmarks = NetscapeBookmarks.parse(html)
        guard !bookmarks.isEmpty else { throw ImportError.malformed(url.lastPathComponent) }

        var entry = ImportLedger.Entry()
        let name = url.deletingPathExtension().lastPathComponent
        let spaceID = try await resolveTargetSpace(
            explicit: targetSpaceID,
            name: name.isEmpty ? String(localized: "Imported") : name,
            entry: &entry,
            dryRun: dryRun
        )
        let result = try await write(bookmarks, into: spaceID, dryRun: dryRun)
        return ImportSummary(
            isDryRun: dryRun,
            bookmarksAdded: result.added,
            bookmarksSkipped: result.skipped,
            targetSpaceID: spaceID
        )
    }

    /// §23.4: bookmarks out, in the format every other browser reads.
    ///
    /// `spaceID == nil` exports every Space, each as a folder. One Space
    /// exports its Essentials as Favorites and its Pinned tabs as bookmarks.
    /// Today's tabs are working state rather than bookmarks, so they stay out.
    func exportBookmarksHTML(spaceID: UUID? = nil) async throws -> String {
        let spaces = try await store.spaces()
        var bookmarks: [ImportedBookmark] = []
        let isSingleSpace = spaceID != nil

        for space in spaces where spaceID == nil || space.id == spaceID {
            let tabs = try await store.tabs(inSpace: space.id, includeArchived: false)
            for tab in tabs where tab.kind != .today {
                bookmarks.append(ImportedBookmark(
                    url: tab.url,
                    title: tab.title.isEmpty ? (tab.url.host() ?? tab.url.absoluteString) : tab.title,
                    dateAdded: tab.createdAt,
                    folderPath: isSingleSpace ? [] : [space.name],
                    placement: isSingleSpace && tab.kind == .essential ? .favorite : .folder
                ))
            }
        }
        return NetscapeBookmarks.write(bookmarks, title: "Luna Bookmarks")
    }

    // MARK: - Writing

    /// Deduplicates, then writes. This is the whole idempotency story for
    /// bookmarks, and it reads from the store rather than the ledger on
    /// purpose: a user who deleted the ledger, or who imports the same sites
    /// from two browsers, still gets no duplicates.
    ///
    /// Two keys, because §23.2's "same URL in a folder" and Luna's model are
    /// not the same shape:
    ///
    /// - **Within the incoming list**, folder path + URL, so a site bookmarked
    ///   in two different folders survives as two bookmarks.
    /// - **Against the target Space**, the URL alone, because Luna has no
    ///   folder column yet (§11.1 lists a `bookmarks` table that is not
    ///   created) and two tabs with one URL in one Space are duplicates by any
    ///   reading.
    private func write(
        _ bookmarks: [ImportedBookmark],
        into spaceID: UUID,
        dryRun: Bool
    ) async throws -> (added: Int, skipped: Int) {
        let existing = try await store.tabs(inSpace: spaceID, includeArchived: true)
        var seen = Set(existing.map { Self.dedupKey($0.url) })
        var order = (existing.map(\.order).max() ?? -1) + 1

        var added = 0
        var skipped = 0
        var seenInBatch = Set<String>()

        for bookmark in bookmarks {
            let key = Self.dedupKey(bookmark.url)
            let pathKey = bookmark.folderPath.joined(separator: "/") + "\u{1}" + key
            guard seenInBatch.insert(pathKey).inserted, seen.insert(key).inserted else {
                skipped += 1
                continue
            }
            added += 1
            guard !dryRun else { continue }

            let when = bookmark.dateAdded ?? Date()
            // ponytail: one `upsert` per bookmark, i.e. one transaction each.
            // Fine at the scale this sees — a whole Dia profile is 44 bookmarks.
            // If a 5,000-bookmark import ever turns up, `BrowserStore` wants a
            // bulk `upsert(_ tabs: [Tab])` and this loop becomes one call.
            try await store.upsert(Tab(
                spaceID: spaceID,
                kind: bookmark.placement.tabKind,
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

    private func resolveTargetSpace(
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

        // A dry run creates nothing at all — not the Space, and not the
        // Profile `seedIfEmpty` would stand up underneath it. It reports the id
        // it would have used so a screen can still say where things would land.
        guard !dryRun else { return UUID() }

        // `seedIfEmpty` is a no-op once anything exists; it is here so an
        // import during onboarding — before the user has opened a window — has
        // a Profile to hang the Space off.
        try await store.seedIfEmpty()
        guard let profile = try await store.profiles().first else {
            throw ImportError.unreadable(String(localized: "Luna's own database"))
        }
        let space = Space(
            name: name,
            symbolName: "square.and.arrow.down",
            gradient: .defaultSpace,
            profileID: profile.id,
            order: (spaces.map(\.order).max() ?? -1) + 1
        )
        try await store.upsert(space)
        entry.spaceID = space.id
        return space.id
    }

    // MARK: - Readers

    private func makeReader(_ request: ImportRequest, snapshot: ImportSnapshot) throws -> any ProfileReader {
        guard request.source.isChromiumFamily else {
            return try SafariReader.snapshot(into: snapshot)
        }
        guard
            let root = ChromiumProfileLocator.userDataRoot(
                in: request.source.supportDirectoryURL,
                candidates: request.source.chromiumUserDataCandidates
            )
        else {
            throw ImportError.notInstalled(request.source.displayName)
        }
        let directory = request.profile.directoryName.isEmpty
            ? root
            : root.appending(path: request.profile.directoryName, directoryHint: .isDirectory)
        return try ChromiumReader.snapshot(profileDirectory: directory, into: snapshot)
    }
}
