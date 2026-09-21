//
//  TabListController+Menu.swift
//  Luna
//
//  §3.4a's right-click, for the list: which row has a menu, and what that menu's items
//  actually call — and §3.4b's second menu, on a group header, which is a different noun
//  and therefore a different menu rather than a longer version of the first.
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
        if let group = list.group(at: row) {
            guard let actions = groupMenuActions?(group.id) else { return nil }
            return GroupMenu.build(for: group, actions: actions)
        }
        guard let tab = list.tab(at: row), let actions = menuActions?(tab.id) else { return nil }
        return TabMenu.build(
            for: tab,
            isMuted: mutedTabIDs.contains(tab.id),
            group: list.group(ofTab: tab.id),
            others: list.groups(besides: list.group(ofTab: tab.id)?.id),
            actions: actions
        )
    }
}
