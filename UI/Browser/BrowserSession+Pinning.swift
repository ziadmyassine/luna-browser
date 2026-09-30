//
//  BrowserSession+Pinning.swift
//  Luna
//
//  §3.3's half of the §6 lifecycle: what it means for a tab to be a tile. A
//  tile's page can go away for two reasons, and the tile comes back
//  differently depending on which:
//
//    · Filed away — pinning a tab that is not on screen, or the §19.2
//      live-tab budget reclaiming a cold one. The blob stays, and clicking the
//      tile lands where the user left off.
//    · Closed — `⌘W` on a tile, a decision that the page is finished. The tile
//      stays; the page goes back to `pinnedURL`, the link it was made from.
//
//  Both end with the page gone and the tile on screen, so one call for both
//  looks right until a closed tile is clicked again and comes back mid-page.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// Whether anything in this session can be kept (§3.3's tiles, §3.4b's
    /// folder tier).
    ///
    /// False in a §5.6 private window, and that is the whole rule: keeping is
    /// the opposite of what such a window is for. Its database is a temporary
    /// directory that goes when the window does, so a tile pinned there would
    /// be a place the user was told to put things and then lost — and one they
    /// would reasonably expect back in their real Spaces, where it never was.
    ///
    /// Read by the two verbs below and beside, by the two menus, by §6.6's
    /// drag and by §3.3a's wells: nothing offers what this refuses.
    var allowsPinning: Bool { !isPrivate }

    /// Pins a tab into the §3.3 grid — the tiles under the URL pill.
    ///
    /// Pinning closes the page and keeps the tab: clicking the tile wakes the
    /// page from the same `interactionState`, so a pinned tab costs a row in
    /// SQLite and no WebContent process (§19.2). There is no "close a pinned
    /// tab", because the tile is the tab.
    ///
    /// Except the page on screen. Dropping its web view blanked the content
    /// pane under the pointer, mid-gesture, and the site just dragged up had
    /// to be reloaded from the tile. The current tab keeps its page, and
    /// `enforceLiveTabBudget` reclaims it later like any other live tab.
    ///
    /// - Returns: false when nothing happened — the tab is already a Favorite,
    ///   or the Profile is already holding Arc's twelve. Evicting the oldest
    ///   tile instead would throw away a login the user put there on purpose.
    /// - Parameter selecting: make the tab current on the way in, as §6.6's
    ///   drag across the §3.3 boundary does. Selection is taken before the
    ///   pin, so the on-screen branch runs and the live page is never torn
    ///   down and rebuilt.
    @discardableResult
    func pinTab(_ id: UUID, at index: Int = .max, selecting: Bool = false) -> Bool {
        guard allowsPinning else { return false }
        guard let tab = list.tab(id), tab.kind != .essential else { return false }
        // Favorites are per Space (§2), so the cap is per Space too.
        if favorites(inSpace: tab.spaceID).count >= Self.favoritesCap { return false }
        if selecting { activateTab(id) }
        // `reorderTab` is what changes a tab's kind, registers the undo and
        // records `pinnedURL`. It reads the row back after `activateTab` has
        // written it, so the home it keeps is the address the user was looking
        // at when they decided to keep it.
        reorderTab(id, to: index, kind: .essential)
        guard activeTabBySpace[tab.spaceID] != id else {
            notifyChange()
            return true
        }
        putPinnedTabAway(id, in: tab.spaceID)
        return true
    }

    /// The only way a tile leaves the grid (§3.3). The tab lands back at the
    /// top of today's tabs, still cold — unpinning is not opening.
    func unpinTab(_ id: UUID) {
        guard list.tab(id)?.kind == .essential else { return }
        // It is not a tile any more, so it has nowhere to go home to, and
        // `reorderTab` is what drops the link: from here on it is an ordinary
        // tab, and an ordinary tab's address is wherever it is. Keeping the old
        // home would bring it back the next time the tab was kept, which is a
        // decision the user has not taken yet.
        reorderTab(id, to: 0, kind: .today)
        notifyChange()
    }

    /// Drops a pinned tab's page without dropping the tab: the tile stays, the
    /// WebContent process goes, and the selection moves to something that still
    /// has a page to show — a tab selected with no web view is an empty card.
    ///
    /// Filing away, not closing. `discardController` caches the session blob
    /// onto the `Tab` on its way out, so the tile comes back to where the user
    /// left the page rather than to the top of it (§6.2). `sendTileHome` is the
    /// other half.
    func putPinnedTabAway(_ id: UUID, in spaceID: UUID) {
        discardController(id)
        releaseSelection(of: id, in: spaceID)
    }

    /// §3.3: `⌘W` on a tile. The tile stays — a pinned tab cannot be closed —
    /// but the page is closed, so it returns to `pinnedURL`: top of the page,
    /// no back/forward history. A tile whose page merely went cold keeps its
    /// blob instead. The tile is the place you keep, not the page you happened
    /// to leave open in it.
    ///
    /// A tile from before schema `v3`'s backfill, or one whose home is somehow
    /// missing, is filed away instead of sent home. Nil means "no home", and
    /// inventing one out of the current address would be worse than filing it.
    func sendTileHome(_ id: UUID, in spaceID: UUID) {
        sendPageHome(id, in: spaceID, markingDormant: false)
    }

    /// The same close for §3.4b's saved rows, which keep their row for the same
    /// reason a tile does — and unlike a tile, remember that it happened.
    ///
    /// - Parameter markingDormant: whether the row should come back dimmed and
    ///   one press from being let go. A tile is never dormant: there is no
    ///   second press to distinguish, because closing a tile again just sends it
    ///   home again. A saved row has exactly one more press in it, and
    ///   `Tab.isDormant` is what remembers which one it is on.
    func sendPageHome(_ id: UUID, in spaceID: UUID, markingDormant: Bool) {
        // Before the write, not after. `discardController` hibernates the
        // controller and caches the blob it captured onto the row; clearing
        // `interactionState` first would put the closed page's history straight
        // back onto the tab it had just been taken off.
        discardController(id)
        if var tab = list.tab(id) {
            if let home = tab.pinnedURL {
                tab.url = home
                tab.interactionState = nil
                // The row is going to load its home page again, and §9.3 should
                // hear about that visit rather than dedupe it against the one
                // this tab recorded before it was closed.
                recordedURL[id] = nil
            }
            tab.isDormant = markingDormant
            write(tab)
            if markingDormant { registerUndo("Close Tab") { $0.wakeDormantTab(id) } }
        }
        releaseSelection(of: id, in: spaceID)
    }

    /// Puts a dimmed row back to being an open tab (§3.4b) — what clicking one
    /// does, and what undo does to the press that dimmed it.
    ///
    /// It does not load anything on its own. A saved row that has been closed is
    /// cold like any other cold tab, and `activateTab` is what wakes it; this
    /// only takes the second press back off it.
    func wakeDormantTab(_ id: UUID) {
        guard var tab = list.tab(id), tab.isDormant else { return }
        tab.isDormant = false
        write(tab)
        notifyChange()
    }

    /// The selection cannot stay on a tab that no longer has a page. Shared by
    /// both halves above: what differs between them is what happens to the
    /// row, never what happens to the selection.
    ///
    /// Never onto the row it is leaving, and never onto a row that has already been
    /// closed once. §3.4b's saved row takes two presses and `⌘W` is the fast one.
    /// Not "the first row in the Space": for a saved tab at the top of the column
    /// that is the row just closed, so the second `⌘W` landed on it again and took
    /// it out of Saved, half a second after the first. A dormant row is excluded
    /// for the same reason wherever it stands: the selection sitting on one is the
    /// second press already lined up.
    func releaseSelection(of id: UUID, in spaceID: UUID) {
        recentTabs.removeAll { $0 == id }
        releaseTab(id, inSpace: spaceID) {
            self.recentTabs.first { self.list.tab($0)?.spaceID == spaceID }
                ?? self.openableTabs(inSpace: spaceID, besides: id).first?.id
        }
        notifyChange()
    }

    /// The rows the selection may move to on its own, in list order.
    ///
    /// A §3.3 tile and a §3.4b row that has been closed once are both places
    /// rather than pages: the tile's page is put away (§19.2) and the dimmed
    /// row's was ended on purpose. Selecting either loads it, so neither is
    /// something Luna may choose for the user — only something the user can
    /// click. Shared with `switchSpace`, which needs the same rule.
    func openableTabs(inSpace spaceID: UUID, besides id: UUID? = nil) -> [Tab] {
        list[spaceID].filter { $0.id != id && $0.kind != .essential && !$0.isDormant }
    }
}
