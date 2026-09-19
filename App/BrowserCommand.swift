//
//  BrowserCommand.swift
//  Luna
//
//  §20.1's key map, as a table rather than as literals scattered through
//  `MainMenu`.
//
//  It moved because the map became editable (§3.6). A shortcut the user can
//  change needs three things a literal cannot give it: a **stable identity** to
//  store an override against — one that survives the item being retitled or
//  moved to another menu — a **default** to reset back to, and a list every
//  other command can be checked against for conflicts. `MainMenu` still owns the
//  structure: which menu a command sits in, and what it sits next to.
//
//  **`defaults` is a list, and only the first is printed.** Several commands are
//  reachable two ways on purpose: Zoom In answers to ⌘+ and to the ⌘= the user
//  actually presses, and Show Next Tab answers both to Arc's ⌘⌥→ and to the
//  ⇧⌘] every other browser uses. The extras are hidden menu items — a hidden
//  item still fires its key equivalent, which `MainMenu` measured for §13.2's
//  sidebar rows and which this leans on.
//
//  A **user override replaces the whole list**, alternates included. The
//  alternative — keeping ours alive underneath theirs — means a user who moved
//  Show Next Tab to ⌃⇥ finds ⇧⌘] still doing it, with nothing in the UI saying
//  so.
//
//  `isCustomisable: false` is not a second class of command; it is a command
//  whose shortcut belongs to macOS rather than to Luna. ⌘Q, ⌘X and ⌘M are
//  muscle memory older than this app, and a browser is not the place to find out
//  what happens when Quit moves. They are still in the table, because the
//  conflict check has to know they are taken.
//

import AppKit

@MainActor
struct BrowserCommand: Identifiable {

    /// Stable across renames and re-homing — it is the `UserDefaults` key an
    /// override is stored under, so changing one forgets that override.
    let id: String
    let title: String
    let action: Selector
    /// The shipped binding. First is printed in the menu; the rest are hidden
    /// items that fire and nothing more. Empty for a command with no shortcut.
    let defaults: [KeyBinding]
    /// False for the handful macOS owns — see the file header.
    let isCustomisable: Bool

    init(
        _ id: String,
        _ title: String,
        _ action: Selector,
        _ defaults: [KeyBinding] = [],
        customisable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.defaults = defaults
        self.isCustomisable = customisable
    }

    // MARK: - App

    static let settings = BrowserCommand(
        "settings", "Settings…", #selector(AppDelegate.showSettings(_:)),
        [KeyBinding(",")], customisable: false
    )

    // MARK: - File

