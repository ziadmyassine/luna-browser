//
//  ExtensionMenu.swift
//  Luna
//
//  What a right-click on an extension offers, wherever it stands: a pinned
//  button on any bar, or a row of the pop-out. One menu for all of them, so
//  the surfaces cannot drift apart on what Remove asks before it removes.
//

import AppKit

@MainActor
enum ExtensionMenu {

    /// Pin or unpin, then `extra`, then Remove. An extension off in this
    /// Space has no button on the bar, so it is offered no pin.
    static func make(for item: ExtensionShelfItem, extra: [NSMenuItem] = []) -> NSMenu {
        let menu = NSMenu()
        if item.isOn {
            let title = item.isPinned ? String(localized: "Unpin from the Bar") : String(localized: "Pin to the Bar")
            menu.addItem(MenuAction.item(title) { ExtensionsCenter.shared.setPinned(!item.isPinned, item.id) })
        }
        for entry in extra { menu.addItem(entry) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(MenuAction.item(String(localized: "Remove “\(item.name)”…")) {
            confirmRemove(item.id, name: item.name)
        })
        return menu
    }

    /// Asks, then removes it from every Space with what it stored. The
    /// pop-out goes first: the question is modal, and a panel left open
    /// behind it would still list the extension being removed.
    static func confirmRemove(_ id: String, name: String) {
        ExtensionsPopout.closeAll()
        guard SettingsHost.confirm(
            String(localized: "Remove “\(name)”?"),
            String(localized: "It is removed from every Space, with everything it stored."),
            action: String(localized: "Remove")
        ) else { return }
        Task { try? await ExtensionsCenter.shared.uninstall(id) }
    }
}
