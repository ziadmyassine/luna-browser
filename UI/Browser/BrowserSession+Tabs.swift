//
//  BrowserSession+Tabs.swift
//  Luna
//
//  The tab half of the coordinator: selection, the §6 lifecycle (open,
//  archive, reorder, move, reopen), navigation, and the write path everything
//  else persists through.
//
//  Ordering rules are not here — they are `TabList`'s, so that "which index
//  does a drop mean" has exactly one answer and can be tested without a window.
//

import AppKit
import BrowserKit

extension BrowserSession {

    // MARK: - Lifecycle (§6)

    func activateTab(_ id: UUID) {
        guard var tab = list.tab(id) else { return }
        // §14: the picker is anchored to a field in the page being left, and
        // the chip asks about a sign-in on it. Both are meaningless over a
        // different tab, and the picker would be actively misleading —
        // pointing at coordinates that now belong to someone else's form.
        if activeTabID != id { passwordUI.dismissAll() }
        activeTabBySpace[tab.spaceID] = id
        promote(id)
        tab.lastActiveAt = Date()
        write(tab)
        ensureController(for: tab).activate()
        enforceLiveTabBudget()
        notifyChange()
    }

    @discardableResult
    func newTab(url: URL?, kind: TabKind = .today) -> UUID {
        let tab = Tab(
            spaceID: activeSpaceID,
            kind: kind,
            url: url ?? Self.blankPage,
            order: list.nextOrder(kind: kind, in: activeSpaceID)
        )
        persistAll(list.insert(tab, at: TabList.openIndex(for: kind)))
        // A URL Luna opens on the user's behalf is a typed visit; a link click
        // reaches us through the engine instead (§9.3).
        if url != nil { pendingVisitKind[tab.id] = .typed }
        activateTab(tab.id)
        return tab.id
    }

    /// Archives the tab — §6.3's soft delete, which keeps title, URL and icon —
    /// and releases its web view. Undoable.
    ///
    /// A pinned tab cannot be closed, only unpinned: closing one leaves the
    /// tile and sends it home — see `sendTileHome`. So `⌘W` on a pinned tab is
    /// "I am finished with this page", not "throw it out".
    func closeTab(_ id: UUID) {
        guard let index = list.indexInSection(of: id), var tab = list.tab(id) else { return }
        if tab.kind == .essential {
            sendTileHome(id, in: tab.spaceID)
            return
        }
        // Read before the removal, while the closing tab still has neighbours.
        let successor = rowBelow(id, in: tab.spaceID)
        tab.archivedAt = Date()
        forget(id)
        persistAll(list.remove(id))
        write(tab)
        if activeTabBySpace[tab.spaceID] == id {
            activeTabBySpace[tab.spaceID] = successor
                ?? recentTabs.first { list.tab($0)?.spaceID == tab.spaceID }
        }
        archived.insert(tab, at: 0)
        registerUndo("Close Tab") { $0.restoreArchived(tab, at: index) }
        notifyChange()
    }

    /// Where the selection goes when the tab showing is closed: **the row
    /// under it in §3.4's list**, or the row above it when it was the last one.
    ///
    /// It used to be the most recently used tab in the Space, which is a
    /// different question and a worse answer here. Closing a run of tabs from
    /// the top sent the selection somewhere down the list and the next `⌘W`
    /// closed that one instead, so the list unravelled from two ends at once;
    /// and with §3.4 stacking today's tabs newest-first, the recent tab is very
    /// often the one above, which reads as the list moving backwards.
    ///
    /// The list's own order is the one thing the user can see, so the answer is
    /// read straight off it — Favorites excluded, because those are §3.3's grid
    /// rather than rows, and a closed row must not select a tile.
    private func rowBelow(_ id: UUID, in spaceID: UUID) -> UUID? {
        let rows = list[spaceID].filter { $0.kind != .essential }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        return (rows.dropFirst(index + 1).first ?? rows[..<index].last)?.id
    }

    /// `⌘⇧T`. The archive is seeded from SQLite at restore, so this still works
    /// on the first keystroke after a relaunch.
    func reopenLastArchived() {
        guard let newest = archived.first else { return }
        restoreArchived(newest, at: TabList.openIndex(for: newest.kind))
    }

    /// §6.4 / §9.2: pull one specific tab back out of the archive.
    ///
    /// - Parameter resumingSession: whether the tab comes back **where it was
    ///   left** — its back/forward list and its scroll position, which is what
    ///   `interactionState` carries. True for the two gestures that mean
    ///   "reopen the tab I closed" (`⌘⇧T` and §11's list), and false for §9's
    ///   Command Bar.
    ///
    ///   The bar is an address bar: its rows are places, and the archive's rows
    ///   sit in the same list as history's and look exactly like them. Choosing
    ///   one and landing half way down the page you were on last week is the
    ///   session resuming behind a gesture that never asked for it — which is
    ///   what Martin hit on an `iPhone 18 Pro` row. Same tab, same Space, same
    ///   name; it simply starts at the top of the page.
    func unarchiveTab(_ id: UUID, resumingSession: Bool = true) {
        guard var tab = archived.first(where: { $0.id == id }) else { return }
        if !resumingSession { tab.interactionState = nil }
        restoreArchived(tab, at: TabList.openIndex(for: tab.kind))
    }

