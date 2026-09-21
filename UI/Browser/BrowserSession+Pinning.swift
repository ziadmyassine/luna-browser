//
//  BrowserSession+Pinning.swift
//  Luna
//
//  §3.3's half of the §6 lifecycle: what it means for a tab to be a tile.
//
//  Split out of `BrowserSession+Tabs.swift` for that file's length limit.
//  Everything here turns on one distinction the rest of the lifecycle does not
//  have to make: a tile's page can go away for two different reasons, and the
//  tile comes back differently depending on which.
//
//    · Filed away — pinning a tab that is not the one on screen, or the
//      §19.2 live-tab budget reclaiming a cold one. Nothing was decided about
//      the page; it simply costs a WebContent process to keep. The blob stays,
//      and clicking the tile lands where the user left off.
//    · Closed — `⌘W` on a tile. That is a decision, and it is "I am
//      finished with this page". The tile stays, because a tile is a place you
//      keep; the page does not, so the tab goes back to `pinnedURL`, the link
//      the tile was made from.
//
//  Both end with the page gone and the tile on screen, which is why they used
//  to be one call and looked right until you closed a tile and clicked it
//  again.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// Pins a tab into the §3.3 grid — the tiles under the URL pill.
    ///
    /// Pinning closes the page and keeps the tab. The tile stays until the
    /// user unpins it, and clicking one wakes the page again from the same
    /// `interactionState` the tab was carrying, so a pinned tab costs a row in
    /// SQLite and no WebContent process (§19.2). That is the whole behaviour:
    /// there is no "close a pinned tab", because the tile is the tab.
    ///
    /// Except the page you are looking at. Dropping a web view saves a
    /// WebContent process, which is right for a tab being filed away and wrong
    /// for the one on screen: pinning the active tab blanked the content pane
    /// under the pointer, mid-gesture, and the site just dragged up there had
    /// to be re-loaded from the tile. A pinned tab that is the current tab
    /// keeps its page, and `enforceLiveTabBudget` reclaims it later like any
    /// other live tab.
    ///
    /// - Returns: false when nothing happened — the tab is already a Favorite,
    ///   or the Profile is already holding Arc's twelve. Refusing is the whole
    ///   behaviour at the cap: quietly evicting the oldest tile would throw away
    ///   a login the user put there on purpose.
    /// - Parameter selecting: make the tab current on the way in. §6.6's drag
    ///   across the §3.3 boundary passes true — a tab you carried up there by
    ///   hand is the tab you are pointing at, so it becomes the one on screen.
    ///   Ordering matters: selection is taken before the pin, so the
    ///   "except the page you are looking at" branch below is the one that
    ///   runs and the live page is never torn down and rebuilt.
    @discardableResult
    func pinTab(_ id: UUID, at index: Int = .max, selecting: Bool = false) -> Bool {
        guard let tab = list.tab(id), tab.kind != .essential else { return false }
        // Favorites are per Profile (§2), so the cap is per Profile too.
        if let profileID = profileID(ofTab: id), favorites(onProfile: profileID).count >= Self.favoritesCap {
            return false
        }
        if selecting { activateTab(id) }
        // `reorderTab` is what changes a tab's kind, what registers the undo,
        // and — since §3.4b gave the saved rows the same behaviour — what
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
    /// but the page is closed, and a closed page has nothing left to come back
    /// to but the link the tile was made from.
    ///
    /// That is the whole distinction, and it is the one the user asked for: a
    /// tile whose page merely went cold keeps its blob and returns you to where
    /// you left off, and a tile you closed returns to `pinnedURL` — top of the
    /// page, no back/forward history. Closing is what you do when you are
    /// finished with the page; the tile is the place you keep, not the page you
    /// happened to leave open in it.
    ///
    /// A tile from before schema `v3`'s backfill, or one whose home is somehow
    /// missing, is filed away instead of sent home. Nil means "no home", and
    /// inventing one out of the current address would be a worse answer than
    /// the behaviour that was already there.
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
    func releaseSelection(of id: UUID, in spaceID: UUID) {
        recentTabs.removeAll { $0 == id }
        if activeTabBySpace[spaceID] == id {
            activeTabBySpace[spaceID] = recentTabs.first { list.tab($0)?.spaceID == spaceID }
                ?? list[spaceID].first { $0.kind != .essential }?.id
        }
        notifyChange()
    }
}
