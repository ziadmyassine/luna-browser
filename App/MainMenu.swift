//
//  MainMenu.swift
//  Luna
//
//  The menu bar, built in code — there is no MainMenu.nib.
//
//  §22.5: every user-facing command is discoverable here, because a command
//  that is only a keystroke is a command nobody finds. This file owns the
//  structure — which menu a command is in and what it sits beside — and
//  `BrowserCommand` owns the map of titles, selectors and keystrokes.
//  `AppDelegate` implements the selectors (`BrowserCommands.swift`). Luna
//  installs no event monitors and overrides no `performKeyEquivalent`.
//
//  Rebinding rebuilds the whole bar rather than editing an item in place
//  (`rebuild`). Not caution: this file already records two measured ways a live
//  menu bar refuses a key equivalent — a ⌘-number added to one is stripped on
//  the way in, and a duplicate ⌘-number erases the later item's key. Both were
//  found by writing to a bar that was already installed. Building a fresh bar
//  and assigning it is the path that is known to work, it is what launch does,
//  and it costs one menu's worth of `NSMenuItem`s on a keystroke the user
//  presses about twice a year.
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

    /// A fresh bar wearing the current bindings. The Spaces and Sidebar Items
    /// submenus come back empty — they are built from the session, so the caller
    /// re-runs `setSpaces` and `setSidebarItems` after this.
    static func rebuild(in app: NSApplication) {
        install(into: app)
    }

    /// Rebuilds the Spaces menu from the session (§5.3).
    ///
    /// `⌃1…⌃9`, not `⌘1…⌘9` (spec §13.2, D-S12). Plain ⌘-number means "go
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
            let entry = NSMenuItem(
                title: name,
                action: #selector(AppDelegate.switchToSpace(_:)),
                keyEquivalent: index < 9 ? String(index + 1) : ""
            )
            entry.keyEquivalentModifierMask = .control
            entry.tag = index
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        for entry in items(.previousSpace) + items(.nextSpace) { menu.addItem(entry) }
    }

    /// Rebuilds View ▸ Sidebar Items from the active Space's tabs — §13.2's
    /// other half, and the "go to tab N" Luna did not have at all.
    ///
    /// `⌘1…⌘9`, in the sidebar's own order (Favorites → Pinned → Today), so the
    /// number is the row the user is looking at.
    ///
    /// A ⌘-number cannot be added to a live menu bar, and that is measured.
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
    /// View also has to stay ahead of Window in the bar, which it does:
    /// AppKit's key-equivalent search stops at the first match in menu-bar
    /// order and consumes the event there, disabled or not, so whichever of
    /// these two is found first is the only one that can ever run `⌘1`.
    /// `AppDelegate.goToSidebarItem(_:)` forwards to the Settings window while
    /// that window is key, which is how Window ▸ Settings keeps its own `⌘1`.
    static func setSidebarItems(_ titles: [String], in app: NSApplication) {
        // Not `mainMenu.items`. Unlike Spaces this submenu is nested inside
        // View rather than sitting on the bar, so the flat search `setSpaces`
        // uses finds nothing at all — silently, because there is no menu to
        // fill and nothing to report.
        guard let menu = app.mainMenu.flatMap({ tagged(sidebarItemsTag, in: $0) })?.submenu else { return }
        // The nine items are never created here. See the doc comment: an
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

    /// The nine `⌘1…⌘9` items, built once and only renamed afterwards.
    ///
    /// Nine placeholders rather than a menu grown to fit, because a tenth tab
    /// gets no shortcut anyway (the same rule a tenth Space follows) and
    /// because the alternative does not work: see `setSidebarItems`.
    private static func sidebarItemsMenu() -> NSMenuItem {
        let entries = (0..<9).map { index -> NSMenuItem in
            let entry = NSMenuItem(
                title: "",
                action: #selector(AppDelegate.goToSidebarItem(_:)),
                keyEquivalent: String(index + 1)
            )
            entry.keyEquivalentModifierMask = .command
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
            plain("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            // SETTINGS-SPEC §2's `⌘,`. Opens the window or brings the one that
            // is already open forward; there is exactly one for the life of the
            // app, and it does not need a session, so it works during a cold
            // launch (see `AppDelegate.validateMenuItem`).
            item(.settings),
            .separator(),
            plain("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            plain("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                  modifiers: [.command, .option]),
            plain("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            plain("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        ])
    }

    private static func fileMenu() -> NSMenu {
        menu("File", flatten([
            [item(.newTab)], items(.openLocation),
            [.separator()],
            items(.duplicateTab), items(.resetPinnedTab),
            [.separator()],
            items(.closeTab), items(.closeAllTabs), items(.cleanUpTabs), items(.reopenArchivedTab),
            [.separator()],
            items(.closeWindow)
        ]))
    }

    private static func editMenu() -> NSMenu {
        menu("Edit", flatten([
            items(.undo), items(.redo),
            [.separator()],
            items(.cut), items(.copy), items(.paste),
            [.separator()],
            items(.selectAll),
            [.separator()],
            // §11.2's two: the address the user is looking at, plain or wrapped
            // in the link syntax every notes app in the dock understands.
            items(.copyURL), items(.copyMarkdown)
        ]))
    }

    private static func viewMenu() -> NSMenu {
        menu("View", flatten([
            // Hides and shows the sidebar. Which layout the window wears is a
            // setting (`⌘,`), not something a reflex keystroke should change.
            items(.toggleSidebar),
            // §20.1's `⌘D`. Favorites are the sidebar's top tier and are
            // per Profile, so this is a View command, not a File one —
            // Luna has no Bookmarks menu to put it in and is not growing one
            // for a single item.
            items(.toggleFavorite),
            [.separator()],
            // §13.2's `⌘1…⌘9`. In View, not in Window, and that is measured
            // rather than a taste call — see `setSidebarItems`.
            [sidebarItemsMenu()],
            [.separator()],
            items(.reloadPage), items(.forceReloadPage), items(.stopLoading),
            [.separator()],
            items(.zoomIn), items(.zoomOut), items(.actualSize),
            [.separator()],
            // §22.5: the downloads panel is only otherwise reachable from the
            // top bar's button, which the sidebar layout does not show at all.
            // ⌘⌥L is free in the §20.1 map and is what Safari uses.
            items(.showDownloads)
        ]))
    }

    private static func historyMenu() -> NSMenu {
        menu("History", flatten([
            items(.goBack), items(.goForward),
            [.separator()],
            // §6.4's pop-out. It hangs off a button in both layouts and had no
            // keystroke at all, which made it the one §22.5 violation left.
            items(.showHistory)
        ]))
    }

    private static func windowMenu() -> NSMenu {
        menu("Window", flatten([
            items(.minimize),
            [plain("Zoom", #selector(NSWindow.performZoom(_:)))],
            [.separator()],
            items(.previousTab), items(.nextTab),
            [.separator()],
            [plain("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))],
            [.separator()],
            [submenu(settingsSectionsMenu())]
        ]))
    }

    /// SETTINGS-SPEC §2's `⌘F`, and the nine sections as clickable items with
    /// no key equivalent of their own.
    ///
    /// They used to declare `⌘1…⌘9` and AppKit was already deleting them.
    /// Measured on macOS 26.5 inside the running app: a ⌘-number that duplicates
    /// one already in the menu bar is erased — not shadowed, erased — with the
    /// earlier item in menu-bar order keeping the key and the later one coming
    /// back with `keyEquivalent == ""`, modifier mask intact, no error and no
    /// warning. View ▸ Sidebar Items is earlier than Window ▸ Settings, so
    /// re-declaring them here would print a shortcut in the menu that the menu
    /// does not have.
    ///
    /// That is also the receipt on the old Spaces binding: `setSpaces` wrote
    /// `⌘1…⌘9` into a menu bar that was already live and already carried these
    /// nine, so Luna's shipped `⌘1` for Spaces never worked — the item was
    /// built with the key and stripped on the way into the menu. §13.2 is a
    /// better binding and a repair.
    ///
    /// The window still gets `⌘1…⌘9`: `AppDelegate.goToSidebarItem(_:)` forwards
    /// to it while it is key, and a hidden Sidebar Item still fires its key
    /// equivalent (probed), so all nine arrive whether or not that many tabs are
    /// open.
    private static func settingsSectionsMenu() -> NSMenu {
        var entries: [NSMenuItem] = items(.searchSettings) + [.separator()]
        for (index, section) in SettingsSectionRegistry.all.enumerated() {
            let entry = plain(section.title, #selector(SettingsWindowController.goToSettingsSection(_:)))
            entry.tag = index
            entries.append(entry)
        }
        return menu("Settings", entries)
    }

    private static func helpMenu() -> NSMenu {
        menu("Help", [plain("\(appName) Help", #selector(NSApplication.showHelp(_:)), "?")])
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

    private static func flatten(_ groups: [[NSMenuItem]]) -> [NSMenuItem] { groups.flatMap { $0 } }

    /// Wraps a menu in the menu-bar item that owns it.
    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// The command as the user sees it, plus a hidden item per alternate
    /// binding. A hidden item is not in the menu and still answers its key
    /// equivalent — the same behaviour §13.2's sidebar rows were built on.
    static func items(_ command: BrowserCommand) -> [NSMenuItem] {
        let bindings = KeyBindings.bindings(for: command)
        let visible = item(command)
        return [visible] + bindings.dropFirst().map { binding in
            let alternate = NSMenuItem(title: command.title, action: command.action, keyEquivalent: binding.key)
            alternate.keyEquivalentModifierMask = binding.modifiers
            alternate.isHidden = true
            return alternate
        }
    }

    /// The printed item: the command's title, its selector and whichever
    /// keystroke `KeyBindings` says it wears today.
    static func item(_ command: BrowserCommand) -> NSMenuItem {
        let binding = KeyBindings.primary(for: command)
        let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: binding?.key ?? "")
        item.keyEquivalentModifierMask = binding?.modifiers ?? []
        return item
    }

    /// A menu entry that is not a `BrowserCommand`: AppKit's own, and the
    /// Settings section rows. An uppercase `key` implies Shift, per AppKit
    /// convention.
    private static func plain(
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
