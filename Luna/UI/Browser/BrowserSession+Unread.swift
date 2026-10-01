//
//  BrowserSession+Unread.swift
//  Luna
//
//  §7.3's unread dot: which tabs have news the user has not seen. The row
//  draws `Tab.hasUnread`; this is what sets and clears it.
//
//  News is a load finishing, or a title changing outside a load — Gmail's
//  "(3) Inbox" — on a tab no window is showing. A link opened in the
//  background is the first case, as it is in Arc. Showing the tab in any
//  window is reading it, so the dot goes the moment a window selects it,
//  whichever gesture got it there.
//

import BrowserKit
import Foundation

extension BrowserSession {

    /// The tab each window has on its content card. A tab selected in a Space
    /// a window has walked away from is not on screen, which is why this reads
    /// each window's own Space rather than every selection it remembers.
    var tabsOnScreen: Set<UUID> {
        Set(windowFocus.values.compactMap { $0.tabBySpace[$0.spaceID] })
    }

    /// Records whether `id` is loading and answers whether this report is the
    /// end of a load.
    /// - Parameter isLive: whether the tab still has a web view. A tab put
    ///   away mid-load never finishes that load, and the next one it starts is
    ///   a new page rather than the end of this one.
    func noteLoading(_ id: UUID, isLoading: Bool, isLive: Bool) -> Bool {
        guard isLive else {
            loadingTabIDs.remove(id)
            return false
        }
        if isLoading {
            loadingTabIDs.insert(id)
            return false
        }
        return loadingTabIDs.remove(id) != nil
    }

    /// Marks `tab` unread unless a window is showing it. Answers whether it
    /// changed, so the caller writes it once with everything else.
    func markUnread(_ tab: inout Tab) -> Bool {
        guard !tab.hasUnread, !tabsOnScreen.contains(tab.id) else { return false }
        tab.hasUnread = true
        return true
    }

    /// Clears the dot on every tab a window is showing. Run from
    /// `notifyChange`, before anything draws.
    func clearUnreadOnScreen() {
        for id in tabsOnScreen {
            guard var tab = list.tab(id), tab.hasUnread else { continue }
            tab.hasUnread = false
            write(tab)
        }
    }
}
