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
        persistAll(list.insert(tab))
        // A URL Luna opens on the user's behalf is a typed visit; a link click
        // reaches us through the engine instead (§9.3).
        if url != nil { pendingVisitKind[tab.id] = .typed }
        activateTab(tab.id)
        return tab.id
    }

    /// Archives the tab — §6.3's soft delete, which keeps title, URL and icon —
    /// and releases its web view. Undoable.
    ///
    /// **A pinned tab cannot be closed**, only unpinned: closing one puts its
    /// page away and leaves the tile, which is what `pinTab` already does. So
    /// `⌘W` on a pinned tab is "put this away", not "throw it out".
    func closeTab(_ id: UUID) {
        guard let index = list.indexInSection(of: id), var tab = list.tab(id) else { return }
        if tab.kind == .essential {
            putPinnedTabAway(id, in: tab.spaceID)
            return
        }
        tab.archivedAt = Date()
        forget(id)
        persistAll(list.remove(id))
        write(tab)
        if activeTabBySpace[tab.spaceID] == id {
            activeTabBySpace[tab.spaceID] = recentTabs.first { list.tab($0)?.spaceID == tab.spaceID }
        }
        archived.insert(tab, at: 0)
        registerUndo("Close Tab") { $0.restoreArchived(tab, at: index) }
        notifyChange()
    }

    /// `⌘⇧T`. The archive is seeded from SQLite at restore, so this still works
    /// on the first keystroke after a relaunch.
    func reopenLastArchived() {
        guard let newest = archived.first else { return }
        restoreArchived(newest, at: .max)
    }

    /// §6.4 / §9.2: pull one specific tab back out of the archive.
    func unarchiveTab(_ id: UUID) {
        guard let tab = archived.first(where: { $0.id == id }) else { return }
        restoreArchived(tab, at: .max)
    }

    /// Every tab this window knows about, across **all** Spaces — `tabs` is the
    /// active Space only. The Command Bar's cross-Space switching and its
    /// archive rows (§9.2) are the reason this exists.
    func allTabs(includeArchived: Bool) -> [Tab] {
        let open = spaces.flatMap { list[$0.id] }
        return includeArchived ? open + archived : open
    }

    /// - Parameter index: position **within `kind`'s section**, not within
    ///   `tabs`. Sections run essential → pinned → today.
    func reorderTab(_ id: UUID, to index: Int, kind: TabKind) {
        guard var tab = list.tab(id), let oldIndex = list.indexInSection(of: id) else { return }
        let oldKind = tab.kind
        // Deliberately not `forget`: reordering a tab must not cost its web view.
        list.remove(id)
        tab.kind = kind
        persistAll(list.insert(tab, at: index))
        registerUndo("Move Tab") { $0.reorderTab(id, to: oldIndex, kind: oldKind) }
        notifyChange()
    }

    /// Pins a tab into the §3.3 grid — the tiles under the URL pill.
    ///
    /// **Pinning closes the page and keeps the tab.** The tile stays until the
    /// user unpins it, and clicking one wakes the page again from the same
    /// `interactionState` the tab was carrying, so a pinned tab costs a row in
    /// SQLite and no WebContent process (§19.2). That is the whole behaviour:
    /// there is no "close a pinned tab", because the tile *is* the tab.
    func pinTab(_ id: UUID, at index: Int = .max) {
        guard let tab = list.tab(id), tab.kind != .essential else { return }
        // **This is the line that was missing.** Pinning put the page away and
        // never moved the tab into the Essentials section, so the row vanished
        // from the list, no tile appeared, and "Pin Tab" looked like it did
        // nothing at all. `reorderTab` is what changes a tab's kind, and it
        // registers the undo.
        reorderTab(id, to: index, kind: .essential)
        putPinnedTabAway(id, in: tab.spaceID)
    }

    /// Drops a pinned tab's page without dropping the tab: the tile stays, the
    /// WebContent process goes, and the selection moves to something that still
    /// has a page to show — a tab selected with no web view is an empty card.
    private func putPinnedTabAway(_ id: UUID, in spaceID: UUID) {
        // `discardController` caches the session blob onto the `Tab` on its way
        // out, so the tile comes back to where the user left the page rather
        // than to the top of it (§6.2).
        discardController(id)
        recentTabs.removeAll { $0 == id }
        if activeTabBySpace[spaceID] == id {
            activeTabBySpace[spaceID] = recentTabs.first { list.tab($0)?.spaceID == spaceID }
                ?? list[spaceID].first { $0.kind != .essential }?.id
        }
        notifyChange()
    }

    /// The only way a tile leaves the grid (§3.3). The tab lands back at the
    /// top of today's tabs, still cold — unpinning is not opening.
    func unpinTab(_ id: UUID) {
        guard list.tab(id)?.kind == .essential else { return }
        reorderTab(id, to: 0, kind: .today)
        notifyChange()
    }

    func moveTab(_ id: UUID, toSpace spaceID: UUID) {
        guard var tab = list.tab(id), tab.spaceID != spaceID,
              spaces.contains(where: { $0.id == spaceID }) else { return }
        let from = tab.spaceID
        let oldIndex = list.indexInSection(of: id) ?? 0
        let oldKind = tab.kind
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

    private func restoreArchived(_ tab: Tab, at index: Int) {
        var restored = tab
        restored.archivedAt = nil
        archived.removeAll { $0.id == tab.id }
        persistAll(list.insert(restored, at: index))
        registerUndo("Close Tab") { $0.closeTab(restored.id) }
        activateTab(restored.id)
    }

    /// Everything a tab costs while it is open: its web view and its caches.
    private func forget(_ id: UUID) {
        discardController(id)
        recentTabs.removeAll { $0 == id }
        faviconPNG[id] = nil
        recordedURL[id] = nil
        pendingVisitKind[id] = nil
    }

    // MARK: - Views

    /// The tab's content view, waking it if it is cold. Call it for the
    /// **selected** tab only — calling it for any other is precisely the §19.4
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
    /// land *after* the row it renumbered — an order that is right on screen
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
