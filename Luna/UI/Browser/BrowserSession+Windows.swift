//
//  BrowserSession+Windows.swift
//  Luna
//
//  §22.6: which window is standing where.
//
//  The Spaces, the tab list and the web views belong to the session and are
//  shared by its windows — there is one database underneath, and a second
//  in-memory copy would race the first onto disk. A window owns only where it
//  stands: the Space it shows and the tab it has selected in each Space it has
//  visited. A private window has its own session and needs none of this.
//
//  `keyWindowID` is what the unqualified `activeTabID` and `activeSpaceID`
//  mean: the app's commands (`⌘W`, `⌘R`, `⌘T`) are about the window the user
//  is in. Chrome asks by name, because a sidebar draws its own window, which
//  is not always the front one. A session with no window still answers:
//  `keyWindowID` starts as a name nothing else holds, focused on first write.
//

import BrowserKit
import Foundation

extension BrowserSession {

    /// §9.1's bar, as the window that owns one hands it over.
    typealias CommandBarPresenter = (CommandBarMode, CommandBarAnchor?) -> Void

    /// One window's place in the session.
    struct WindowFocus {
        /// The Space this window is showing (§5.3).
        var spaceID: UUID
        /// The tab it has selected in each Space it has been to, so walking
        /// away from a Space and back returns to the page you left — per
        /// window, because two windows in one Space are two places to stand.
        var tabBySpace: [UUID: UUID] = [:]
    }

    // MARK: - Reading, by window

    func activeSpaceID(inWindow window: UUID) -> UUID { focus(window).spaceID }

    func activeTabID(inWindow window: UUID) -> UUID? {
        let focus = focus(window)
        return focus.tabBySpace[focus.spaceID]
    }

    /// Every tab in the Space `window` is showing, in the order §3.4 draws.
    func tabs(inWindow window: UUID) -> [Tab] { list[activeSpaceID(inWindow: window)] }

    /// §3.3's tiles for the Space `window` is showing.
    func favorites(inWindow window: UUID) -> [Tab] {
        list.favorites(inSpace: activeSpaceID(inWindow: window))
    }

    /// One of §3.4's two tiers for that Space, as slots — each folder carrying
    /// its own tabs.
    func slots(inTier kind: TabKind, inWindow window: UUID) -> [SidebarSlot] {
        list.drawnSlots(inSpace: activeSpaceID(inWindow: window), kind: kind)
    }

    func focus(_ window: UUID) -> WindowFocus {
        windowFocus[window] ?? WindowFocus(spaceID: lastUsedSpaceID)
    }

    // MARK: - Writing, by window

    func activateTab(_ id: UUID, inWindow window: UUID) {
        withKeyWindow(window) { activateTab(id) }
    }

    func switchSpace(_ id: UUID, inWindow window: UUID) {
        withKeyWindow(window) { switchSpace(id) }
    }

    /// Runs `body` as though `window` were the front one.
    ///
    /// The session's verbs are written against "the window the user is in" and
    /// there are a hundred of them; a second spelling of each, threading a
    /// window id through `newTab` and `reorderTab` and everything they call,
    /// would be a hundred places for the two to disagree. A window that is not
    /// key can still be clicked in — AppKit gives a background window's views
    /// the click and makes it key on the way — so the key window is restored
    /// afterwards rather than assumed.
    private func withKeyWindow(_ window: UUID, _ body: () -> Void) {
        let previous = keyWindowID
        keyWindowID = window
        body()
        keyWindowID = previous
    }

    // MARK: - The chrome a window has put up

    func commandBar(inWindow window: UUID) -> CommandBarPresenter? { commandBarByWindow[window] }

    func setCommandBar(_ present: CommandBarPresenter?, inWindow window: UUID) {
        commandBarByWindow[window] = present
    }

    func urlField(inWindow window: UUID) -> (() -> Void)? { urlFieldByWindow[window] }

    func setURLField(_ focus: (() -> Void)?, inWindow window: UUID) {
        urlFieldByWindow[window] = focus
    }

    // MARK: - Windows coming and going

    /// Registers a window and returns it standing where the front one is.
    ///
    /// The same Space with nothing selected, which is what a cold launch gives
    /// too (§19.4): Luna has no New Tab page to put in a window nobody has
    /// asked a question of yet, and §30.6's row and §3.3a's wells already say
    /// what to do with an empty one.
    func openWindow(_ window: UUID) {
        windowFocus[window] = WindowFocus(spaceID: activeSpaceID)
        extensions?.sync()
    }

    /// Forgets a window that has closed. Its pages are not torn down here —
    /// they belong to the session, and another window may be showing one.
    func closeWindow(_ window: UUID) {
        windowFocus[window] = nil
        commandBarByWindow[window] = nil
        urlFieldByWindow[window] = nil
        defer { extensions?.sync() }
        guard window == keyWindowID, let next = windowFocus.keys.first else { return }
        keyWindowID = next
    }

    /// The window the user came forward to. Every unqualified question the app
    /// asks the session from here on is about this one.
    func setKeyWindow(_ window: UUID) {
        guard window != keyWindowID, windowFocus[window] != nil else { return }
        keyWindowID = window
        notifyChange()
    }

    // MARK: - A tab changing windows

    /// §6.6's tear-off: `id` goes on `window`'s card and comes off every other
    /// window's, which moves on to the row beside it as a closed tab's window
    /// does. The page is not reloaded — its web view belongs to the session
    /// and goes wherever it is shown.
    ///
    /// The tab stays in every window's list. The list is the Space's, and
    /// every window onto the Space draws the same one (§22.6); what moves is
    /// which window is showing the page.
    func showTab(_ id: UUID, onlyInWindow window: UUID) {
        guard let tab = list.tab(id) else { return }
        let others = windowFocus.filter { $0.key != window && $0.value.tabBySpace[tab.spaceID] == id }.keys
        if !others.isEmpty {
            let next = rowBelow(id, in: tab.spaceID)
            for other in others { windowFocus[other]?.tabBySpace[tab.spaceID] = next }
        }
        windowFocus[window, default: WindowFocus(spaceID: tab.spaceID)].spaceID = tab.spaceID
        activateTab(id, inWindow: window)
    }

    // MARK: - A tab going away

    /// Moves every window's selection off `id`, wherever it is selected.
    ///
    /// Every window, not the front one. A tab that has been closed, unpinned or
    /// carried into another Space is gone from the column all of them draw, and
    /// a window behind this one would otherwise keep pointing at a row that is
    /// no longer there — and put that page back on screen the moment it came
    /// forward.
    ///
    /// `successor` is a closure because working one out costs a walk of the
    /// Space and most releases have nothing to release.
    func releaseTab(_ id: UUID, inSpace spaceID: UUID, to successor: () -> UUID?) {
        let holders = windowFocus.filter { $0.value.tabBySpace[spaceID] == id }.keys
        guard !holders.isEmpty else { return }
        let next = successor()
        for window in holders { windowFocus[window]?.tabBySpace[spaceID] = next }
    }

    /// Takes a deleted Space out of every window (§5.4): what each had selected
    /// in it is forgotten, and any window that was standing in it is moved to
    /// `refuge`. Nil only when the last Space has gone, which `deleteSpace`
    /// refuses before it gets here.
    func releaseSpace(_ id: UUID, to refuge: UUID?) {
        for window in windowFocus.keys {
            windowFocus[window]?.tabBySpace[id] = nil
            guard windowFocus[window]?.spaceID == id, let refuge else { continue }
            switchSpace(refuge, inWindow: window)
        }
    }
}
