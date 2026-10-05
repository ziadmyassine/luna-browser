//
//  TabMenu+Many.swift
//  Luna
//
//  §3.4a's menu on a row that is one of several marked tabs: what can be done
//  to all of them at once. Folder, pin, close — the items whose meaning does
//  not change with the number of tabs. Rename, icon, copy link and mute are
//  each about one page, and a menu that offered them here would have to pick
//  which.
//

import AppKit
import BrowserKit

extension TabMenu {

    /// The verbs, bound to the marked tabs — `BrowserSession.tabMenuActions(for:)`.
    struct ManyActions {
        /// Nil in a §5.6 private window, as on the one-tab menu.
        var pin: (() -> Void)?
        /// Into that folder, or — with nil — out of the folders they are in.
        var setGroup: (UUID?) -> Void
        /// A new folder holding all of them, its name field open.
        var newGroup: () -> Void
        var close: () -> Void
    }

    /// - Parameter folders: every folder the tabs could go into.
    /// - Parameter inFolder: whether any of them is in a folder, which is what
    ///   puts Remove from Folder on the menu.
    static func build(count: Int, folders: [TabGroup], inFolder: Bool, actions: ManyActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let parent = NSMenuItem(title: String(localized: "Add to Folder"), action: nil, keyEquivalent: "")
        parent.attributedTitle = SidebarMenu.label(symbol: "folder", title: parent.title)
        parent.submenu = folderMenu(count: count, folders: folders, inFolder: inFolder, actions: actions)
        menu.addItem(parent)
        if let pin = actions.pin {
            menu.addItem(SidebarMenu.glyphItem(String(localized: "Pin \(count) Tabs"), symbol: "pin", action: pin))
        }
        menu.addItem(.separator())

        let close = SidebarMenu.glyphItem(String(localized: "Close \(count) Tabs"), symbol: "xmark", action: actions.close)
        close.keyEquivalent = "w"
        close.keyEquivalentModifierMask = .command
        menu.addItem(close)
        return menu
    }

    private static func folderMenu(count: Int, folders: [TabGroup], inFolder: Bool, actions: ManyActions) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(SidebarMenu.glyphItem(
            String(localized: "New Folder with \(count) Tabs"),
            symbol: "folder.badge.plus",
            action: actions.newGroup
        ))
        if !folders.isEmpty {
            submenu.addItem(.separator())
            for group in folders {
                submenu.addItem(SidebarMenu.glyphItem(group.name, symbol: group.symbolName) { actions.setGroup(group.id) })
            }
        }
        if inFolder {
            submenu.addItem(.separator())
            submenu.addItem(SidebarMenu.glyphItem(String(localized: "Remove from Folder"), symbol: "folder.badge.minus") {
                actions.setGroup(nil)
            })
        }
        return submenu
    }
}
