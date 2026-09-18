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

    /// Identifies the View ▸ Sidebar Items submenu, refilled by
    /// `setSidebarItems` on every structural change.
    private static let sidebarItemsTag = 1_002

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

    /// Rebuilds the Spaces menu from the session (§5.3).
    ///
    /// **`⌃1…⌃9`, not `⌘1…⌘9` (spec §13.2, D-S12).** Plain ⌘-number means "go
    /// to tab N" in Safari, Chrome, Firefox, Edge and Arc; Arc puts Spaces on
    /// ⌃-number, Dia on Ctrl-number and Vivaldi on ⌘⇧-number — three products,
    /// three modifiers, none of them ⌘-number. Luna spent that namespace on a
    /// feature 94% of Arc's daily users never used twice (§13.1), so it is
    /// given back to `setSidebarItems` and Spaces move one modifier over.
    ///
    /// A tenth Space is listed and clickable, just without a shortcut — which
    /// is what every other browser does too.
    ///
    /// Previous/Next Space are rebuilt here rather than in `install` because
    /// this method clears the menu; they are the ⌘→⌃ translation of the Window
    /// menu's `⌘⌥←/→`, which still belongs to tabs (§7.4, §20.1).
    static func setSpaces(_ names: [String], in app: NSApplication) {
        guard let menu = app.mainMenu?.items.first(where: { $0.tag == spacesTag })?.submenu else { return }
        menu.removeAllItems()
        for (index, name) in names.enumerated() {
            let entry = item(
                name,
                #selector(AppDelegate.switchToSpace(_:)),
                index < 9 ? String(index + 1) : "",
                modifiers: .control
            )
            entry.tag = index
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Previous Space", #selector(AppDelegate.previousSpace(_:)),
                          arrow: NSLeftArrowFunctionKey, modifiers: [.control, .option]))
        menu.addItem(item("Next Space", #selector(AppDelegate.nextSpace(_:)),
                          arrow: NSRightArrowFunctionKey, modifiers: [.control, .option]))
    }

    /// Rebuilds View ▸ Sidebar Items from the active Space's tabs — §13.2's
    /// other half, and the "go to tab N" Luna did not have at all.
    ///
    /// `⌘1…⌘9`, in the sidebar's own order (Favorites → Pinned → Today), so the
    /// number is the row the user is looking at.
    ///
    /// **A ⌘-number cannot be added to a live menu bar, and that is measured.**
    /// Instrumented on macOS 26.5 inside the running app: an item built with
    /// `keyEquivalent == "1"` still reports `"1"` on the line before
    /// `NSMenu.addItem`, and `""` on the line after — modifier mask intact, key
    /// gone, no error and no warning. `setSpaces` does not hit it because its
    /// items are ⌃-numbers, and the Settings sections do not hit it because
    /// they are built during `install`, before `app.mainMenu` is assigned.
    /// So the nine live from `install` and are only ever renamed; growing the
    /// menu to fit the tab count silently produces a menu with no shortcuts at
    /// all, which is exactly what the first build of this did.
    ///
    /// **View also has to stay ahead of Window in the bar**, which it does:
    /// AppKit's key-equivalent search stops at the first match in menu-bar
    /// order and consumes the event there, disabled or not, so whichever of
    /// these two is found first is the only one that can ever run `⌘1`.
    /// `AppDelegate.goToSidebarItem(_:)` forwards to the Settings window while
    /// that window is key, which is how Window ▸ Settings keeps its own `⌘1`.
    static func setSidebarItems(_ titles: [String], in app: NSApplication) {
        // **Not `mainMenu.items`.** Unlike Spaces this submenu is nested inside
        // View rather than sitting on the bar, so the flat search `setSpaces`
        // uses finds nothing at all — silently, because there is no menu to
        // fill and nothing to report.
        guard let menu = app.mainMenu.flatMap({ tagged(sidebarItemsTag, in: $0) })?.submenu else { return }
        // **The nine items are never created here.** See the doc comment: an
        // item carrying a ⌘-number loses its key equivalent on the way into a
        // menu bar that is already live, so all nine exist from `install` and
        // this only renames and hides them.
        let names = titles.prefix(menu.items.count)
        for (index, entry) in menu.items.enumerated() {
            entry.isHidden = index >= names.count
            guard index < names.count else { continue }
            let title = Array(names)[index]
            entry.title = title.isEmpty ? String(localized: "Untitled") : title
        }
    }

    /// The nine `⌘1…⌘9` items, built **once** and only renamed afterwards.
    ///
    /// Nine placeholders rather than a menu grown to fit, because a tenth tab
    /// gets no shortcut anyway (the same rule a tenth Space follows) and
    /// because the alternative does not work: see `setSidebarItems`.
    private static func sidebarItemsMenu() -> NSMenuItem {
        let entries = (0..<9).map { index -> NSMenuItem in
            let entry = item("", #selector(AppDelegate.goToSidebarItem(_:)), String(index + 1))
            entry.tag = index
            entry.isHidden = true
            return entry
        }
        let host = submenu(menu("Sidebar Items", entries))
        host.tag = sidebarItemsTag
        return host
    }

    // MARK: - The menus

    private static func appMenu() -> NSMenu {
        let name = appName
        return menu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            // SETTINGS-SPEC §2's `⌘,`. Opens the window or brings the one that
            // is already open forward; there is exactly one for the life of the
            // app, and it does not need a session, so it works during a cold
            // launch (see `AppDelegate.validateMenuItem`).
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
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
            // Hides and shows the sidebar. Which layout the window wears is a
            // setting (`⌘,`), not something a reflex keystroke should change.
            item("Hide Sidebar", #selector(AppDelegate.toggleSidebarVisibility(_:)), "s"),
            // §20.1's `⌘D`. Favorites are the sidebar's top tier and are
            // **per Profile**, so this is a View command, not a File one —
            // Luna has no Bookmarks menu to put it in and is not growing one
            // for a single item.
            item("Add to Favorites", #selector(AppDelegate.toggleFavorite(_:)), "d"),
            .separator(),
            // §13.2's `⌘1…⌘9`. **In View, not in Window, and that is measured
            // rather than a taste call** — see `setSidebarItems`.
            sidebarItemsMenu(),
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
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
            .separator(),
            submenu(settingsSectionsMenu())
        ])
    }

    /// SETTINGS-SPEC §2's `⌘F`, and the nine sections as **clickable items with
    /// no key equivalent of their own**.
    ///
    /// **They used to declare `⌘1…⌘9` and AppKit was already deleting them.**
    /// Measured on macOS 26.5 inside the running app: a ⌘-number that duplicates
    /// one already in the menu bar is *erased* — not shadowed, erased — with the
    /// earlier item in menu-bar order keeping the key and the later one coming
    /// back with `keyEquivalent == ""`, modifier mask intact, no error and no
    /// warning. View ▸ Sidebar Items is earlier than Window ▸ Settings, so
    /// re-declaring them here would print a shortcut in the menu that the menu
    /// does not have.
    ///
    /// That is also the receipt on the old Spaces binding: `setSpaces` wrote
    /// `⌘1…⌘9` into a menu bar that was already live and already carried these
    /// nine, so **Luna's shipped `⌘1` for Spaces never worked** — the item was
    /// built with the key and stripped on the way into the menu. §13.2 is a
    /// better binding *and* a repair.
    ///
    /// The window still gets `⌘1…⌘9`: `AppDelegate.goToSidebarItem(_:)` forwards
    /// to it while it is key, and a hidden Sidebar Item still fires its key
    /// equivalent (probed), so all nine arrive whether or not that many tabs are
    /// open.
    private static func settingsSectionsMenu() -> NSMenu {
        var items: [NSMenuItem] = [
            item("Search Settings", #selector(SettingsWindowController.focusSettingsSearch(_:)), "f"),
            .separator()
        ]
        for (index, section) in SettingsSectionRegistry.all.enumerated() {
            let entry = item(section.title, #selector(SettingsWindowController.goToSettingsSection(_:)))
            entry.tag = index
            items.append(entry)
        }
        return menu("Settings", items)
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

    /// The first item carrying `tag`, at any depth. Menu-bar items are only the
    /// top row; everything a submenu owns is a level down.
    private static func tagged(_ tag: Int, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.tag == tag { return item }
            if let submenu = item.submenu, let found = tagged(tag, in: submenu) { return found }
        }
        return nil
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
