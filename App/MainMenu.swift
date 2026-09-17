//
//  MainMenu.swift
//  Luna
//
//  The menu bar, built in code — there is no MainMenu.nib.
//

import AppKit

/// Builds and installs Luna's menu bar.
///
/// M0 scope is deliberately the minimum a macOS app needs to be operable:
/// App, Edit, Window, Help. The complete every-command-discoverable menu
/// (File / View / History / Bookmarks) is §22.5 and lands in M4, once the
/// commands it would expose actually exist.
@MainActor
enum MainMenu {
    /// Builds the menu bar and installs it on `app`.
    static func install(into app: NSApplication) {
        let name = appName

        let edit = menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            .separator(),
            item("Select All", #selector(NSText.selectAll(_:)), "a")
        ])

        let window = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])

        let help = menu("Help", [
            item("\(name) Help", #selector(NSApplication.showHelp(_:)), "?")
        ])

        let main = NSMenu()
        main.addItem(submenu(menu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                 modifiers: [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        ])))
        main.addItem(submenu(edit))
        main.addItem(submenu(window))
        main.addItem(submenu(help))

        app.mainMenu = main
        // AppKit fills these in for us: the window list, and Spotlight for Help.
        app.windowsMenu = window
        app.helpMenu = help
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }

    /// Wraps a menu in the menu-bar item that owns it.
    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A first-responder command. An uppercase `key` implies Shift, per AppKit convention.
    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
