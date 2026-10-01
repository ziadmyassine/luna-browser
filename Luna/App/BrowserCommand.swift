//
//  BrowserCommand.swift
//  Luna
//
//  §20.1's key map, as a table rather than as literals scattered through
//  `MainMenu`, which still owns the structure. A shortcut the user can change
//  (§3.6) needs a stable identity to store an override against, a default to
//  reset back to, and a list every other command can be checked against.
//
//  `defaults` is a list and only the first is printed; the extras are hidden
//  menu items, and a hidden item still fires its key equivalent. A user
//  override replaces the whole list: keeping ours alive underneath means ⇧⌘]
//  still shows the next tab after the user moved it to ⌃⇥, with nothing in the
//  UI saying so.
//
//  `isCustomisable: false` marks a shortcut macOS owns (⌘Q, ⌘X, ⌘M). They stay
//  in the table because the conflict check has to know they are taken.
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
    /// A file on this Mac, in a tab — any of `LocalFileTypes`.
    static let openFile = BrowserCommand(
        "openFile", "Open File…", #selector(AppDelegate.openFile(_:)), [KeyBinding("o")],
        symbol: "doc", keywords: ["file", "html", "pdf", "local"]
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

    /// §18.1. The Mac's own Find keys, so fixed like Cut and Copy. ⌘F is the
    /// Settings window's search as well — see `BrowserCommands+Find.swift`.
    static let find = BrowserCommand(
        "find", "Find…", #selector(AppDelegate.findInPage(_:)), [KeyBinding("f")], customisable: false,
        symbol: "text.magnifyingglass", keywords: ["find in page", "find on page", "search page"]
    )
    static let findNext = BrowserCommand(
        "findNext", "Find Next", #selector(AppDelegate.findNextInPage(_:)), [KeyBinding("g")], customisable: false
    )
    static let findPrevious = BrowserCommand(
        "findPrevious", "Find Previous", #selector(AppDelegate.findPreviousInPage(_:)),
        [KeyBinding("g", [.command, .shift])], customisable: false
    )
    static let useSelectionForFind = BrowserCommand(
        "useSelectionForFind", "Use Selection for Find", #selector(AppDelegate.useSelectionForFind(_:)),
        [KeyBinding("e")], customisable: false
    )

    // MARK: - View

    static let toggleSidebar = BrowserCommand(
        "toggleSidebar", "Hide Sidebar", #selector(AppDelegate.toggleSidebarVisibility(_:)), [KeyBinding("s")]
    )
    static let toggleFavorite = BrowserCommand(
        "toggleFavorite", "Add to Favorites", #selector(AppDelegate.toggleFavorite(_:)), [KeyBinding("d")],
        // §3.4a's Pin and Unpin are this command: a pinned tab is a Favorite.
        symbol: "star", keywords: ["favourite", "bookmark", "pin tab", "unpin tab"]
    )
    static let reloadPage = BrowserCommand(
        "reloadPage", "Reload Page", #selector(AppDelegate.reloadPage(_:)), [KeyBinding("r")],
        symbol: "arrow.clockwise", keywords: ["refresh"]
    )
    static let forceReloadPage = BrowserCommand(
        "forceReloadPage", "Force Refresh the Page", #selector(AppDelegate.forceReloadPage(_:)),
        [KeyBinding("r", [.command, .option])], symbol: "arrow.clockwise.circle", keywords: ["hard refresh", "cache"]
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
    /// §17. Ships unbound: no browser has a convention for it to follow, and
    /// the chip's Open button is the way in until the user records one.
    static let openBlockedPopup = BrowserCommand(
        "openBlockedPopup", "Open Blocked Pop-up", #selector(AppDelegate.openBlockedPopup(_:))
    )
    /// ⇧⌘P, as in Search; nothing in §20.1's map had it.
    static let pictureInPicture = BrowserCommand(
        "pictureInPicture", "Picture in Picture", #selector(AppDelegate.togglePictureInPicture(_:)),
        [KeyBinding("p", [.command, .shift])],
        symbol: "pip", keywords: ["pip", "float video", "floating video"]
    )
    /// §18.4a. Every window, private ones too; no shortcut, as no browser has one.
    /// Safari's keys for both: ⇧⌘R is Reader, and forcing a refresh is ⌥⌘R.
    static let reader = BrowserCommand(
        "reader", "Reader", #selector(AppDelegate.toggleReader(_:)), [KeyBinding("r", [.command, .shift])],
        symbol: "doc.plaintext", keywords: ["reader mode", "reading mode", "article", "read"]
    )
    static let hideElements = BrowserCommand(
        "hideElements", "Hide Something…", #selector(AppDelegate.toggleHidingElements(_:)),
        [KeyBinding("h", [.command, .shift])],
        symbol: "eye.slash", keywords: ["hide element", "remove", "block element", "banner", "annoyance"]
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
    /// §11.3. No shortcut, as in Safari: it is one Return away from deleting.
    static let clearHistory = BrowserCommand(
        "clearHistory", "Clear History…", #selector(AppDelegate.clearHistory(_:)),
        symbol: "clock.badge.xmark", keywords: ["delete history", "forget history"]
    )

    // MARK: - Develop

    /// Safari's four Develop shortcuts, so a hand that knows Safari finds them.
    static let showWebInspector = BrowserCommand(
        "showWebInspector", "Show Web Inspector", #selector(AppDelegate.toggleWebInspector(_:)),
        [KeyBinding("i", [.command, .option])],
        symbol: "hammer", keywords: ["inspect element", "devtools", "developer tools", "elements"]
    )
    static let showJavaScriptConsole = BrowserCommand(
        "showJavaScriptConsole", "Show JavaScript Console", #selector(AppDelegate.showJavaScriptConsole(_:)),
        [KeyBinding("c", [.command, .option])],
        symbol: "terminal", keywords: ["console", "devtools", "log"]
    )
    static let showPageSource = BrowserCommand(
        "showPageSource", "Show Page Source", #selector(AppDelegate.showPageSource(_:)),
        [KeyBinding("u", [.command, .option])],
        symbol: "chevron.left.forwardslash.chevron.right", keywords: ["view source", "html", "sources"]
    )
    static let startElementSelection = BrowserCommand(
        "startElementSelection", "Start Element Selection", #selector(AppDelegate.startElementSelection(_:)),
        symbol: "cursorarrow.rays", keywords: ["inspect element", "pick element"]
    )
    static let disableJavaScript = BrowserCommand(
        "disableJavaScript", "Disable JavaScript", #selector(AppDelegate.toggleJavaScript(_:)),
        symbol: "curlybraces", keywords: ["javascript", "js"]
    )
    static let emptyCaches = BrowserCommand(
        "emptyCaches", "Empty Caches", #selector(AppDelegate.emptyCaches(_:)),
        [KeyBinding("e", [.command, .option])],
        symbol: "trash", keywords: ["clear cache", "cache"]
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
    /// No key of its own: ⌘F is Find…, which the Settings window answers by
    /// focusing its search. Kept in the table, and in Window ▸ Settings, so the
    /// search is reachable from the menu bar too.
    static let searchSettings = BrowserCommand(
        "searchSettings", "Search Settings", #selector(SettingsWindowController.focusSettingsSearch(_:)),
        customisable: false
    )

    // MARK: - The table

    /// Every command that can hold a shortcut, in menu order. The numbered
    /// families are absent on purpose — see `KeyBindings.reserved`.
    static let all: [BrowserCommand] = [
        settings,
        newTab, newWindow, newPrivateWindow, openLocation, openFile, duplicateTab, resetPinnedTab,
        renameTab, muteSite, moveToFolder, newFolder, closeTab, closeAllTabs, cleanUpTabs,
        reopenArchivedTab, closeWindow, downloadPDF, printPage,
        undo, redo, cut, copy, paste, selectAll, find, findNext, findPrevious, useSelectionForFind,
        copyURL, copyMarkdown,
        toggleSidebar, toggleFavorite, reloadPage, forceReloadPage, stopLoading, openBlockedPopup,
        zoomIn, zoomOut, actualSize, pictureInPicture, muteAllTabs, unmuteAllTabs, reader, siteSettings, hideElements, showDownloads,
        goBack, goForward, showHistory, clearHistory,
        showWebInspector, showJavaScriptConsole, showPageSource, startElementSelection, disableJavaScript, emptyCaches,
        previousTab, nextTab, previousSpace, nextSpace, minimize, searchSettings,
        showWelcome
    ]

    static func command(id: String) -> BrowserCommand? { all.first { $0.id == id } }
}

// MARK: - §20.2's tab commands

/// An extension so the struct's body stays inside SwiftLint's limit; the
/// table above lists these in menu order with the rest.
extension BrowserCommand {

    /// §20.2: §3.4a's tab menu, from the keyboard. Each runs the verb the menu
    /// runs, on the tab in front. Two ship with a key: ⌃M is Firefox's Mute
    /// Tab, and ⌥⌘N sits beside ⌘N and ⇧⌘N for the third thing Luna makes.
    /// The rest have no convention to follow and wait for the user's own.
    static let renameTab = BrowserCommand(
        "renameTab", "Rename Tab…", #selector(AppDelegate.renameActiveTab(_:)),
        symbol: "pencil", keywords: ["name tab", "title"]
    )
    static let muteSite = BrowserCommand(
        "muteSite", "Mute Site", #selector(AppDelegate.toggleSiteMute(_:)), [KeyBinding("m", .control)],
        symbol: "speaker.slash", keywords: ["mute tab", "unmute", "sound", "audio", "silence"]
    )
    static let moveToFolder = BrowserCommand(
        "moveToFolder", "Move to Folder…", #selector(AppDelegate.moveActiveTabToFolder(_:)),
        symbol: "folder", keywords: ["add to folder", "group", "tab group"]
    )
    static let newFolder = BrowserCommand(
        "newFolder", "New Folder", #selector(AppDelegate.newTabFolder(_:)), [KeyBinding("n", [.command, .option])],
        symbol: "folder.badge.plus", keywords: ["new group", "tab group"]
    )
    /// §3.2a's pop-out, from whichever address bar the window is showing.
    static let siteSettings = BrowserCommand(
        "siteSettings", "Site Settings…", #selector(AppDelegate.openSiteSettings(_:)),
        symbol: SiteMenu.Glyph.advanced, keywords: ["permissions", "camera", "microphone", "site", "website"]
    )

    /// §30.17's first run, again, from Help.
    static let showWelcome = BrowserCommand(
        "showWelcome", "Welcome to Luna", #selector(AppDelegate.showWelcome(_:)),
        symbol: "hand.wave", keywords: ["onboarding", "first run", "setup", "import", "theme"]
    )
}

// MARK: - §9.2's shortcut rows

extension BrowserCommand {

    /// Every command the Command Bar offers, carrying the keystroke it wears
    /// right now rather than the one it shipped with.
    ///
    /// A symbol is what marks a command as belonging in the bar. The ones
    /// without are the ones a row would be wrong for: Undo, Cut and Paste
    /// belong to whatever has the keyboard; Minimize, Settings and Hide Sidebar
    /// are already answered elsewhere in the list (§9.2's settings rows,
    /// `AppCommand.toggleSidebar`); and Search Settings means nothing outside
    /// the Settings window.
    ///
    /// Each one is asked of the responder chain, as a menu asks itself before
    /// it opens: no handler, or a handler that says no, and the row is not
    /// offered. Read when the bar opens, never per keystroke (§9.7).
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
