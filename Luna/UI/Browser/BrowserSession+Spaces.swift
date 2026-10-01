//
//  BrowserSession+Spaces.swift
//  Luna
//
//  The Space half of the coordinator (spec §6): create, rename, reorder,
//  re-icon, re-gradient, delete — and the Favorites tier those
//  operations have to keep whole.
//
//  · Deleting a Space never destroys a tab. Its tabs are archived or adopted
//    into a surviving Space before the Space row goes, because `tabs.spaceID`
//    cascades and a cascade is not undoable.
//  · A Space owns its cookie jar (§9, schema `v7`), so nothing re-points one:
//    a `WKWebView`'s data store is fixed at construction, and re-pointing
//    leaves loaded tabs writing to the old jar (Nook, zen#15023).
//  · No window-close-on-last-tab rule. If one comes it is evaluated over the
//    window, never the visible Space: zen#9272 lost one user ~500 tabs.
//

import AppKit
import BrowserKit
import WebKit

/// What happens to a Space's tabs when the Space goes (§6.3).
///
/// There is no "and delete them" case on purpose: `closeTab` archives, so
/// keeping them costs nothing and losing them cannot be undone.
enum SpaceDeletionPolicy: Sendable, Equatable {
    /// Archive them — still in `⌘⇧T` and in the archive, re-homed onto a
    /// surviving Space so the cascade cannot take their rows.
    case archiveTabs
    /// Move them, still open, into another Space.
    case adopt(into: UUID)
}

extension BrowserSession {

    // MARK: - Reading

    /// A Space's Favorites — §3.3's tier itself (§2).
    func favorites(inSpace id: UUID) -> [Tab] { list.favorites(inSpace: id) }

    /// Arc's cap, and its two other constraints come with it: zero is allowed,
    /// and the tier loads lazily — which Luna gets for free, because a Favorite
    /// holds no `TabController` until it is clicked.
    static let favoritesCap = 12

    // MARK: - Create (§6.1)

    /// A new Space, with a cookie jar of its own, so it starts signed out of
    /// everything.
    ///
    /// The Space lands next to the active one, not at the end (§13.10).
    @discardableResult
    func createSpace(name: String) async throws -> Space {
        let name = try Self.spaceName(from: name)
        let index = spaces.firstIndex { $0.id == activeSpaceID }.map { $0 + 1 } ?? spaces.count
        let space = Space(
            name: name,
            symbolName: Self.defaultSpaceSymbol,
            gradient: nextGradient(spaces.map(\.gradient)),
            order: index
        )
        spaces.insert(space, at: index)
        list.addSpace(space.id)
        try await store.upsert(space)
        try await renumberSpaces()
        switchSpace(space.id)
        startExtensions(inSpace: space.id)
        return space
    }

    /// Picks up what another part of the app wrote straight to the store —
    /// today, §23.2's importer during §30.17's first run.
    ///
    /// Spaces and the tabs in them, because a new Space is not the only thing
    /// an import can land in: the second run from the same browser, or a first
    /// run whose Space name already matched, writes into one this session is
    /// already showing, and a sweep for new Spaces alone leaves those
    /// bookmarks invisible until the next launch.
    ///
    /// Additive on purpose. Nothing here removes, replaces or reloads a row it
    /// already holds, so no open tab is closed and no live web view is torn
    /// down by a refresh it had nothing to do with.
    func adoptSpacesWrittenElsewhere() async throws {
        let known = Set(spaces.map(\.id))
        let onDisk = try await store.spaces()
        let arrived = onDisk.filter { !known.contains($0.id) }
        if !arrived.isEmpty {
            for space in arrived {
                spaces.append(space)
                list.addSpace(space.id)
                startExtensions(inSpace: space.id)
            }
        }
        var adopted = 0
        var held = Set(archived.map(\.id))
        for space in onDisk {
            for tab in try await store.tabs(inSpace: space.id, includeArchived: true) {
                guard list.tab(tab.id) == nil, held.insert(tab.id).inserted else { continue }
                if tab.archivedAt == nil { _ = list.insert(tab) } else { archived.append(tab) }
                adopted += 1
            }
        }
        guard !arrived.isEmpty || adopted > 0 else { return }
        try await renumberSpaces()
        notifyChange()
    }

