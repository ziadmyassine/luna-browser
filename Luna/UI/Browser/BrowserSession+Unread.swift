//
//  BrowserSession+Unread.swift
//  Luna
//
//  §7.3's unread dot: which tabs have news the user has not seen. The row
//  draws `Tab.hasUnread`; this is what sets and clears it.
//
//  News is one of two things on a tab no window is showing: a link opened
//  in the background finishing its first load, as in Arc, or the page's
//  title gaining or raising a count — Gmail's "(3) Inbox". Any load
//  finishing was news at first, and every relaunch then dotted the whole
//  list: restoring a tab, waking a hibernated one and a page tidying its
//  own title all finish loads nobody would call news. Showing the tab in
//  any window is reading it, so the dot goes the moment a window selects
//  it, whichever gesture got it there.
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

    /// Whether this report is news on `id`. `oldTitle` is the title before it,
    /// for a report that changed the title.
    func isNews(_ id: UUID, finishedLoad: Bool, from oldTitle: String?, to state: TabState) -> Bool {
        if finishedLoad, unseenBackgroundTabIDs.remove(id) != nil { return true }
        // A title that changes during a load is part of that load.
        guard let oldTitle, !state.isLoading else { return false }
        return Self.countRose(from: oldTitle, to: state.title)
    }

    /// Whether `new` carries a higher count than `old`: "(3) Inbox" after
    /// "Inbox" or "(2) Inbox", and "[4]" the same. A count going down, or a
    /// title with none, is a page tidying itself, not news.
    static func countRose(from old: String, to new: String) -> Bool {
        guard let after = count(in: new) else { return false }
        return after > (count(in: old) ?? 0)
    }

    private static func count(in title: String) -> Int? {
        guard let match = title.firstMatch(of: /[(\[](\d{1,5})\+?[)\]]/) else { return nil }
        return Int(match.1)
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
            unseenBackgroundTabIDs.remove(id)
            guard var tab = list.tab(id), tab.hasUnread else { continue }
            tab.hasUnread = false
            write(tab)
        }
    }

    /// The dots the first rule left, cleared once: a relaunch had dotted most
    /// of the list. Not under XCTest, whose host shares this Mac's defaults
    /// and would spend the once on a throwaway database.
    func clearUnreadFromBeforeTheRule() {
        let key = "unread.clearedLoadRule"
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        for var tab in list.bySpace.values.joined() where tab.hasUnread {
            tab.hasUnread = false
            write(tab)
        }
    }
}
