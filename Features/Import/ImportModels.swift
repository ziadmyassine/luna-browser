//
//  ImportModels.swift
//  Luna — §23.2
//
//  The neutral value types every reader produces and the importer consumes.
//  Nothing here touches the disk, the store or AppKit, so a reader can be
//  tested against a fixture the test builds itself.
//

import BrowserKit
import Foundation

/// What an import is allowed to touch. Deliberately two cases: the reference
/// screen (§30.18) promises "bookmarks, history, and extensions" and we cannot
/// import extensions — §16.2 has no store and §16.5 has no parity guarantee.
/// Every string this engine exposes says "bookmarks and history".
struct ImportSurfaces: OptionSet, Sendable, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let bookmarks = ImportSurfaces(rawValue: 1 << 0)
    static let history = ImportSurfaces(rawValue: 1 << 1)
    static let all: ImportSurfaces = [.bookmarks, .history]

    /// The copy a screen should show. Never mentions extensions or passwords.
    var localizedDescription: String {
        switch self {
        case .bookmarks: String(localized: "Bookmarks")
        case .history: String(localized: "History")
        default: String(localized: "Bookmarks and history")
        }
    }
}

/// Where a bookmark sits in the source browser, which decides its `TabKind`.
enum BookmarkPlacement: String, Sendable, Hashable {
    /// A loose URL directly on the bookmarks bar — the handful of sites reached
    /// in one click. Lands as `.essential` (§7.1, §11.4's "Favorites").
    case favorite
    /// Anything inside a folder, or under "Other"/"Mobile". Lands as `.pinned`.
    case folder

    var tabKind: TabKind {
        self == .favorite ? .essential : .pinned
    }
}

/// One bookmark, flattened out of whatever tree it came from.
///
/// `folderPath` is carried even though Luna has nowhere to persist it yet
/// (§11.1 lists a `bookmarks` table that is not created): the Netscape HTML
/// export rebuilds the tree from it, and it is what the future table needs.
struct ImportedBookmark: Sendable, Hashable {
    var url: URL
    var title: String
    var dateAdded: Date?
    var folderPath: [String]
    var placement: BookmarkPlacement
    /// The name of the source's own Space this belongs to, for the two
    /// browsers that have Spaces — nil everywhere else, meaning "the one Space
    /// this import is making".
    ///
    /// Read only by a reader that `keepsItsOwnStructure`. A Chromium
    /// `Bookmarks` file has no Spaces in it, and §3.4b puts one import in one
    /// folder, so for every other source this stays nil and the tree is
    /// flattened on write.
    var spaceName: String?

    init(
        url: URL,
        title: String,
        dateAdded: Date? = nil,
        folderPath: [String] = [],
        placement: BookmarkPlacement = .folder,
        spaceName: String? = nil
    ) {
        self.url = url
        self.title = title
        self.dateAdded = dateAdded
        self.folderPath = folderPath
        self.placement = placement
        self.spaceName = spaceName
    }

    /// A saved address, or nil for anything that is not plain web content.
    ///
    /// Stricter than `ChromiumImport`'s `scheme != nil`, and deliberately: a
    /// `Bookmarks` file holds what the user bookmarked, but a browser's own
    /// sidebar holds its own furniture too — `arc://`, `dia://`, a new-tab
    /// page. None of those is an address Luna can open, so a row for one would
    /// be a tab that goes nowhere in the folder the import just made.
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https", url.host()?.isEmpty == false else { return nil }
        return url
    }
}

/// One visit, one row of `visits` in the source browser.
struct ImportedVisit: Sendable, Hashable {
    var url: URL
    var title: String
    var kind: VisitKind
    var at: Date
    /// The source's own ordering key, used as the re-import watermark. For
    /// Chromium this is `visits.visit_time` in microseconds since 1601.
    var sourceStamp: Int64
}

/// One keyset page of visits, as a reader hands them over.
///
/// `lastRowID` advances past every row scanned, including the ones that were
/// dropped as unreadable — paging on the last usable row would loop forever on
/// a bad row.
struct VisitPage: Sendable {
    var visits: [ImportedVisit] = []
    var lastRowID: Int64 = 0
    var isLast: Bool = true

    static let empty = VisitPage()
}