    // MARK: - Rename, reorder, re-icon, re-gradient (§6.2)

    func renameSpace(_ id: UUID, to name: String) async throws {
        let name = try Self.spaceName(from: name)
        try await mutateSpace(id) { $0.name = name }
    }

    /// The longest name a Space may carry.
    ///
    /// 32, measured against the widest place the app shows one whole: the
    /// Settings card's header, whose label is 278 pt at the pane's 640 pt
    /// minimum and holds 34 characters of ordinary text at
    /// `TypeScale.settingsHeading`. Past that every surface is worse rather
    /// than truncated — `MainMenu`'s Spaces submenu and §30.9's dot menu put
    /// the name in an `NSMenu` item, and a menu does not truncate, it grows.
    ///
    /// `nonisolated` so `SpaceNameFormatter` can read it: a `Formatter`
    /// override is called by AppKit on the main thread but is not declared on
    /// it, and this is a constant with nothing to race over.
    nonisolated static let spaceNameCap = 32

    /// What a typed, pasted or imported name is stored as.
    ///
    /// Capped rather than refused. A name arrives from an import or a paste as
    /// often as from the keyboard, and a shortened name is what the user meant
    /// where an error dialog is not — `SpaceNameFormatter` is what stops the
    /// keyboard reaching this, so the only names arriving long are the ones
    /// nobody typed.
    static func spaceName(from typed: String) throws -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.emptyName }
        // `prefix` counts characters, not code units, so an emoji or a
        // combining accent costs one and never gets cut in half.
        return String(trimmed.prefix(spaceNameCap)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setIcon(_ symbolName: String, forSpace id: UUID) async throws {
        guard !symbolName.isEmpty else { throw SessionError.emptyName }
        try await mutateSpace(id) { $0.symbolName = symbolName }
    }

    func setGradient(_ gradient: GradientPair, forSpace id: UUID) async throws {
        try await mutateSpace(id) { $0.gradient = gradient }
    }

    /// Moves a Space to `index` and renumbers the rest.
    ///
    /// Trivial only because `BrowserStore.spaces()` renumbers drifted order to
    /// `0..<n` on load, so this never has to defend against the gaps a delete
    /// leaves.
    func reorderSpace(_ id: UUID, to index: Int) async throws {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { throw SessionError.unknownSpace }
        let to = min(max(index, 0), spaces.count - 1)
        guard to != from else { return }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: to)
        try await renumberSpaces()
    }

    // MARK: - Favorites (§2)

    /// Arc's cap of 12. The overflow is demoted, never deleted: it becomes a
    /// pinned tab in the Space it already lives in, least recently used first.
    func enforceFavoritesCap(inSpace id: UUID) {
        let favorites = list.favorites(inSpace: id)
        guard favorites.count > Self.favoritesCap else { return }
        for tab in favorites.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).dropFirst(Self.favoritesCap) {
            rehome(tab.id, to: tab.spaceID, as: .pinned, archiving: false)
        }
    }

    // MARK: - Launch

    /// Redirects the sweep away from the disk, and the only way to run it
    /// inside a test; the test receives the identifier set that decides which
    /// stores survive.
    ///
    /// A sink rather than a boolean. Unset — the value the app always has —
    /// the sweep goes to the real `SpaceJarStore`, and only outside a test run.
    /// A flag a test flips would leave the disk reachable, and one test that
    /// forgot to put it back would arm it for every test after; here, switching
    /// the guard off and pointing the sweep somewhere harmless are the same act.
    var orphanSweepSink: ((Set<UUID>) async -> Void)? {
        get { Self.sinks[ObjectIdentifier(self)] }
        set { Self.sinks[ObjectIdentifier(self)] = newValue }
    }

    /// Deletes every `WKWebsiteDataStore` on disk that no Space names, and
    /// drains the deferred-removal queue while it is there (spec §3.1, §3.2).
    ///
    /// `remove(forIdentifier:)` fails while any live `WKWebView` still uses the
    /// store, and a web view goes when ARC says so rather than when the user
    /// clicks Delete — so a removal that loses that race is queued in
    /// `UserDefaults` and finished here on the next launch. Cheap, because
    /// WebKit is the registry: a delete that failed yesterday is still listed
    /// today, so orphan recovery costs one diff (DuckDuckGo relies on the same).
    ///
    /// Once per process, not per session, because a second window sweeping the
    /// same disk would race the first one's removals. Detached so a slow
    /// WebKit answer never delays the first paint.
    func sweepOrphanedProfileStores() {
        // Never from a test, unless the test has routed the sweep away from
        // the disk: a test's database holds two rows, so the sweep would delete
        // the user's real cookie jars. XCTest is loaded in a test run and in
        // nothing else, so it is the one safe thing to key on.
        let sink = orphanSweepSink
        guard sink != nil || NSClassFromString("XCTestCase") == nil else { return }
        // Once per process — but only for the disk. Two windows racing each
        // other's removals is what that rule exists to prevent, and a redirected
        // sweep removes nothing, so it is not what the rule is about.
        if sink == nil {
            guard !Self.hasSweptOrphanStores else { return }
            Self.hasSweptOrphanStores = true
        }
        let store = store
        let spaceJars = spaceJars
        Task {
            // The set is the whole decision: everything WebKit lists and this
            // does not name is deleted. An empty or stale set is not a weaker
            // sweep, it is one that takes the user's live cookie jars.
            guard let live = try? await store.liveDataStoreIdentifiers() else { return }
            guard let sink else { return await spaceJars.sweepOrphans(keeping: live) }
            await sink(live)
        }
    }

    /// Process-wide, because the disk is. Main-actor isolated with the rest of
    /// the session, so "once" means once.
    static var hasSweptOrphanStores = false

    /// Per-session sinks. A stored property cannot live in an extension, and the
    /// alternative is a property on `BrowserSession` itself that reads as app
    /// state rather than as the test seam it is.
    private static var sinks: [ObjectIdentifier: (Set<UUID>) async -> Void] = [:]

    // MARK: - Plumbing
    //
    // Internal rather than private: `BrowserSession+SpaceDeletion.swift` is the
    // other half of this API and Swift's `private` is file-scoped.

    /// Moves one tab to another Space and/or another section, discarding its
    /// web view on the way — it belongs to the source Space's data store and
    /// must not carry those cookies anywhere (§7).
    func rehome(_ id: UUID, to spaceID: UUID, as kind: TabKind, archiving: Bool) {
        guard var tab = list.tab(id) else { return }
        discardController(id)
        recentTabs.removeAll { $0 == id }
        persistAll(list.remove(id))
        tab.spaceID = spaceID
        tab.kind = kind
        guard !archiving else {
            tab.archivedAt = Date()
            archived.insert(tab, at: 0)
            write(tab)
            return
        }
        tab.order = list.nextOrder(kind: kind, in: spaceID)
        persistAll(list.insert(tab))
    }

    private func mutateSpace(_ id: UUID, _ change: (inout Space) -> Void) async throws {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw SessionError.unknownSpace }
        change(&spaces[index])
        try await store.upsert(spaces[index])
        notifyChange()
    }

    /// Rewrites `order` to `0..<n` and persists every Space whose number moved —
    /// the same self-heal `BrowserStore.spaces()` applies on load, done eagerly
    /// so the running window and the database never disagree.
    func renumberSpaces() async throws {
        for (position, space) in spaces.enumerated() where space.order != position {
            spaces[position].order = position
            try await store.upsert(spaces[position])
        }
        notifyChange()
    }

}
