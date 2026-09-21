//
//  BrowserSession+Spaces.swift
//  Luna
//
//  The Space half of the coordinator (spec §6): create, rename, reorder,
//  re-icon, re-gradient, re-profile, delete — and the per-Profile Favorites
//  tier those operations have to keep whole.
//
//  Three things here are not obvious, and they are the reason the file exists:
//
//  · Changing a Space's Profile rebuilds every web view in it. Nook's
//    `assign(spaceId:toProfile:)` sets the field and persists and does nothing
//    else, so every already-loaded tab keeps writing to the old cookie jar
//    until something unloads it; zen#15023 is the same bug with a greyed-out
//    menu item for feedback. A `WKWebView`'s data store is fixed at
//    construction, so the only honest fix is Ora's: destroy, recreate, restore
//    the transient state. `interactionState` survives — it is the tab's
//    back/forward history and scroll position, not the store's. The session
//    does not: the user is logged out in that Space, and the UI has to say so
//    before the call, not after.
//
//  · Deleting a Space never destroys a tab. `.archiveTabs` archives them
//    (`closeTab` already does, so it is nearly free) and `.adopt(into:)`
//    re-homes them. Either way the rows move to a surviving Space before the
//    Space row goes, because `tabs.spaceID` cascades and a cascade is not
//    undoable. Vivaldi closes the tabs with no undo; Arc has no documented undo
//    anywhere in three years of release notes.
//
//  · Favorites belong to the Profile (§2, and the owner's locked decision).
//    An `.essential` row still keeps a home Space for the foreign key, so every
//    operation that removes or re-points a Space re-homes the Profile's
//    Favorites onto a Space that survives it first — `keepFavorites(ofSpace:)`.
//
//  Not here, deliberately: no window-close-on-last-tab rule. When one comes it
//  is evaluated over the window, never the visible Space. zen#9272 took the
//  other path, quit the browser while another Space still held five tabs by the
//  window-close route rather than a session end, and one user lost ~500 tabs.
//  floorp#2152 is the same bug, still open.
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

    /// Which Spaces share a Profile — the fan-out C's Settings label needs, and
    /// the set every Favorites operation is scoped to. Arc has no UI anywhere
    /// showing this, and it is the root of the most-reported conceptual
    /// confusion in every review of it.
    func spaces(onProfile id: UUID) -> [Space] {
        spaces.filter { $0.profileID == id }
    }

    /// The Profile a tab's cookies actually belong to.
    ///
    /// Derived from the tab's home Space rather than read off the row. A
    /// `tabs.profileID` column is specified to agent A and is the durable
    /// model; when it lands, this is the one line that changes.
    func profileID(ofTab id: UUID) -> UUID? {
        list.tab(id).flatMap { space($0.spaceID)?.profileID }
    }

    /// A Profile's Favorites — the per-Profile tier itself (§2). Every Space on
    /// the Profile shows exactly this list.
    func favorites(onProfile id: UUID) -> [Tab] { list.favorites(onProfile: id) }

    /// Arc's cap, and its two other constraints come with it: zero is allowed,
    /// and the tier loads lazily — which Luna gets for free, because a Favorite
    /// holds no `TabController` until it is clicked.
    static let favoritesCap = 12

    // MARK: - Create (§6.1)

    /// A new Space, optionally sharing an existing Profile.
    ///
    /// `profileID: nil` mints a fresh Profile, which is what every Space got
    /// before this existed — so many-Spaces-to-one-Profile was modelled in the
    /// schema and unreachable from the app. Passing an existing id is how Work
    /// and Work Admin end up in one cookie jar.
    ///
    /// The Space lands next to the active one, not at the end (§13.10).
    @discardableResult
    func createSpace(name: String, profileID: UUID? = nil) async throws -> Space {
        let profile: Profile
        if let profileID {
            guard let existing = profiles[profileID] else { throw SessionError.unknownProfile }
            profile = existing
        } else {
            profile = Profile(name: name)
            try await store.upsert(profile)
            profiles[profile.id] = profile
        }

        let index = spaces.firstIndex { $0.id == activeSpaceID }.map { $0 + 1 } ?? spaces.count
        let space = Space(
            name: name,
            symbolName: Self.defaultSpaceSymbol,
            gradient: nextGradient(spaces.map(\.gradient)),
            profileID: profile.id,
            order: index
        )
        spaces.insert(space, at: index)
        list.addSpace(space.id, profileID: profile.id)
        try await store.upsert(space)
        try await renumberSpaces()
        switchSpace(space.id)
        return space
    }

    // MARK: - Rename, reorder, re-icon, re-gradient (§6.2)

    func renameSpace(_ id: UUID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.emptyName }
        try await mutateSpace(id) { $0.name = trimmed }
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
    /// leaves. That self-heal is the one good idea in this area in any project
    /// researched; reordering itself is implemented in none of them.
    func reorderSpace(_ id: UUID, to index: Int) async throws {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { throw SessionError.unknownSpace }
        let to = min(max(index, 0), spaces.count - 1)
        guard to != from else { return }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: to)
        try await renumberSpaces()
    }

    // MARK: - Changing a Space's Profile (§3.3)

    /// Re-points a Space at another Profile **and rebuilds every web view in
    /// it**, which is the half everybody else skips.
    ///
    /// The rebuild is not cosmetic: a `WKWebView`'s `websiteDataStore` is fixed
    /// when it is constructed, so a tab loaded before the switch keeps reading
    /// and writing the old Profile's cookies for as long as its web view
    /// lives. Setting the field without rebuilding is a silent cross-profile
    /// leak. Warn with ``crossProfileMoveWarning`` before calling this.
    func setProfile(_ profileID: UUID, forSpace id: UUID) async throws {
        guard let space = space(id) else { throw SessionError.unknownSpace }
        guard profiles[profileID] != nil else { throw SessionError.unknownProfile }
        guard space.profileID != profileID else { return }
        let previous = space.profileID

        // Favorites are the old Profile's, not this Space's. They stay with it
        // if it still has somewhere to live; if this was its last Space they
        // come along, and the cap is re-checked on the far side.
        keepFavorites(ofSpace: id, onProfile: previous)

        // Which tabs were awake, so the same ones are awake afterwards. Every
        // controller goes, live or cold: a cold one still holds the old store
        // and would hand it to the next `activate()`.
        let live = list[id].filter { controllers[$0.id] != nil }.map(\.id)
        let wasActive = activeTabBySpace[id]
        for tab in list[id] { discardController(tab.id) }

        try await mutateSpace(id) { $0.profileID = profileID }
        list.setProfile(profileID, forSpace: id)

        // Rebuilt against the new Profile's store: `ensureController` asks
        // `dataStore(forSpace:)` afresh, and the `Tab` still carries the
        // `interactionState` blob `discardController` cached on its way out.
        for tabID in live {
            guard let tab = list.tab(tabID) else { continue }
            _ = ensureController(for: tab)
        }
        if let wasActive, list.tab(wasActive) != nil { activateTab(wasActive) }

        enforceFavoritesCap(onProfile: profileID)
        try await discardProfileIfUnused(previous)
        notifyChange()
    }

    // MARK: - Favorites (§2)

    /// Moves the Favorites homed in `spaceID` onto another Space of the same
    /// Profile, so losing or re-pointing this Space does not lose the Profile's
    /// tiles. A no-op when this is the Profile's only Space — the tiles then
    /// travel with it, which is the only place left for them to go.
    func keepFavorites(ofSpace spaceID: UUID, onProfile profileID: UUID) {
        guard let survivor = spaces.first(where: { $0.id != spaceID && $0.profileID == profileID }) else { return }
        for favorite in list[spaceID] where favorite.kind == .essential && favorite.spaceID == spaceID {
            rehome(favorite.id, to: survivor.id, as: .essential, archiving: false)
        }
    }

    /// Arc's cap of 12, applied to a Profile whose tiles have just been pooled
    /// with another's. The overflow is demoted, never deleted: it becomes a
    /// pinned tab in the Space it already lives in, least recently used first.
    func enforceFavoritesCap(onProfile id: UUID) {
        let favorites = list.favorites(onProfile: id)
        guard favorites.count > Self.favoritesCap else { return }
        for tab in favorites.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).dropFirst(Self.favoritesCap) {
            rehome(tab.id, to: tab.spaceID, as: .pinned, archiving: false)
        }
    }

    // MARK: - Launch

    /// Deletes every `WKWebsiteDataStore` on disk that no Profile names, and
    /// drains the deferred-removal queue while it is there (spec §3.1, §3.2).
    ///
    /// This is the one call that makes store deletion eventually consistent.
    /// `remove(forIdentifier:)` fails while any live `WKWebView` still uses the
    /// store, and a web view goes away when ARC says so rather than when the
    /// user clicks Delete — so a removal that loses that race is queued in
    /// `UserDefaults` and finished here, on the next launch, when nothing is
    /// holding anything. Without it the queue is written and never read.
    ///
    /// Cheap, because WebKit is the registry: a delete that failed yesterday is
    /// still listed today, so orphan recovery costs one diff. DuckDuckGo relies
    /// on exactly this — *"If this fails, we are going to still clean them next
    /// time as WebKit keeps track of all stores for us."*
    ///
    /// Launch work, not window work: it runs once per process even though a
    /// `BrowserSession` is per window, because a second window sweeping the same
    /// disk would race the first one's removals. Detached from the launch path
    /// so a slow WebKit answer never delays the first paint.
    /// Redirects the sweep away from the disk, and is the only way to make
    /// it run inside a test.
    ///
    /// The two safety rules this shape encodes, and why it is a sink rather than
    /// a boolean:
    ///
    /// · The default is safe. Unset — the value the app always has — the
    ///   sweep goes to the real `ProfileStore`, and only when the process is not
    ///   a test run.
    /// · "Sweep the real disk from a test" is unspellable. A flag the test
    ///   flips would leave the disk reachable, and one test that forgot to put
    ///   the flag back would arm it for every test after it. Here, switching the
    ///   guard off and pointing the sweep somewhere harmless are the same act:
    ///   there is no argument to this API that lets a test reach
    ///   `WKWebsiteDataStore.remove(forIdentifier:)`.
    ///
    /// What a test gains is the thing worth asserting — the identifier set that
    /// was handed over, which is what decides which stores survive.
    var orphanSweepSink: ((Set<UUID>) async -> Void)? {
        get { Self.sinks[ObjectIdentifier(self)] }
        set { Self.sinks[ObjectIdentifier(self)] = newValue }
    }

    func sweepOrphanedProfileStores() {
        // Never from a test, unless the test has already routed the sweep
        // away from the disk. The sweep deletes every store on disk that this
        // session's database does not name, and a test's database is a temporary
        // file holding two rows — so a test that installed the lifecycle would
        // delete the user's real cookie jars and call it orphan recovery. The
        // only safe thing to key on is the harness itself: XCTest is loaded in a
        // test run and in nothing else.
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
        let profileStore = profileStore
        Task {
            // The set is the whole decision: everything WebKit lists and this
            // does not name is deleted. An empty or stale one is not a weaker
            // sweep, it is a sweep that takes the user's live cookie jars.
            guard let live = try? await store.liveDataStoreIdentifiers() else { return }
            guard let sink else { return await profileStore.sweepOrphans(keeping: live) }
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

    /// Removes a Profile's store and its row once no Space names it (§6.3).
    func discardProfileIfUnused(_ id: UUID) async throws {
        guard let profile = profiles[id], !spaces.contains(where: { $0.profileID == id }) else { return }
        try await profileStore.remove(profile)
        profiles[id] = nil
        try await store.delete(profileID: id)
    }
}