/// What the importer is doing, for a progress bar. `total == nil` means the
/// count is not knowable up front without a second full scan.
struct ImportProgress: Sendable, Hashable {
    enum Phase: String, Sendable {
        case copying, bookmarks, history, finishing
    }

    var phase: Phase
    var completed: Int
    var total: Int?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

/// The result of a run, and — with `isDryRun` — of a preview of one.
///
/// `failed` plus `warnings` is the malformed-input contract: an import never
/// throws on a single bad row, it counts it and carries on.
struct ImportSummary: Sendable, Hashable {
    var isDryRun: Bool = false
    var bookmarksAdded: Int = 0
    /// Already present in the target Space, by URL. The idempotency evidence:
    /// a second run reports every bookmark here and adds none.
    var bookmarksSkipped: Int = 0
    var visitsAdded: Int = 0
    /// Visits older than the watermark of a previous import of this profile.
    var visitsSkipped: Int = 0
    var failed: Int = 0
    var warnings: [String] = []
    /// The Space everything landed in, so a screen can offer "show me". The
    /// first of them when the source brought its own Spaces (§23.2 — Arc).
    var targetSpaceID: UUID?
    /// How many Spaces the import made or wrote into. One for every source but
    /// Arc, whose sidebar has Spaces of its own.
    var spacesTouched: Int = 0
}

enum ImportError: LocalizedError, Equatable {
    case notInstalled(String)
    case noProfiles(String)
    /// TCC, not the sandbox: `~/Library/Safari` is `EPERM` even for an
    /// unsandboxed binary, and no entitlement changes that. Verified on this
    /// machine 2026-09-17 — see §23.2.
    case needsFullDiskAccess(String)
    case unreadable(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(name):
            String(localized: "\(name) isn't installed on this Mac.")
        case let .noProfiles(name):
            String(localized: "\(name) has no profiles Luna can read.")
        case let .needsFullDiskAccess(name):
            String(localized: """
            \(name)'s bookmarks and history are protected by macOS. Grant Luna Full Disk Access in \
            System Settings, or export a bookmarks HTML file from \(name) and import that instead.
            """)
        case let .unreadable(file):
            String(localized: "Luna couldn't read \(file).")
        case let .malformed(file):
            String(localized: "\(file) isn't in a format Luna understands. The browser may have changed it.")
        }
    }
}

/// One import, fully specified. A screen builds this from its two panes.
struct ImportRequest: Sendable, Hashable {
    var source: ImportSource
    /// For Safari, or any single-profile layout, `ChromiumProfile(directoryName: "")`.
    var profile: ChromiumProfile
    var surfaces: ImportSurfaces = .all
    /// Where bookmarks land. `nil` reuses the Space a previous import of this
    /// profile created, or makes one named after the profile.
    var targetSpaceID: UUID?

    /// The Space name a fresh import creates. "Dia — Main", not "Profile 1":
    /// on this Mac Dia's `Default` is called "Work" and `Profile 1` is "Main",
    /// so the directory name is never the right thing to show.
    var spaceName: String {
        let label = profile.label(for: source)
        return label == source.displayName ? source.displayName : "\(source.displayName) — \(label)"
    }
}

/// Remembers what has already been imported, so a second run is a no-op.
///
/// A small JSON file rather than `UserDefaults` for one reason: a test can
/// point it at a temporary directory and get a real, empty ledger.
struct ImportLedger: Sendable {
    struct Entry: Codable, Sendable {
        /// Newest source timestamp already imported, in microseconds. Chromium
        /// counts from 1601 and Safari from 2001, which is why the ledger key
        /// includes the source — the numbers are not comparable across them.
        var historyWatermark: Int64 = 0
        var spaceID: UUID?
    }

    let fileURL: URL

    static var standard: ImportLedger {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return ImportLedger(fileURL: support
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "import-ledger.json"))
    }

    static func key(_ request: ImportRequest) -> String {
        "\(request.source.rawValue)/\(request.profile.directoryName)"
    }

    func entries() -> [String: Entry] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    func entry(_ key: String) -> Entry {
        entries()[key] ?? Entry()
    }

    /// Best-effort: a ledger that cannot be written costs a duplicated history
    /// import next time, which is a smaller loss than failing a completed one.
    func save(_ entry: Entry, for key: String) {
        var all = entries()
        all[key] = entry
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
