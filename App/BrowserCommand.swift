//
//  BrowserCommand.swift
//  Luna
//
//  §20.1's key map, as a table rather than as literals scattered through
//  `MainMenu`.
//
//  It moved because the map became editable (§3.6). A shortcut the user can
//  change needs three things a literal cannot give it: a stable identity to
//  store an override against, one that survives the item being retitled or
//  moved; a default to reset back to; and a list every other command can be
//  checked against for conflicts. `MainMenu` still owns the structure.
//
//  `defaults` is a list and only the first is printed. Several commands are
//  reachable two ways on purpose — Zoom In answers ⌘+ and the ⌘= the user
//  actually presses, Show Next Tab answers Arc's ⌘⌥→ and the ⇧⌘] every other
//  browser uses. The extras are hidden menu items, and a hidden item still
//  fires its key equivalent.
//
//  A user override replaces the whole list, alternates included: keeping ours
//  alive underneath theirs means a user who moved Show Next Tab to ⌃⇥ finds
//  ⇧⌘] still doing it, with nothing in the UI saying so.
//
//  `isCustomisable: false` is not a second class of command, it is one whose
//  shortcut belongs to macOS rather than to Luna. ⌘Q, ⌘X and ⌘M are muscle
//  memory older than this app. They are still in the table, because the
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
    /// The SF Symbol §9.2's row wears, and the mark that says this command
    /// belongs in the Command Bar at all — see `commandBarEntries`.
    let symbolName: String?
    /// What should find the command besides its title, lowercased. Copy URL is
    /// the case that needs it: everybody calls that one copying the link.
    let keywords: [String]

    init(
        _ id: String,
        _ title: String,
        _ action: Selector,
        _ defaults: [KeyBinding] = [],
        customisable: Bool = true,
        symbol: String? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.defaults = defaults
        self.isCustomisable = customisable
        self.symbolName = symbol
        self.keywords = keywords
    }

    // MARK: - App

    static let settings = BrowserCommand(
        "settings", "Settings…", #selector(AppDelegate.showSettings(_:)),
        [KeyBinding(",")], customisable: false
    )

    // MARK: - File

    static let newTab = BrowserCommand("newTab", "New Tab", #selector(AppDelegate.newTab(_:)), [KeyBinding("t")], symbol: "plus.square")
    static let newWindow = BrowserCommand(
        "newWindow", "New Window", #selector(AppDelegate.newWindow(_:)), [KeyBinding("n")],
        symbol: "macwindow.badge.plus"
    )
    /// §5.6. `⌘⇧N` everywhere except Safari, which spends it on a second
    /// profile window — and Luna's Spaces are what that shortcut would be for.
    static let newPrivateWindow = BrowserCommand(
        "newPrivateWindow", "New Private Window", #selector(AppDelegate.newPrivateWindow(_:)),
        [KeyBinding("n", [.command, .shift])],
        symbol: "eyeglasses", keywords: ["incognito", "private browsing"]
    )
    static let openLocation = BrowserCommand(
        "openLocation", "Open Location…", #selector(AppDelegate.editLocation(_:)), [KeyBinding("l")]
    )
    static let duplicateTab = BrowserCommand(
        "duplicateTab", "Duplicate Tab", #selector(AppDelegate.duplicateTab(_:)), symbol: "doc.on.doc"
    )
    static let resetPinnedTab = BrowserCommand(
        "resetPinnedTab", "Reset Pinned Tab to Base URL", #selector(AppDelegate.resetPinnedTab(_:)),
        symbol: "pin", keywords: ["pinned"]
    )
    static let closeTab = BrowserCommand(
        "closeTab", "Close Tab", #selector(AppDelegate.closeTab(_:)), [KeyBinding("w")], symbol: "xmark.square"
    )
    static let closeAllTabs = BrowserCommand(
        "closeAllTabs", "Close All Tabs", #selector(AppDelegate.closeAllTabs(_:)),
        [KeyBinding("k", [.command, .shift])],
        symbol: "rectangle.stack.badge.minus", keywords: ["clear tabs"]
    )
    static let cleanUpTabs = BrowserCommand(
        "cleanUpTabs", "Clean Up Tabs", #selector(AppDelegate.cleanUpTabs(_:)),
        [KeyBinding("k", [.command, .option])],
        symbol: "sparkles", keywords: ["tidy tabs"]
    )
    static let reopenArchivedTab = BrowserCommand(
        "reopenArchivedTab", "Reopen Last Archived Tab", #selector(AppDelegate.reopenArchivedTab(_:)),
        [KeyBinding("t", [.command, .shift])],
        symbol: "arrow.uturn.backward", keywords: ["undo close tab", "restore tab"]
    )
    static let closeWindow = BrowserCommand(
        "closeWindow", "Close Window", #selector(NSWindow.performClose(_:)),
        [KeyBinding("w", [.command, .shift])], customisable: false, symbol: "macwindow"
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
        "copyURL", "Copy URL", #selector(AppDelegate.copyPageURL(_:)), [KeyBinding("c", [.command, .shift])],
        symbol: "link", keywords: ["copy link", "address", "url", "share"]
    )
    static let copyMarkdown = BrowserCommand(
        "copyMarkdown", "Copy URL as Markdown", #selector(AppDelegate.copyPageMarkdown(_:)),
        [KeyBinding("c", [.command, .option, .shift])],
        symbol: "doc.on.clipboard", keywords: ["copy link", "markdown"]
    )

    // MARK: - View

    static let toggleSidebar = BrowserCommand(
        "toggleSidebar", "Hide Sidebar", #selector(AppDelegate.toggleSidebarVisibility(_:)), [KeyBinding("s")]
    )
    static let toggleFavorite = BrowserCommand(
        "toggleFavorite", "Add to Favorites", #selector(AppDelegate.toggleFavorite(_:)), [KeyBinding("d")],
        symbol: "star", keywords: ["favourite", "bookmark"]
    )
    static let reloadPage = BrowserCommand(
        "reloadPage", "Reload Page", #selector(AppDelegate.reloadPage(_:)), [KeyBinding("r")],
        symbol: "arrow.clockwise", keywords: ["refresh"]
    )
    static let forceReloadPage = BrowserCommand(
        "forceReloadPage", "Force Refresh the Page", #selector(AppDelegate.forceReloadPage(_:)),
        [KeyBinding("r", [.command, .shift])], symbol: "arrow.clockwise.circle", keywords: ["hard refresh", "cache"]
    )
    static let stopLoading = BrowserCommand(
        "stopLoading", "Stop Loading", #selector(AppDelegate.stopLoading(_:)), [KeyBinding(".")], symbol: "xmark.circle"
    )
    /// ⌘+ is the shortcut everyone writes down and ⌘= is the one their hand
    /// performs, because + is the shifted key. Both, or the menu prints a
    /// keystroke that needs a shift the user will not press.
    static let zoomIn = BrowserCommand(
        "zoomIn", "Zoom In", #selector(AppDelegate.zoomIn(_:)), [KeyBinding("+"), KeyBinding("=")],
        symbol: "plus.magnifyingglass"
    )
    static let zoomOut = BrowserCommand(
        "zoomOut", "Zoom Out", #selector(AppDelegate.zoomOut(_:)), [KeyBinding("-")], symbol: "minus.magnifyingglass"
    )
    static let actualSize = BrowserCommand(
        "actualSize", "Zoom to Actual Size", #selector(AppDelegate.resetZoom(_:)), [KeyBinding("0")],
        symbol: "1.magnifyingglass", keywords: ["reset zoom", "actual size"]
    )
    static let showDownloads = BrowserCommand(
        "showDownloads", "Downloads", #selector(AppDelegate.showDownloads(_:)), [KeyBinding("l", [.command, .option])],
        symbol: "arrow.down.circle", keywords: ["files"]
    )

    // MARK: - History

    static let goBack = BrowserCommand("goBack", "Back", #selector(AppDelegate.goBack(_:)), [KeyBinding("[")],
        symbol: "chevron.left", keywords: ["previous page"])
    static let goForward = BrowserCommand(
        "goForward", "Forward", #selector(AppDelegate.goForward(_:)), [KeyBinding("]")], symbol: "chevron.right", keywords: ["next page"]
    )
    static let showHistory = BrowserCommand(
        "showHistory", "Show History…", #selector(AppDelegate.showHistory(_:)), [KeyBinding("y")], symbol: "clock.arrow.circlepath"
    )

    // MARK: - Window

    static let previousTab = BrowserCommand(
        "previousTab", "Show Previous Tab", #selector(AppDelegate.previousTab(_:)),
        [KeyBinding(function: NSLeftArrowFunctionKey, [.command, .option]), KeyBinding("[", [.command, .shift])],
        symbol: "arrow.backward.square"
    )
    static let nextTab = BrowserCommand(
        "nextTab", "Show Next Tab", #selector(AppDelegate.nextTab(_:)),
        [KeyBinding(function: NSRightArrowFunctionKey, [.command, .option]), KeyBinding("]", [.command, .shift])],
        symbol: "arrow.forward.square"
    )
    static let previousSpace = BrowserCommand(
        "previousSpace", "Previous Space", #selector(AppDelegate.previousSpace(_:)),
        [KeyBinding(function: NSLeftArrowFunctionKey, [.control, .option])], symbol: "square.stack.3d.up"
    )
    static let nextSpace = BrowserCommand(
        "nextSpace", "Next Space", #selector(AppDelegate.nextSpace(_:)),
        [KeyBinding(function: NSRightArrowFunctionKey, [.control, .option])], symbol: "square.stack.3d.up"
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
        newTab, newWindow, newPrivateWindow, openLocation, duplicateTab, resetPinnedTab, closeTab, closeAllTabs, cleanUpTabs,
        reopenArchivedTab, closeWindow,
        undo, redo, cut, copy, paste, selectAll, copyURL, copyMarkdown,
        toggleSidebar, toggleFavorite, reloadPage, forceReloadPage, stopLoading,
        zoomIn, zoomOut, actualSize, showDownloads,
        goBack, goForward, showHistory,
        previousTab, nextTab, previousSpace, nextSpace, minimize, searchSettings
    ]

    static func command(id: String) -> BrowserCommand? { all.first { $0.id == id } }
}

