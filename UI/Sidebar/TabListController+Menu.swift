//
//  TabListController+Menu.swift
//  Luna
//
//  §3.4a's right-click, for the list: which row has a menu, and what that menu's seven
//  items actually call.
//
//  Split out of `TabListController.swift` for that file's length limit, and it is the
//  right seam anyway — the wording and the order live in `TabMenu.swift`, the verbs live
//  on `BrowserSession`, and this is the one place that knows a row is a tab.
//

import AppKit
import BrowserKit

extension TabListController {

    /// Only tabs have a menu: `+ Add Tab` and the rule are commands, and a context menu on
    /// a command is a menu with nothing in it.
    ///
    /// The `Tab` is read here and the id is what the menu carries. The row index this
    /// was summoned from is already stale by the time an item fires — the menu is modal,
    /// and a background tab finishing a load can certainly have arrived by then; the id
    /// cannot drift.
    func contextMenu(forRow row: Int) -> NSMenu? {
        guard let tab = list.tab(at: row), let actions = menuActions?(tab.id) else { return nil }
        return TabMenu.build(for: tab, isMuted: mutedTabIDs.contains(tab.id), actions: actions)
    }
}
