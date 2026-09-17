//
//  MainMenu.swift
//  Luna
//
//  The menu bar, built in code — there is no MainMenu.nib.
//
//  §22.5: every user-facing command is discoverable here, because a command
//  that is only a keystroke is a command nobody finds. The §20.1 key map is
//  therefore declared **once**, in this file, and `AppDelegate` implements the
//  selectors (`BrowserCommands.swift`). Luna installs no event monitors and
//  overrides no `performKeyEquivalent`.
//
//  Bookmarks and a History list are absent on purpose: they have no commands
//  yet (§11.3, §11.4), and a menu of permanently dimmed items is worse than a
//  shorter menu.
//
//  Cosmetic, verified in M0: AppKit auto-injects Writing Tools, AutoFill,
//  Dictation and Emoji & Symbols into any menu titled "Edit". Do not add them
//  by hand as well.
//

import AppKit

/// Builds and installs Luna's menu bar.
@MainActor
enum MainMenu {

    /// Identifies the Spaces submenu so `setSpaces` can refill it without
    /// rebuilding the menu bar.
    private static let spacesTag = 1_001

    /// Builds the menu bar and installs it on `app`.
    static func install(into app: NSApplication) {
        let window = windowMenu()
        let help = helpMenu()
        let spaces = submenu(menu("Spaces", []))
        spaces.tag = spacesTag

        let main = NSMenu()
        for item in [submenu(appMenu()), submenu(fileMenu()), submenu(editMenu()),
                     submenu(viewMenu()), submenu(historyMenu()), spaces,
                     submenu(window), submenu(help)] {
            main.addItem(item)
        }

        app.mainMenu = main
        // AppKit fills these in for us: the window list, and Spotlight for Help.
        app.windowsMenu = window
        app.helpMenu = help
    }

    /// Rebuilds the Spaces menu from the session (§5.3). `⌘1…⌘9`; a tenth Space
    /// is listed and clickable, just without a shortcut — which is what every
    /// other browser does too.
    static func setSpaces(_ names: [String], in app: NSApplication) {
        guard let menu = app.mainMenu?.items.first(where: { $0.tag == spacesTag })?.submenu else { return }
        menu.removeAllItems()
        for (index, name) in names.enumerated() {
            let entry = item(name, #selector(AppDelegate.switchToSpace(_:)), index < 9 ? String(index + 1) : "")
            entry.tag = index
            menu.addItem(entry)
        }
    }

    // MARK: - The menus

    private static func appMenu() -> NSMenu {
        let name = appName
        return menu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                 modifiers: [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        ])
    }

    private static func fileMenu() -> NSMenu {
        menu("File", [
            item("New Tab", #selector(AppDelegate.newTab(_:)), "t"),
            item("Open Location…", #selector(AppDelegate.editLocation(_:)), "l"),
            .separator(),
            item("Close Tab", #selector(AppDelegate.closeTab(_:)), "w"),
            item("Reopen Last Archived Tab", #selector(AppDelegate.reopenArchivedTab(_:)), "T")
        ])
    }

    private static func editMenu() -> NSMenu {
        menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            .separator(),
            item("Select All", #selector(NSText.selectAll(_:)), "a")
        ])
    }

    private static func viewMenu() -> NSMenu {
        menu("View", [
            item("Toggle Sidebar", #selector(AppDelegate.toggleChromeLayout(_:)), "s"),
            .separator(),
            item("Reload Page", #selector(AppDelegate.reloadPage(_:)), "r"),
            item("Stop Loading", #selector(AppDelegate.stopLoading(_:)), "."),
            .separator(),
            // §22.5: the downloads panel is only otherwise reachable from the
            // top bar's button, which the sidebar layout does not show at all.
            // ⌘⌥L is free in the §20.1 map and is what Safari uses.
            item("Downloads", #selector(AppDelegate.showDownloads(_:)), "l", modifiers: [.command, .option])
        ])
    }

    private static func historyMenu() -> NSMenu {
        menu("History", [
            item("Back", #selector(AppDelegate.goBack(_:)), "["),
            item("Forward", #selector(AppDelegate.goForward(_:)), "]")
        ])
    }

    private static func windowMenu() -> NSMenu {
        menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Show Previous Tab", #selector(AppDelegate.previousTab(_:)),
                 arrow: NSLeftArrowFunctionKey, modifiers: [.command, .option]),
            item("Show Next Tab", #selector(AppDelegate.nextTab(_:)),
                 arrow: NSRightArrowFunctionKey, modifiers: [.command, .option]),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])
    }

    private static func helpMenu() -> NSMenu {
        menu("Help", [
            item("\(appName) Help", #selector(NSApplication.showHelp(_:)), "?")
        ])
    }

    // MARK: - Construction

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

    /// An arrow-key command. `NSLeftArrowFunctionKey` and friends are `Int`
    /// constants in the private-use plane, not characters, so they have to be
    /// spelled as a scalar — `"←"` in a source file does not work.
    private static func item(
        _ title: String,
        _ action: Selector,
        arrow: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let key = UnicodeScalar(UInt32(arrow)).map { String(Character($0)) } ?? ""
        return item(title, action, key, modifiers: modifiers)
    }
}