// MARK: - §9.2's shortcut rows

extension BrowserCommand {

    /// Every command the Command Bar offers, carrying the keystroke it wears
    /// right now rather than the one it shipped with.
    ///
    /// A symbol is what marks a command as belonging in the bar. The ones
    /// without are the ones a row would be wrong for: Undo, Cut and Paste
    /// belong to whatever has the keyboard, Minimize and Settings are already
    /// answered somewhere else in the list — §9.2's settings rows open the
    /// window — and Search Settings means nothing outside it. Hide Sidebar is
    /// absent for the same reason: `AppCommand.toggleSidebar` is already there,
    /// and two rows doing one thing is worse than neither.
    ///
    /// Each one is asked of the responder chain, which is the question a menu
    /// asks itself before it opens: no handler, or a handler that says no, and
    /// the row is not offered. Back with nothing behind it is not worth a row.
    ///
    /// Read when the bar opens, never per keystroke (§9.7) — a binding can be
    /// rebound and a command can stop applying while the app is running, but
    /// neither can do it between two characters.
    static var commandBarEntries: [ShortcutEntry] {
        all.compactMap { command in
            guard let symbol = command.symbolName else { return nil }
            let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
            guard let target = NSApp.target(forAction: command.action, to: nil, from: item) else { return nil }
            if let validator = target as? NSMenuItemValidation, !validator.validateMenuItem(item) { return nil }
            return ShortcutEntry(
                id: command.id,
                title: command.title,
                symbolName: symbol,
                shortcut: KeyBindings.primary(for: command)?.display ?? "",
                keywords: command.keywords
            )
        }
    }
}