    /// Every tab this window knows about, across all Spaces — `tabs` is the
    /// active Space only. The Command Bar's cross-Space switching and its
    /// archive rows (§9.2) are the reason this exists.
    /// De-duplicated: Favorites are per Profile (§2), so every Space sharing a
    /// Profile resolves the same tiles and a plain `flatMap` would list each of
    /// them once per Space — which the Command Bar would show as duplicate
    /// switch-to-tab rows for the same tab.
    func allTabs(includeArchived: Bool) -> [Tab] {
        var seen: Set<UUID> = []
        let open = spaces.flatMap { list[$0.id] }.filter { seen.insert($0.id).inserted }
        return includeArchived ? open + archived : open
    }

    /// - Parameter index: position within `kind`'s section, not within
    ///   `tabs`. Sections run essential → pinned → today.
    func reorderTab(_ id: UUID, to index: Int, kind: TabKind) {
        guard var tab = list.tab(id), let oldIndex = list.indexInSection(of: id) else { return }
        let oldKind = tab.kind
        // Deliberately not `forget`: reordering a tab must not cost its web view.
        // Persisted, not discarded: pulling a tab out of the Favorites tier
        // renumbers that tier across the whole Profile, and some of the rows it
        // renumbers live in other Spaces.
        persistAll(list.remove(id))
        tab.kind = kind
        persistAll(list.insert(tab, at: index))
        registerUndo("Move Tab") { $0.reorderTab(id, to: oldIndex, kind: oldKind) }
        notifyChange()
    }

    /// True when moving this tab into that Space crosses a Profile
    /// boundary — the case that costs the user their session, and the one that
    /// must never happen silently. Ask before `moveTab`, and say
    /// ``crossProfileMoveWarning``.
    func moveCrossesProfileBoundary(_ id: UUID, toSpace spaceID: UUID) -> Bool {
        guard let from = profileID(ofTab: id), let to = space(spaceID)?.profileID else { return false }
        return from != to
    }

    /// Arc's wording, which is the best of the four researched: Firefox refuses
    /// the operation outright with a 500-word essay, Chrome refuses it in a
    /// comment (`// Profiles must be the same.`), and Zen allows it silently and
    /// it does not work (zen#11268).
    static let crossProfileMoveWarning = String(localized: """
    This Space uses a different profile. You could be logged out of an account if you're not \
    logged into it in the other profile.
    """)

    func moveTab(_ id: UUID, toSpace spaceID: UUID) {
        guard var tab = list.tab(id), tab.spaceID != spaceID,
              spaces.contains(where: { $0.id == spaceID }) else { return }
        let from = tab.spaceID
        let oldIndex = list.indexInSection(of: id) ?? 0
        let oldKind = tab.kind
        // A Favorite is a login tile and Favorites belong to the Profile (§2),
        // so one carried across a Profile boundary lands as a pinned tab rather
        // than joining another cookie jar's tiles.
        if oldKind == .essential, moveCrossesProfileBoundary(id, toSpace: spaceID) {
            tab.kind = .pinned
        }
        // The web view belongs to the old Space's data store; it has to die here
        // or the tab would carry the old profile's cookies across (§5.1).
        discardController(id)
        persistAll(list.remove(id))
        tab.spaceID = spaceID
        tab.order = list.nextOrder(kind: tab.kind, in: spaceID)
        persistAll(list.insert(tab))
        if activeTabBySpace[from] == id {
            activeTabBySpace[from] = recentTabs.first { list.tab($0)?.spaceID == from }
        }
        registerUndo("Move Tab to Space") { session in
            session.moveTab(id, toSpace: from)
            session.reorderTab(id, to: oldIndex, kind: oldKind)
        }
        notifyChange()
    }

    /// - Parameter index: where in its section it goes back, or nil for the
    ///   end of it. Undo hands over the index it was closed from; reopening
    ///   from the archive has no such memory and is simply a tab opening now.
    private func restoreArchived(_ tab: Tab, at index: Int?) {
        var restored = tab
        restored.archivedAt = nil
        // A Favorite can reach the archive by one route only — its Space was
        // deleted and the Profile had no other Space to keep it in — and the
        // Profile it comes back to may have filled the twelve since. Coming back
        // as a pinned tab is the honest answer; silently making a thirteenth
        // tile is not.
        if restored.kind == .essential,
           let profileID = space(restored.spaceID)?.profileID,
           favorites(onProfile: profileID).count >= Self.favoritesCap {
            restored.kind = .pinned
        }
        archived.removeAll { $0.id == tab.id }
        persistAll(list.insert(restored, at: index))
        registerUndo("Close Tab") { $0.closeTab(restored.id) }
        activateTab(restored.id)
    }

