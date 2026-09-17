//
//  SidebarMenu.swift
//  Luna
//
//  Context menus for the sidebar — pin, unpin, close. One helper for the whole
//  sidebar because `NSMenuItem` dispatches through target/action and a closure
//  has no target: without this, every menu would need a `@objc` method on some
//  view that happens to still be alive when the item fires, which for a row
//  view the table is free to recycle is a use-after-free waiting to happen.
//
//  `ClosureMenuItem` is its own target, so the action lives exactly as long as
//  the item does, and the menu owns both.
//

import AppKit

@MainActor
enum SidebarMenu {

    /// A menu item that runs `action`. The item retains the closure; nothing
    /// else has to stay alive for it to fire.
    static func item(title: String, action: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, action: action)
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {

    private let body: () -> Void

    init(title: String, action: @escaping () -> Void) {
        body = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() {
        body()
    }
}