    static let newTab = BrowserCommand("newTab", "New Tab", #selector(AppDelegate.newTab(_:)), [KeyBinding("t")])
    static let openLocation = BrowserCommand(
        "openLocation", "Open Location…", #selector(AppDelegate.editLocation(_:)), [KeyBinding("l")]
    )
    static let duplicateTab = BrowserCommand(
        "duplicateTab", "Duplicate Tab", #selector(AppDelegate.duplicateTab(_:))
    )
    static let resetPinnedTab = BrowserCommand(
        "resetPinnedTab", "Reset Pinned Tab to Base URL", #selector(AppDelegate.resetPinnedTab(_:))
    )
    static let closeTab = BrowserCommand("closeTab", "Close Tab", #selector(AppDelegate.closeTab(_:)), [KeyBinding("w")])
    static let closeAllTabs = BrowserCommand(
        "closeAllTabs", "Close All Tabs", #selector(AppDelegate.closeAllTabs(_:)),
        [KeyBinding("k", [.command, .shift])]
    )
    static let cleanUpTabs = BrowserCommand(
        "cleanUpTabs", "Clean Up Tabs", #selector(AppDelegate.cleanUpTabs(_:)),
        [KeyBinding("k", [.command, .option])]
    )
    static let reopenArchivedTab = BrowserCommand(
        "reopenArchivedTab", "Reopen Last Archived Tab", #selector(AppDelegate.reopenArchivedTab(_:)),
        [KeyBinding("t", [.command, .shift])]
    )
    static let closeWindow = BrowserCommand(
        "closeWindow", "Close Window", #selector(NSWindow.performClose(_:)),
        [KeyBinding("w", [.command, .shift])], customisable: false
    )

    // MARK: - Edit

    static let undo = BrowserCommand("undo", "Undo", Selector(("undo:")), [KeyBinding("z")], customisable: false)
    static let redo = BrowserCommand(
        "redo", "Redo", Selector(("redo:")), [KeyBinding("z", [.command, .shift])], customisable: false
    )
    static let cut = BrowserCommand("cut", "Cut", #selector(NSText.cut(_:)), [KeyBinding("x")], customisable: false)
    static let copy = BrowserCommand("copy", "Copy", #selector(NSText.copy(_:)), [KeyBinding("c")], customisable: false)
    static let paste = BrowserCommand(
        "paste", "Paste", #selector(NSText.paste(_:)), [KeyBinding("v")], customisable: false
    )
    static let selectAll = BrowserCommand(
        "selectAll", "Select All", #selector(NSText.selectAll(_:)), [KeyBinding("a")], customisable: false
    )
    static let copyURL = BrowserCommand(
        "copyURL", "Copy URL", #selector(AppDelegate.copyPageURL(_:)), [KeyBinding("c", [.command, .shift])]
    )
    static let copyMarkdown = BrowserCommand(
        "copyMarkdown", "Copy URL as Markdown", #selector(AppDelegate.copyPageMarkdown(_:)),
        [KeyBinding("c", [.command, .option, .shift])]
    )

    // MARK: - View

    static let toggleSidebar = BrowserCommand(
        "toggleSidebar", "Hide Sidebar", #selector(AppDelegate.toggleSidebarVisibility(_:)), [KeyBinding("s")]
    )
    static let toggleFavorite = BrowserCommand(
        "toggleFavorite", "Add to Favorites", #selector(AppDelegate.toggleFavorite(_:)), [KeyBinding("d")]
    )
    static let reloadPage = BrowserCommand(
        "reloadPage", "Reload Page", #selector(AppDelegate.reloadPage(_:)), [KeyBinding("r")]
    )
    static let forceReloadPage = BrowserCommand(
        "forceReloadPage", "Force Refresh the Page", #selector(AppDelegate.forceReloadPage(_:)),
        [KeyBinding("r", [.command, .shift])]
    )
    static let stopLoading = BrowserCommand(
        "stopLoading", "Stop Loading", #selector(AppDelegate.stopLoading(_:)), [KeyBinding(".")]
    )
    /// ⌘+ is the shortcut everyone writes down and ⌘= is the one their hand
    /// performs, because + is the shifted key. Both, or the menu prints a
    /// keystroke that needs a shift the user will not press.
    static let zoomIn = BrowserCommand(
        "zoomIn", "Zoom In", #selector(AppDelegate.zoomIn(_:)), [KeyBinding("+"), KeyBinding("=")]
    )
    static let zoomOut = BrowserCommand(
        "zoomOut", "Zoom Out", #selector(AppDelegate.zoomOut(_:)), [KeyBinding("-")]
    )
    static let actualSize = BrowserCommand(
        "actualSize", "Zoom to Actual Size", #selector(AppDelegate.resetZoom(_:)), [KeyBinding("0")]
    )
    static let showDownloads = BrowserCommand(
        "showDownloads", "Downloads", #selector(AppDelegate.showDownloads(_:)), [KeyBinding("l", [.command, .option])]
    )

    // MARK: - History

    static let goBack = BrowserCommand("goBack", "Back", #selector(AppDelegate.goBack(_:)), [KeyBinding("[")])
    static let goForward = BrowserCommand(
        "goForward", "Forward", #selector(AppDelegate.goForward(_:)), [KeyBinding("]")]
    )
    static let showHistory = BrowserCommand(
        "showHistory", "Show History…", #selector(AppDelegate.showHistory(_:)), [KeyBinding("y")]
    )

    // MARK: - Window

    static let previousTab = BrowserCommand(
        "previousTab", "Show Previous Tab", #selector(AppDelegate.previousTab(_:)),
        [KeyBinding(function: NSLeftArrowFunctionKey, [.command, .option]), KeyBinding("[", [.command, .shift])]
    )
    static let nextTab = BrowserCommand(
        "nextTab", "Show Next Tab", #selector(AppDelegate.nextTab(_:)),
        [KeyBinding(function: NSRightArrowFunctionKey, [.command, .option]), KeyBinding("]", [.command, .shift])]
    )
    static let previousSpace = BrowserCommand(
        "previousSpace", "Previous Space", #selector(AppDelegate.previousSpace(_:)),
        [KeyBinding(function: NSLeftArrowFunctionKey, [.control, .option])]
    )
    static let nextSpace = BrowserCommand(
        "nextSpace", "Next Space", #selector(AppDelegate.nextSpace(_:)),
        [KeyBinding(function: NSRightArrowFunctionKey, [.control, .option])]
    )
    static let minimize = BrowserCommand(
        "minimize", "Minimize", #selector(NSWindow.performMiniaturize(_:)), [KeyBinding("m")], customisable: false
    )
    static let searchSettings = BrowserCommand(
        "searchSettings", "Search Settings", #selector(SettingsWindowController.focusSettingsSearch(_:)),
        [KeyBinding("f")], customisable: false
    )

    // MARK: - The table

    /// Every command that can hold a shortcut, in menu order. The numbered
    /// families are absent on purpose — see `KeyBindings.reserved`.
    static let all: [BrowserCommand] = [
        settings,
        newTab, openLocation, duplicateTab, resetPinnedTab, closeTab, closeAllTabs, cleanUpTabs,
        reopenArchivedTab, closeWindow,
        undo, redo, cut, copy, paste, selectAll, copyURL, copyMarkdown,
        toggleSidebar, toggleFavorite, reloadPage, forceReloadPage, stopLoading,
        zoomIn, zoomOut, actualSize, showDownloads,
        goBack, goForward, showHistory,
        previousTab, nextTab, previousSpace, nextSpace, minimize, searchSettings
    ]

    static func command(id: String) -> BrowserCommand? { all.first { $0.id == id } }
}
