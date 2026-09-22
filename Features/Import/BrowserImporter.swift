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
//  1. Idempotent. Bookmarks are deduplicated against the target Space by URL,
//     read from the store rather than remembered; history by a per-profile
//     watermark in `ImportLedger`, so a second run asks the source only for
//     visits newer than the newest one already taken.
//  2. Never blocking, never hogging the store. Everything runs on
//     `BrowserImporter`'s own actor, and visits cross to `BrowserStore` in
//     batches of 500 with a `flush()` between them (§11.5), so the store's
//     actor is entered and left per batch rather than held for the whole
//     import.
//  3. Malformed input is the normal case. A truncated `Bookmarks`, a locked or
//     corrupt `History`, a bookmarks tree deeper than anything sane: each fails
//     its own surface, is counted in `ImportSummary.failed` with a line in
//     `warnings`, and the rest of the import still lands.
//
//  Not imported, deliberately: passwords (§23.2 — Keychain-encrypted and
//  out of scope) and extensions (§30.18's copy warning — there is no store
//  and no parity guarantee, so no string here may promise them).
//

import BrowserKit
import Foundation

actor BrowserImporter {
    /// Not private: `BrowserImporter+Placement` is the other half of this
    /// actor and does the writing.
    let store: BrowserStore
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
            // The browser, not the profile inside it: a folder called "Chrome"
            // is what the user came looking for, and two of that browser's
            // profiles belong in the same one.
            folderName: request.source.displayName,
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
        folderName: String? = nil,
        surfaces: ImportSurfaces = .all,
        targetSpaceID: UUID? = nil,
        dryRun: Bool = false,
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async throws -> ImportSummary {
        var summary = ImportSummary(isDryRun: dryRun)
        var entry = ledger.entry(ledgerKey)

        // One Space for the whole import. Since `v8` an imported visit joins a
        // Space's history the way an imported bookmark joins its tabs, and two
        // answers to "which Space" is how the two halves of one import come
        // apart.
        //
        // Still resolved by whichever surface needs it first rather than up
        // front, because a browser with nothing to give must not leave an empty
        // Space behind.
        var target: UUID?

        // Bookmarks first: bounded, and what the user actually looks for. A
        // history import cancelled halfway has still delivered them.
        if surfaces.contains(.bookmarks) {
            progress?(ImportProgress(phase: .bookmarks, completed: 0, total: nil))
            target = await importBookmarks(
                reader: reader,
                names: Names(space: spaceName, folder: folderName ?? spaceName, explicit: targetSpaceID),
                entry: &entry,
                into: &summary,
                dryRun: dryRun
            )
        }

        if surfaces.contains(.history) {
            // The first Space the import made, which for a sidebar is the one
            // the source lists first. A browser's `History` is one file per
            // profile and says nothing about which of its Spaces a visit
            // happened in, so it cannot be split between them — and putting
            // the same 70,000 visits in each would be worse than choosing one.
            if target == nil {
                target = try await resolveTargetSpace(explicit: targetSpaceID, name: spaceName, entry: &entry, dryRun: dryRun)
                summary.targetSpaceID = target
                summary.spacesTouched = max(summary.spacesTouched, 1)
            }
            await importHistory(
                reader: reader,
                entry: &entry,
                target: ImportTarget(space: target, dryRun: dryRun),
                into: &summary,
                progress: progress
            )
        }

        progress?(ImportProgress(phase: .finishing, completed: summary.visitsAdded, total: nil))
        if !dryRun { ledger.save(entry, for: ledgerKey) }
        return summary
    }

    /// Where an import is putting things: the Space everything lands in, and
    /// whether this run is only rehearsing.
    ///
    /// `space` is nil only if the caller never resolved one, and a visit that
    /// arrives without a Space is in no Space's history at all.
    private struct ImportTarget {
        var space: UUID?
        var dryRun: Bool
    }

    private func importHistory(
        reader: any ProfileReader,
        entry: inout ImportLedger.Entry,
        target: ImportTarget,
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

                if !target.dryRun {
                    // One store transaction per page, not per visit (§11.5):
                    // `recordVisit` buffers and `flush` commits the batch, so
                    // the store's actor is entered and left per page rather
                    // than held for the whole import.
                    for visit in page.visits {
                        try await store.recordVisit(
                            url: visit.url,
                            title: visit.title,
                            kind: visit.kind,
                            at: visit.at,
                            inSpace: target.space
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
        let result = try await write(
            bookmarks,
            into: spaceID,
            // The file's own name. There is no browser to ask — an HTML export
            // says nothing about who wrote it — and the name the user saved it
            // under is the nearest true thing.
            folder: name.isEmpty ? String(localized: "Imported") : name,
            dryRun: dryRun
        )
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
        // Arc's and Dia's own saved tabs, which live beside `User Data` rather
        // than in the profile — the whole of what Arc saves, and the only
        // non-empty half of what Dia does.
        let sidebar = Self.sidebar(for: request)
        return try ChromiumReader.snapshot(
            profileDirectory: directory,
            sidebar: sidebar,
            sidebarFile: sidebar.map { request.source.supportDirectoryURL.appending(path: $0.fileName) },
            into: snapshot
        )
    }

    private static func sidebar(for request: ImportRequest) -> ChromiumReader.SidebarSource? {
        guard let name = request.source.sidebarFileName else { return nil }
        switch request.source {
        case .arc: return .arc(fileName: name)
        case .dia: return .dia(fileName: name, profileDirectory: request.profile.directoryName)
        default: return nil
        }
    }
}
