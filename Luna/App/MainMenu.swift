//
//  MainMenu.swift
//  Luna
//
//  The menu bar, built in code — there is no MainMenu.nib.
//
//  §22.5: every user-facing command is discoverable here, because a command
//  that is only a keystroke is a command nobody finds. This file owns the
//  structure; `BrowserCommand` owns titles, selectors and keystrokes, and
//  `BrowserCommands.swift` implements the selectors. Luna installs no event
//  monitors and overrides no `performKeyEquivalent`.
//
//  Rebinding rebuilds the whole bar (`rebuild`) rather than editing an item in
//  place: a live menu bar strips a ⌘-number added to it and erases a duplicate
//  ⌘-number's key (measured — see `setSidebarItems`, `settingsSectionsMenu`).
//
//  AppKit injects Writing Tools, AutoFill, Dictation and Emoji & Symbols into
//  any menu titled "Edit". Do not add them by hand as well.
//

import AppKit
import BrowserKit

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
        // Develop sits where Safari puts it, just before Window.
        let develop = DevelopMenu.isShown ? [submenu(developMenu())] : []
        for item in [submenu(appMenu()), submenu(fileMenu()), submenu(editMenu()),
                     submenu(viewMenu()), submenu(historyMenu()), spaces]
            + develop + [submenu(window), submenu(help)] {
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
    /// `⌃1…⌃9`, not `⌘1…⌘9` (spec §13.2, D-S12). Plain ⌘-number means "go to
    /// tab N" in Safari, Chrome, Firefox, Edge and Arc; Arc puts Spaces on
    /// ⌃-number, Dia on Ctrl-number and Vivaldi on ⌘⇧-number. That namespace
    /// is not spent on a feature 94% of Arc's daily users never used twice
    /// (§13.1); it belongs to `setSidebarItems`.
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
    /// other half, "go to tab N".
    ///
    /// `⌘1…⌘9`, in the sidebar's own order (Favorites → Pinned → Today), so the
    /// number is the row the user is looking at.
    ///
    /// A ⌘-number cannot be added to a live menu bar. Measured on macOS 26.5
    /// inside the running app: an item built with `keyEquivalent == "1"`
    /// reports `"1"` on the line before `NSMenu.addItem` and `""` on the line
    /// after — modifier mask intact, key gone, no error. (`setSpaces` escapes it
    /// because its items are ⌃-numbers.) So the nine live from `install` and
    /// are only ever renamed; growing the menu to fit the tab count produces a
    /// menu with no shortcuts at all.
    ///
    /// View has to stay ahead of Window in the bar: AppKit's key-equivalent
    /// search stops at the first match in menu-bar order and consumes the event
    /// there, disabled or not, so only the first can ever run `⌘1`.
    /// `AppDelegate.goToSidebarItem(_:)` forwards to the Settings window while
    /// that window is key, which is how Window ▸ Settings keeps its own `⌘1`.
    static func setSidebarItems(_ titles: [String], in app: NSApplication) {
        // Not `mainMenu.items`. Unlike Spaces this submenu is nested inside
        // View rather than sitting on the bar, so the flat search `setSpaces`
        // uses finds nothing at all — silently, because there is no menu to
        // fill and nothing to report.
        guard let menu = app.mainMenu.flatMap({ tagged(sidebarItemsTag, in: $0) })?.submenu else { return }
        // The nine items are never created here — see the doc comment. This
        // only renames and hides them.
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
            // Settings › About rather than AppKit's panel: the version is there,
            // and so is the one thing a person asking about it wants next.
            plain("About \(name)", #selector(AppDelegate.showAbout(_:))),
            plain("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
            .separator(),
            // SETTINGS-SPEC §2's `⌘,`. Opens the window or brings the one that
            // is already open forward; there is exactly one for the life of the
            // app, and it does not need a session, so it works during a cold
            // launch (see `AppDelegate.validateMenuItem`).
            item(.settings),
            .separator(),
            // Luna Control's kill switch, beside Quit's neighbours because it is
            // the other "make everything stop" in the menu. Titled by
            // `validateStopAllAgents`.
            plain("Stop All Agents", #selector(AppDelegate.toggleStopAllAgents(_:))),
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
            [item(.newTab)], items(.newWindow), items(.newPrivateWindow), items(.openLocation), items(.openFile),
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
            items(.reloadPage), items(.forceReloadPage), items(.stopLoading), items(.openBlockedPopup),
            [.separator()],
            items(.zoomIn), items(.zoomOut), items(.actualSize),
            [.separator()],
            items(.pictureInPicture),
            [.separator()],
            items(.reader), items(.hideElements),
            [.separator()],
            // §22.5: the list both layouts' Downloads buttons open. ⌘⌥L is
            // free in the §20.1 map and is what Safari uses.
            items(.showDownloads)
        ]))
    }

    private static func historyMenu() -> NSMenu {
        menu("History", flatten([
            items(.goBack), items(.goForward),
            [.separator()],
            // §6.4's pop-out. It hangs off a button in both layouts, and §22.5
            // wants it reachable from the menu bar too.
            items(.showHistory),
            [.separator()],
            [otherMacsMenu()]
        ]))
    }

    private static func developMenu() -> NSMenu {
        menu("Develop", flatten([
            items(.showWebInspector), items(.showJavaScriptConsole), items(.showPageSource),
            items(.startElementSelection),
            [.separator()],
            [submenu(userAgentMenu())], items(.disableJavaScript),
            [.separator()],
            items(.emptyCaches)
        ]))
    }

    /// The same four modes as Settings ▸ Advanced, ticked by
    /// `validateDevelopCommand`.
    private static func userAgentMenu() -> NSMenu {
        let titles = [
            String(localized: "Default"), String(localized: "Safari"),
            String(localized: "Chrome"), String(localized: "Custom")
        ]
        let entries = titles.enumerated().map { index, title in
            let entry = plain(title, #selector(AppDelegate.chooseUserAgent(_:)))
            entry.tag = index
            return entry
        }
        return menu("User Agent", entries)
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
    /// Not `⌘1…⌘9`. Measured on macOS 26.5: a ⌘-number duplicating one
    /// already in the menu bar is erased, not shadowed — the earlier item in
    /// menu-bar order keeps the key and the later one comes back with
    /// `keyEquivalent == ""`, no error, no warning. View ▸ Sidebar Items is
    /// earlier than Window ▸ Settings, so declaring them here would print a
    /// shortcut the menu does not have.
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

// MARK: - Tabs on Other Macs

extension MainMenu {

    /// Identifies History ▸ Tabs on Other Macs, refilled by `setOtherMacs`.
    private static let otherMacsTag = 1_003

    /// Kept so `rebuild` can refill the submenu; unlike Spaces, nothing else
    /// re-sends it after a rebind.
    private static var otherMacs: [SyncDevice] = []

    /// History ▸ Tabs on Other Macs (docs/plans/SYNC-PLAN.md §5): one section per
    /// Mac, already filtered by `SyncCoordinator.otherMacs`.
    static func setOtherMacs(_ macs: [SyncDevice], in app: NSApplication) {
        otherMacs = macs
        guard let menu = app.mainMenu.flatMap({ tagged(otherMacsTag, in: $0) })?.submenu else { return }
        fill(menu, with: macs)
    }

    private static func otherMacsMenu() -> NSMenuItem {
        let list = menu("Tabs on Other Macs", [])
        fill(list, with: otherMacs)
        let host = submenu(list)
        host.tag = otherMacsTag
        return host
    }

    private static func fill(_ menu: NSMenu, with macs: [SyncDevice]) {
        menu.removeAllItems()
        guard !macs.isEmpty else {
            menu.addItem(NSMenuItem(title: String(localized: "No Other Macs"), action: nil, keyEquivalent: ""))
            return
        }
        for mac in macs {
            menu.addItem(.sectionHeader(title: mac.name))
            for tab in mac.tabs {
                let title = tab.title.isEmpty ? (tab.url.host() ?? tab.url.absoluteString) : tab.title
                let entry = NSMenuItem(title: title, action: #selector(AppDelegate.openTabFromOtherMac(_:)), keyEquivalent: "")
                entry.representedObject = tab.url
                menu.addItem(entry)
            }
        }
    }
}
