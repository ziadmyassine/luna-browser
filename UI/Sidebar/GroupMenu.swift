//
//  GroupMenu.swift
//  Luna
//
//  §3.4b's folder menu: right-click a folder's header in §3.4's list, and the
//  one item the column's empty plane carries.
//
//  Its own menu rather than a longer §3.4a. A folder and a tab are different
//  nouns — one is a page, the other is a name around several — and half of
//  §3.4a's items have no meaning on a folder at all: there is no address to
//  copy, nothing to duplicate, no sound to mute, and pinning is the one thing
//  §3.4b says a folder may never be. A menu that greyed out five of its eight
//  items would teach the user to stop opening it.
//
//  Five items in three groups: the two that change what the folder is, the
//  one that moves it across the rule, and the two that end it. A plain
//  `NSMenu`, and the glyphs ride in `attributedTitle`, for the reasons §3.4a
//  records.
//
//  Neither Rename nor Change Icon asks a question in a window. A folder is made
//  by a right-click and named on its own row, so renaming it later is the same
//  gesture the user already did once, and the icons are a submenu because a
//  list of sixteen pictures is a thing to point at rather than a thing to
//  answer. That is also why nothing here ends in an ellipsis: no item opens
//  anything before it commits.
//

import AppKit
import BrowserKit

@MainActor
enum GroupMenu {

    /// What the menu can do. The list owns the verbs, as §3.4a's does.
    ///
    /// Renaming is not among them, and deliberately: the name is typed on the
    /// row, so the menu's *Rename* opens a field rather than calling a verb.
    /// That closure comes from the list, not the session — see `build`.
    struct Actions {
        var setIcon: (String) -> Void
        var setSaved: (Bool) -> Void
        var ungroup: () -> Void
        var close: () -> Void
    }

    /// - Parameter rename: opens the name field on the folder's own row.
    static func build(for group: TabGroup, actions: Actions, rename: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(SidebarMenu.glyphItem(String(localized: "Rename"), symbol: "pencil", action: rename))
        menu.addItem(iconSubmenu(current: group.symbolName, actions: actions))
        menu.addItem(.separator())

        // §3.4b: a folder stands on one side of the rule or the other, and its
        // tabs stand with it. There is no third answer — a folder cannot be
        // pinned, because §3.3's grid is one tile per tab.
        menu.addItem(SidebarMenu.glyphItem(
            group.isSaved ? String(localized: "Remove from Saved") : String(localized: "Save Folder"),
            symbol: group.isSaved ? "tray.and.arrow.up" : "tray.and.arrow.down",
            action: { actions.setSaved(!group.isSaved) }
        ))
        menu.addItem(.separator())

        // The first keeps every page and drops the name; the second ends the
        // pages. Both say which, because "Delete" over a folder of open tabs is
        // a word that could mean either.
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Remove Folder, Keep Tabs"),
            symbol: "rectangle.dashed",
            action: actions.ungroup
        ))
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Close Folder and Tabs"),
            symbol: "xmark",
            action: actions.close
        ))
        return menu
    }

    /// The one item the empty part of the column carries (§3.4b).
    ///
    /// A folder and nothing else. The plane already moves the window on a press
    /// and already swipes between Spaces, and a right-click on it is not a
    /// right-click on any tab — so the only thing it can offer is the one thing
    /// that needs no tab to exist.
    static func plane(newFolder: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "New Folder"),
            symbol: "folder.badge.plus",
            action: newFolder
        ))
        return menu
    }

    /// The sixteen, with the one the folder is wearing ticked.
    ///
    /// A submenu rather than a dialog, for the reason the file header gives, and
    /// a tick rather than a highlight because `NSMenuItem.state` is the one
    /// "this is the current one" macOS draws without being asked.
    private static func iconSubmenu(current: String, actions: Actions) -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Change Icon"), action: nil, keyEquivalent: "")
        parent.attributedTitle = SidebarMenu.label(symbol: "photo", title: parent.title)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for symbol in symbols {
            let item = SidebarMenu.glyphItem(symbol.label, symbol: symbol.name) { actions.setIcon(symbol.name) }
            item.state = symbol.name == current ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// A curated list, for the reason §3.4a's tab icons give: a symbol name that
    /// does not resolve draws nothing at all, and a text field has no way to say
    /// which of the six thousand names it is.
    ///
    /// Its own list again. A folder names a *body of work* — a project, a trip,
    /// a shopping list — where a tab names a page and a Space names a mode, so
    /// the three vocabularies only touch at the edges. `folder` leads it because
    /// it is what a folder starts as.
    static let symbols: [(label: String, name: String)] = [
        (String(localized: "Folder"), "folder"),
        (String(localized: "Tray"), "tray.full"),
        (String(localized: "Box"), "shippingbox"),
        (String(localized: "Briefcase"), "briefcase"),
        (String(localized: "Books"), "books.vertical"),
        (String(localized: "Graduation Cap"), "graduationcap"),
        (String(localized: "Flask"), "flask"),
        (String(localized: "Hammer"), "hammer"),
        (String(localized: "Paintbrush"), "paintbrush"),
        (String(localized: "Airplane"), "airplane"),
        (String(localized: "House"), "house"),
        (String(localized: "Cart"), "cart"),
        (String(localized: "Gift"), "gift"),
        (String(localized: "Sparkles"), "sparkles"),
        (String(localized: "Tag"), "tag"),
        (String(localized: "Star"), "star")
    ]
}