    /// Everything a tab costs while it is open: its web view and its caches.
    private func forget(_ id: UUID) {
        discardController(id)
        recentTabs.removeAll { $0 == id }
        // §3.4a's mute is a fact about a live page, and this tab no longer has one. A
        // reopened tab comes back audible, which is the same answer a relaunch gives.
        mutedTabIDs.remove(id)
        faviconPNG[id] = nil
        recordedURL[id] = nil
        pendingVisitKind[id] = nil
    }

    // MARK: - Views

    /// The tab's content view, waking it if it is cold. Call it for the
    /// selected tab only — calling it for any other is precisely the §19.4
    /// violation the hibernation budget exists to prevent.
    func webView(for id: UUID) -> NSView? {
        guard let tab = list.tab(id) else { return nil }
        let controller = ensureController(for: tab)
        controller.activate()
        return controller.webView
    }

    /// The live controller, or nil for a hibernated tab. Never creates one: a
    /// cold tab's title, URL and tint live on its `Tab`, which is what a row
    /// should be reading anyway.
    func controller(for id: UUID) -> TabController? { controllers[id] }

    func tab(_ id: UUID) -> Tab? { list.tab(id) }

    /// A tab's icon — from this session, else the on-disk cache (§4.7).
    func favicon(for id: UUID) -> NSImage? {
        let png = faviconPNG[id] ?? list.tab(id)?.url.host().flatMap { FaviconService.shared.favicon(forHost: $0) }
        return png.flatMap(NSImage.init(data:))
    }

    // MARK: - Navigation

    /// Navigates the active tab, opening one if the window is empty — the
    /// Command Bar's commit path (§9.2).
    func load(_ url: URL) {
        guard let id = activeTabID, let tab = list.tab(id) else {
            newTab(url: url, kind: .today)
            return
        }
        pendingVisitKind[id] = .typed
        ensureController(for: tab).load(url)
    }

    func reload() { activeController?.reload() }
    func stop() { activeController?.stop() }
    func goBack() { activeController?.goBack() }
    func goForward() { activeController?.goForward() }

    /// `⌘⌥←` / `⌘⌥→` (§7.4). Wraps: a browser's tab list is a ring.
    func selectAdjacentTab(offset: Int) {
        let tabs = tabs
        guard !tabs.isEmpty else { return }
        let current = activeTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? 0
        let next = ((current + offset) % tabs.count + tabs.count) % tabs.count
        activateTab(tabs[next].id)
    }

    func search(_ query: String, limit: Int) async -> [HistoryHit] {
        (try? await store.searchHistory(query, limit: limit)) ?? []
    }

    var activeController: TabController? { activeTabID.flatMap { controllers[$0] } }

    // MARK: - Persistence

    /// Captures every live tab's session blob, writes it, and drains the write
    /// queue. Called on quit and on resign-active — `interactionState` reads
    /// back nil once the WebContent process is gone, so reading it late means
    /// reading nothing (§6.2).
    func persist() async {
        for (id, controller) in controllers {
            guard var tab = list.tab(id) else { continue }
            tab.interactionState = controller.captureInteractionState()
            write(tab)
        }
        await writeChain?.value
    }

    /// Releases every web view. Call before the app's last run-loop turn so
    /// WebContent processes die while AppKit is still up.
    func tearDown() {
        for id in controllers.keys { discardController(id) }
    }

    /// Records a tab's mutation in memory and on disk. Every write goes through
    /// here, so there is exactly one place that can forget to persist.
    func write(_ tab: Tab) {
        list.update(tab)
        enqueue { store in try? await store.upsert(tab) }
    }

    func persistAll(_ tabs: [Tab]) {
        guard !tabs.isEmpty else { return }
        enqueue { store in
            for tab in tabs { try? await store.upsert(tab) }
        }
    }

    /// One chain for every tab write. Unordered `Task`s would let a renumber
    /// land after the row it renumbered — an order that is right on screen
    /// and wrong after a relaunch.
    private func enqueue(_ work: @escaping @Sendable (BrowserStore) async -> Void) {
        let previous = writeChain
        let store = store
        writeChain = Task {
            await previous?.value
            await work(store)
        }
    }

    // MARK: - Undo (§6.7)

    func registerUndo(_ name: String, _ body: @escaping @MainActor @Sendable (BrowserSession) -> Void) {
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { session in
            // `UndoManager` calls back on whichever thread ran `undo()`, which
            // for a menu command is always the main one.
            MainActor.assumeIsolated { body(session) }
        }
    }
}
