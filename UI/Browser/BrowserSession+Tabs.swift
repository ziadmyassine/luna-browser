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
        // §3.4b: choosing a dimmed row is opening it again, so the second press
        // it was holding goes away. Clicking one is the ordinary way back.
        tab.isDormant = false
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
        persistAll(list.insert(tab, at: openIndex(for: kind)))
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
        // §3.4b's two presses. A saved row — loose, or inside a saved group — is
        // a place the user kept, so the first press ends the page and leaves the
        // row behind, dimmed and back at the address it was saved at. The second
        // press has no page left to mean, so it means the row.
        if tab.kind.keepsTabWhenPageCloses, !tab.isDormant {
            sendPageHome(id, in: tab.spaceID, markingDormant: true)
            return
        }
        // Read before the removal, while the closing tab still has neighbours.
        let successor = rowBelow(id, in: tab.spaceID)
        tab.archivedAt = Date()
        forget(id)
        persistAll(list.remove(id))
        // §6.3's shelf is for pages. One of Luna's own is not a page you can
        // come back to, so its row goes rather than being kept for thirty days
        // — see `AutoArchive.isWorthArchiving`. Undo still reopens it: the
        // closure below carries the whole `Tab`, and `restoreArchived` re-files
        // it whether or not it was ever on the shelf.
        if AutoArchive.isWorthArchiving(tab) {
            write(tab)
            archived.insert(tab, at: 0)
        } else {
            discard(id)
        }
        releaseTab(id, inSpace: tab.spaceID) {
            successor ?? self.recentTabs.first { self.list.tab($0)?.spaceID == tab.spaceID }
        }
        registerUndo("Close Tab") { $0.restoreArchived(tab, at: index) }
        notifyChange()
    }

    /// Where the selection goes when the tab showing is closed: the row
    /// under it in §3.4's list, or the row above it when it was the last one.
    ///
    /// It used to be the most recently used tab in the Space, which is a
    /// different question. Closing a run of tabs from the top sent the selection
    /// down the list and the next `⌘W` closed that one instead, so the list
    /// unravelled from two ends at once; and with §3.4 stacking today's tabs
    /// newest-first, the recent tab is often the one above.
    ///
    /// The list's own order is the one thing the user can see, so the answer is
    /// read straight off it — tiles and dimmed rows excluded, for
    /// `openableTabs`' reason: closing a tab must not load the one below it.
    /// The tab being closed stays in, because its own place is the question.
    private func rowBelow(_ id: UUID, in spaceID: UUID) -> UUID? {
        let rows = list[spaceID].filter { $0.id == id || ($0.kind != .essential && !$0.isDormant) }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        return (rows.dropFirst(index + 1).first ?? rows[..<index].last)?.id
    }

    /// `⌘⇧T`. The archive is seeded from SQLite at restore, so this still works
    /// on the first keystroke after a relaunch.
    ///
    /// The Space you are in, not the app: reopening a tab in Work must not
    /// bring back the Personal page you closed before you switched (§9.2).
    func reopenLastArchived() {
        guard let newest = archivedInActiveSpace.first else { return }
        restoreArchived(newest, at: openIndex(for: newest.kind))
    }

    /// §6.4 / §9.2: pull one specific tab back out of the archive.
    ///
    /// - Parameter resumingSession: whether the tab comes back the way it was
    ///   put away — where the page was left, and where the row was filed. True
    ///   for the two gestures that mean "reopen the tab I closed" (`⌘⇧T` and
    ///   §11's list), and false for §9's Command Bar.
    ///
    ///   The bar is an address bar: its rows are places, and the archive's rows
    ///   sit in the same list as history's and look like them. Choosing one and
    ///   landing half way down the page you were on last week is the session
    ///   resuming behind a gesture that never asked for it. Same tab, same
    ///   Space, same name; it simply starts at the top of the page, in today's
    ///   tabs.
    func unarchiveTab(_ id: UUID, resumingSession: Bool = true) {
        guard var tab = archived.first(where: { $0.id == id }) else { return }
        guard resumingSession else {
            // And it comes back loose, as a tab of the day. Where a tab was
            // filed is not part of the address: a page closed out of a §3.4b
            // folder was put in one on purpose, and typing its name again is
            // asking for the page, not for the folder to be re-stocked. Put
            // back in it, the answer arrived dimmed, two levels in, and one
            // press from being let go — which is the state the user had just
            // finished putting it in.
            tab.interactionState = nil
            let wasKept = tab.kind.keepsTabWhenPageCloses
            tab.kind = .today
            tab.groupID = nil
            restoreArchived(Self.keepingWhatItIsFor(tab, wasKept: wasKept), at: openIndex(for: .today))
            return
        }
        restoreArchived(tab, at: openIndex(for: tab.kind))
    }

    /// The Space you are in, its open tabs and its archived ones together —
    /// what the Command Bar offers (§9.2).
    ///
    /// Not `allTabs`. A Space's tabs, its history and its cookie jar are one
    /// set of things, and a Work window offering a Personal tab is offering a
    /// page that is signed in as somebody else. The bar used to list every
    /// Space and tell them apart with a badge; since `v7` made the Space the
    /// jar, the honest answer is not to offer the other one at all.
    func tabsInActiveSpace(includeArchived: Bool) -> [Tab] {
        includeArchived ? tabs + archivedInActiveSpace : tabs
    }

    /// §6.3's archive for the Space you are in. `archived` is every Space's,
    /// because the store writes and `⌘⌥1`'s sweeps work on the whole list.
    var archivedInActiveSpace: [Tab] {
        archived.filter { $0.spaceID == activeSpaceID }
    }

    /// Every tab this window knows about, across all Spaces — `tabs` is the
    /// active Space only. Teardown, the muting sweep and §23's tab count are
    /// the callers: the ones that mean every tab in the app rather than every
    /// tab on offer.
    /// De-duplicated: a Favorite resolves through more than one Space's list,
    /// so a plain `flatMap` would count each of them once per Space.
    func allTabs(includeArchived: Bool) -> [Tab] {
        var seen: Set<UUID> = []
        let open = spaces.flatMap { list[$0.id] }.filter { seen.insert($0.id).inserted }
        return includeArchived ? open + archived : open
    }

    /// - Parameter index: position within the run the tab is joining — a group's
    ///   members when `group` is given, the Profile's Favorites for `.essential`,
    ///   else the section's top-level slots (§3.4b).
    /// - Parameter group: the §3.4b group it lands in, or nil for loose. The
    ///   group's own tier wins over `kind`: a tab dropped into a saved group is
    ///   saved, whichever side of the rule it was dragged from.
    func reorderTab(_ id: UUID, to index: Int, kind: TabKind, group groupID: UUID? = nil) {
        guard var tab = list.tab(id), let oldIndex = list.indexInSection(of: id) else { return }
        let oldKind = tab.kind
        let oldGroup = tab.groupID
        let destination = groupID.flatMap { list.group($0) }
        // §3.4b: the tier under §3.3's tiles holds folders and nothing else, so
        // a tab arriving there on its own is given one. Here rather than at the
        // gestures, because there are four ways in — the drop, the menu, an
        // import, an undo — and a rule enforced in four places is a rule with
        // three holes in it. The new folder opens its name field, so the drop
        // ends with the cursor in it.
        if (destination?.kind ?? kind) == .pinned, destination == nil {
            createGroup(name: Self.untitledGroupName, kind: .pinned, containing: [id], at: index)
            return
        }
        // Deliberately not `forget`: reordering a tab must not cost its web view.
        // Persisted, not discarded: pulling a tab out of the Favorites tier
        // renumbers that tier across the whole Profile, and some of the rows it
        // renumbers live in other Spaces.
        persistAll(list.remove(id))
        tab.kind = destination?.kind ?? kind
        tab.groupID = destination?.id
        persistAll(list.insert(Self.keepingWhatItIsFor(tab, wasKept: oldKind.keepsTabWhenPageCloses), at: index))
        registerUndo("Move Tab") { $0.reorderTab(id, to: oldIndex, kind: oldKind, group: oldGroup) }
        notifyChange()
    }

    /// The bookkeeping a tab needs when it crosses into or out of a tier that
    /// keeps it — §3.3's grid and §3.4b's saved rows.
    ///
    /// `pinnedURL` is the address a kept row goes back to when its page is
    /// closed, so it is recorded at the moment of keeping and cleared at the
    /// moment of letting go: a tab that walked off somewhere and was then
    /// dragged down past the rule must not bring a stale home back with it the
    /// next time it is saved. A tab already in a keeping tier keeps the home it
    /// has, because that is the page the user chose rather than wherever the
    /// site has since wandered.
    static func keepingWhatItIsFor(_ tab: Tab, wasKept: Bool) -> Tab {
        var tab = tab
        guard tab.kind.keepsTabWhenPageCloses else {
            tab.pinnedURL = nil
            tab.isDormant = false
            return tab
        }
        if !wasKept || tab.pinnedURL == nil { tab.pinnedURL = tab.url }
        return tab
    }

    /// True when moving this tab into that Space would cross into another
    /// cookie jar — the case that costs the user their session, and the one
    /// that must never happen silently. Ask before `moveTab`, and say
    /// ``crossProfileMoveWarning``.
    ///
    /// Every move between Spaces crosses one now: a Space owns its jar (§9), so
    /// the boundary is the Space. It used to be true only of the moves that
    /// also changed profile, which was most of them and looked like a rule.
    func moveCrossesProfileBoundary(_ id: UUID, toSpace spaceID: UUID) -> Bool {
        guard let tab = list.tab(id), space(spaceID) != nil else { return false }
        return tab.spaceID != spaceID
    }

    /// Arc's wording, which is the best of the four researched: Firefox refuses
    /// the operation outright with a 500-word essay, Chrome refuses it in a
    /// comment (`// Profiles must be the same.`), and Zen allows it silently and
    /// it does not work (zen#11268).
    ///
    /// "Profile" is the user's word for a Space (§9). The sentence is unchanged
    /// because the fact it states is unchanged: the tab is moving into another
    /// cookie jar.
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
        let oldGroup = tab.groupID
        // A Favorite is a login tile and Favorites belong to the Profile (§2),
        // so one carried across a Profile boundary lands as a pinned tab rather
        // than joining another cookie jar's tiles.
        if oldKind == .essential, moveCrossesProfileBoundary(id, toSpace: spaceID) {
            tab.kind = .pinned
        }
        // A §3.4b group belongs to the Space it was made in, so a tab carried
        // out of that Space leaves the group rather than dragging it along —
        // the name stays where the rest of its tabs are.
        tab.groupID = nil
        // The web view belongs to the old Space's data store; it has to die here
        // or the tab would carry the old profile's cookies across (§5.1).
        discardController(id)
        persistAll(list.remove(id))
        tab.spaceID = spaceID
        tab.order = list.nextOrder(kind: tab.kind, in: spaceID)
        persistAll(list.insert(tab))
        releaseTab(id, inSpace: from) { self.recentTabs.first { self.list.tab($0)?.spaceID == from } }
        registerUndo("Move Tab to Space") { session in
            session.moveTab(id, toSpace: from)
            session.reorderTab(id, to: oldIndex, kind: oldKind, group: oldGroup)
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
        // deleted — and the Space it comes back to may have filled the twelve
        // since. Coming back as a pinned tab is the honest answer; silently
        // making a thirteenth tile is not.
        if restored.kind == .essential,
           favorites(inSpace: restored.spaceID).count >= Self.favoritesCap {
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

    /// A tab's icon — from this session, else its favicon cache (§4.7).
    func favicon(for id: UUID) -> NSImage? {
        let png = faviconPNG[id] ?? list.tab(id)?.url.host().flatMap { favicons.favicon(forHost: $0) }
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
        (try? await store.searchHistory(query, limit: limit, inSpace: activeSpaceID)) ?? []
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
        extensions?.tearDown()
    }

    /// Records a tab's mutation in memory and on disk. Every write goes through
    /// here, so there is exactly one place that can forget to persist.
    func write(_ tab: Tab) {
        list.update(tab)
        enqueue { store in try? await store.upsert(tab) }
    }

    /// Drops a tab's row for good — `write`'s counterpart for a tab that is not
    /// being kept. On the same chain as every other write, so a delete cannot
    /// overtake the renumber of the rows it left behind.
    func discard(_ id: UUID) {
        enqueue { store in try? await store.delete(tabID: id) }
    }

    func persistAll(_ tabs: [Tab]) {
        guard !tabs.isEmpty else { return }
        enqueue { store in
            for tab in tabs { try? await store.upsert(tab) }
        }
    }

    /// Everything one `TabList` mutation touched — §3.4b interleaves groups with
    /// the loose tabs around them, so moving a tab renumbers both.
    func persistAll(_ writes: TabListWrites) {
        guard !writes.isEmpty else { return }
        enqueue { store in
            for group in writes.groups { try? await store.upsert(group) }
            for tab in writes.tabs { try? await store.upsert(tab) }
        }
    }

    /// One chain for every tab write. Unordered `Task`s would let a renumber
    /// land after the row it renumbered — an order that is right on screen
    /// and wrong after a relaunch. Internal rather than private because
    /// `BrowserSession+Groups.swift` deletes rows on the same chain, and a
    /// deletion that overtook the renumber that emptied a group would be a
    /// foreign key failing on a row nobody can see.
    func enqueue(_ work: @escaping @Sendable (BrowserStore) async -> Void) {
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
