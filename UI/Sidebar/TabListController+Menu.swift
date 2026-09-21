//
//  TabListController+Menu.swift
//  Luna
//
//  §3.4a's right-click, for the list: which row has a menu, and what that menu's items
//  actually call — and §3.4b's second menu, on a group header, which is a different noun
//  and therefore a different menu rather than a longer version of the first.
//
//  Renaming is here rather than in either menu, for both nouns: the name is typed on the
//  row, and the row is the one thing a menu never knows about.
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
    func contextMenu(forRow row: Int?) -> NSMenu? {
        // The plane under the rows belongs to the list rather than to any one
        // of them, so it is where a folder made out of nothing is asked for.
        guard let row else {
            return GroupMenu.plane { [weak self] in self?.onNewGroup?() }
        }
        if let group = list.group(at: row) {
            guard let actions = groupMenuActions?(group.id) else { return nil }
            return GroupMenu.build(for: group, actions: actions) { [weak self] in
                self?.beginRenaming(group: group.id)
            }
        }
        guard let tab = list.tab(at: row), let actions = menuActions?(tab.id) else { return nil }
        return TabMenu.build(
            for: tab,
            isMuted: mutedTabIDs.contains(tab.id),
            group: list.group(ofTab: tab.id),
            others: list.groups(besides: list.group(ofTab: tab.id)?.id),
            actions: actions,
            rename: { [weak self] in self?.beginRenaming(tab: tab.id) }
        )
    }

    /// Opens the name field on a folder's own row (§3.4b).
    ///
    /// Called straight after one is made, which is the whole reason a folder is
    /// not asked for in a dialog first: the row appears already waiting to be
    /// named, and the first keystroke is the name. `makeIfNecessary` matters —
    /// a folder made while the list is scrolled away has no view yet.
    func beginRenaming(group id: UUID) {
        guard let row = list.row(ofGroup: id), let group = list.group(id) else { return }
        beginRenaming(atRow: row, showing: group.name)
    }

    /// The same field, on a tab (§3.4a's Rename).
    ///
    /// It opens on the name the row is showing — the tab's own name if it has
    /// one, the page's title if it does not — rather than on an empty box over
    /// a title the user can no longer read. Typing the page's title back, or
    /// clearing the field, is how the name goes back to the page; `renameTab`
    /// is where both of those are read.
    func beginRenaming(tab id: UUID) {
        guard let row = list.row(of: id), let tab = list.tab(at: row) else { return }
        beginRenaming(atRow: row, showing: tab.customTitle ?? tab.title)
    }

    private func beginRenaming(atRow row: Int, showing name: String) {
        table.scrollRowToVisible(row)
        table.window?.makeFirstResponder(table)
        guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarRowView else { return }
        view.beginEditing(name)
    }
}
