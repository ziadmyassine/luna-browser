//
//  TabMenu.swift
//  Luna
//
//  §3.4a's tab menu: right-click a row in §3.4's list.
//
//  In the reference's own order and its groups: pin, §3.4b's save and group,
//  duplicate, copy link, the three that change what the row is, then close. The
//  reference (`inspiration/tab-context-menu.png`) has seventeen items; the ones
//  still missing are declined rather than deferred — Split, Chat, Move to
//  Profile, Move to Window and both Bookmarks rows are features Luna either does
//  not have or reaches another way, and a menu listing what an app cannot do
//  teaches the user to stop reading it. The groups stay even where they hold one
//  item, because the grouping is what makes the list scannable.
//
//  The two §3.4b items are not on a §3.3 tile. A tile is already kept, by a tier
//  that keeps it harder than the saved one does, and a group may not be pinned at
//  all — so on a tile both would be offers to demote it.
//
//  A plain `NSMenu`, for the reason `SiteMenu.swift` gives: on macOS 26 that is
//  the liquid-glass menu, drawn by AppKit with its own material, blur, keyboard
//  and VoiceOver handling.
//
//  The glyphs are in the titles, because `NSMenuItem.image` draws nothing here —
//  measured with a five-way probe in a bare AppKit app, and not one appeared. An
//  `NSTextAttachment` in `attributedTitle` does, and keeps the native highlight,
//  the arrow keys and the key-equivalent column.
//  `SidebarMenu.label(symbol:title:in:)` is the mechanism; a tab stop is what
//  lines the words up in a column.
//
//  The menu is built per press and holds no row index. `NSTableView` recycles
//  row views and moves them between rows, so an index captured when the menu was
//  built is stale the moment a tab is inserted above it — the bug that once made
//  pressing close on one tab mute the tab underneath. Every item closes over a
//  `UUID`, the only identifier that cannot drift.
//

import AppKit
import BrowserKit

@MainActor
enum TabMenu {

    /// What the menu can do. The list owns the verbs — it is the one thing that knows both
    /// the tab and the session — and this file owns only the wording and the order.
    struct Actions {
        var pin: () -> Void
        var unpin: () -> Void
        /// §3.4b: across the rule, or back under it.
        var setSaved: (Bool) -> Void
        /// §3.4b: into that folder, or — with nil — out of whatever folder it is in.
        var setGroup: (UUID?) -> Void
        /// §3.4b: a new folder around this tab. It takes no name, because the
        /// name is typed on the folder's own row the moment it appears.
        var newGroup: () -> Void
        var duplicate: () -> Void
        /// Nil means "give the name back to the page".
        var rename: (String?) -> Void
        /// Nil means "give the icon back to the site".
        var setIcon: (String?) -> Void
        var setMuted: (Bool) -> Void
        var close: () -> Void
    }

    /// - Parameter group: the §3.4b folder this tab is already in, if any.
    /// - Parameter others: every other folder in the list, for the submenu that moves it.
    static func build(
        for tab: Tab,
        isMuted: Bool,
        group: TabGroup? = nil,
        others: [TabGroup] = [],
        actions: Actions
    ) -> NSMenu {
        let menu = NSMenu()
        // Closure items are their own target, so AppKit would enable them anyway. Off for
        // the same reason `SiteMenu` turns it off: nothing here may be enabled by accident.
        menu.autoenablesItems = false
        let pinned = tab.kind == .essential

        // §3.3: a tile leaves the grid the same way it entered it. The spec has promised
        // this item since the grid was built and the menu never had it.
        menu.addItem(item(
            pinned ? String(localized: "Unpin") : String(localized: "Pin"),
            symbol: pinned ? "pin.slash" : "pin",
            action: pinned ? actions.unpin : actions.pin
        ))
        // §3.4b, and not on a tile: a tile is already kept, by a tier that keeps it
        // harder. Offering to save one would be offering to demote it.
        if !pinned {
            let saved = tab.kind == .pinned
            menu.addItem(item(
                saved ? String(localized: "Remove from Saved") : String(localized: "Save Tab"),
                symbol: saved ? "tray.and.arrow.up" : "tray.and.arrow.down",
                action: { actions.setSaved(!saved) }
            ))
            menu.addItem(.separator())
            menu.addItem(groupSubmenu(current: group, others: others, actions: actions))
        }
        menu.addItem(.separator())

        menu.addItem(item(
            String(localized: "Duplicate"),
            symbol: "plus.square.on.square",
            action: actions.duplicate
        ))
        menu.addItem(.separator())

        menu.addItem(copyLink(tab.url))
        menu.addItem(.separator())

        // Ellipses, because both of these ask a question first. macOS reserves the
        // trailing `…` for a command that opens something before it commits, and these two
        // are the only items here that do.
        menu.addItem(item(String(localized: "Rename…"), symbol: "pencil") {
            askName(for: tab, then: actions.rename)
        })
        menu.addItem(item(String(localized: "Change Icon…"), symbol: "photo") {
            askIcon(for: tab, then: actions.setIcon)
        })
        menu.addItem(item(
            isMuted ? String(localized: "Unmute Site") : String(localized: "Mute Site"),
            symbol: isMuted ? "speaker.wave.2" : "speaker.slash",
            action: { actions.setMuted(!isMuted) }
        ))
        menu.addItem(.separator())

        let close = item(String(localized: "Close"), symbol: "xmark", action: actions.close)
        // The shortcut the same command already has in the app menu (§20.1), shown rather
        // than installed: a context menu's key equivalents are live only while it is open,
        // and `⌘W` is handled by the responder chain the rest of the time.
        close.keyEquivalent = "w"
        close.keyEquivalentModifierMask = .command
        menu.addItem(close)
        return menu
    }

    // MARK: - Items

    /// §3.4b's folder submenu: the one that makes a new folder, then the ones that
    /// already exist, then the way out of the one this tab is in.
    ///
    /// A submenu rather than a run of items in the main menu, because the number of
    /// entries is the user's rather than the design's — a menu that grows by one every
    /// time somebody makes a folder stops being scannable at about the fourth.
    ///
    /// It reads Add for a loose tab and Move for one that is already in a folder,
    /// because those are different acts and the item says which.
    ///
    /// New Folder carries no ellipsis and asks nothing. The folder appears with the
    /// tab already in it and its name field open on its own row, which is one fewer
    /// window than a dialog and puts the answer where the thing being named is.
    private static func groupSubmenu(current: TabGroup?, others: [TabGroup], actions: Actions) -> NSMenuItem {
        let parent = NSMenuItem(
            title: current == nil ? String(localized: "Add to Folder") : String(localized: "Move to Folder"),
            action: nil,
            keyEquivalent: ""
        )
        parent.attributedTitle = SidebarMenu.label(symbol: "folder", title: parent.title)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(item(
            String(localized: "New Folder"),
            symbol: "folder.badge.plus",
            action: actions.newGroup
        ))
        if !others.isEmpty {
            submenu.addItem(.separator())
            for group in others {
                submenu.addItem(item(group.name, symbol: group.symbolName) { actions.setGroup(group.id) })
            }
        }
        if current != nil {
            submenu.addItem(.separator())
            submenu.addItem(item(String(localized: "Remove from Folder"), symbol: "folder.badge.minus") {
                actions.setGroup(nil)
            })
        }
        parent.submenu = submenu
        return parent
    }

    /// One item, with the reference's glyph beside its word.
    ///
    /// The glyph rides in `attributedTitle` rather than in `image`, which is not drawn at
    /// all on this macOS — `SidebarMenu.label(symbol:title:in:)` has the measurement. The
    /// plain `title` is set as well and stays underneath: it is what VoiceOver reads and
    /// what `typeSelect` matches, and neither should have to step over an attachment.
    private static func item(_ title: String, symbol name: String, action: @escaping () -> Void) -> NSMenuItem {
        SidebarMenu.glyphItem(title, symbol: name, action: action)
    }

    /// The reference's "Copy Link as Markdown" without the Markdown: this is the plain
    /// address, which is what the user asked for and what §3.2's site menu already puts on
    /// the pasteboard. The two are deliberately the same call — copying a link from the row
    /// and copying it from the pill must not produce different pasteboards.
    private static func copyLink(_ url: URL) -> NSMenuItem {
        item(String(localized: "Copy Link"), symbol: "link") {
            NSPasteboard.general.clearContents()
            // As a string as well as a URL: a plain text field pasted into gets the
            // address rather than nothing at all.
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    // MARK: - The two questions

    /// Asks for a name and hands it over — nil for "give it back to the page".
    ///
    /// The answer goes to a closure rather than coming back as a return value, because
    /// there are three outcomes and only two of them are a name: a typed name, a cleared
    /// name, and a cancel. Returning `String?` would collapse the last two into each other
    /// and a cancelled dialog would silently rename the tab to nothing.
    private static func askName(for tab: Tab, then commit: (String?) -> Void) {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.stringValue = tab.customTitle ?? ""
        // The page's own title as the placeholder, so the field shows what clearing it
        // gets you back rather than making the user remember.
        field.placeholderString = tab.title.isEmpty ? URLPillView.domain(of: tab.url) : tab.title

        let alert = NSAlert()
        alert.messageText = String(localized: "Rename this tab")
        alert.informativeText = String(localized: """
        The name stays whatever you type, wherever the page goes. Leave it empty to go back \
        to the page's own title.
        """)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        commit(typed.isEmpty ? nil : typed)
    }

    /// Asks for an icon and hands it over — nil for "give it back to the site". Same three
    /// outcomes, same reason it is a closure.
    private static func askIcon(for tab: Tab, then commit: (String?) -> Void) {
        let picker = NSPopUpButton(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size), pullsDown: false)
        picker.addItem(withTitle: String(localized: "The site's own icon"))
        for symbol in symbols { picker.addItem(withTitle: symbol.label) }
        // `+ 1` for the entry above, which is the one every tab starts on.
        let current = symbols.firstIndex { $0.name == tab.customSymbolName }
        picker.selectItem(at: current.map { $0 + 1 } ?? 0)

        let alert = NSAlert()
        alert.messageText = String(localized: "Choose an icon for this tab")
        alert.informativeText = String(localized: """
        The icon replaces the site's favicon in the sidebar. It stays with the tab wherever \
        the page goes.
        """)
        alert.accessoryView = picker
        alert.addButton(withTitle: String(localized: "Change"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // `- 1` for the entry above the list, which is the one that means "no icon of your
        // own" — so an index that falls outside the curated list is that answer.
        let choice = picker.indexOfSelectedItem - 1
        commit(symbols.indices.contains(choice) ? symbols[choice].name : nil)
    }

    /// A curated list rather than free text, for the reason §3.7's Space icon row gives:
    /// a symbol name that does not resolve draws nothing at all, and a text field has no
    /// way to tell the user which of the six thousand names it is.
    ///
    /// Its own list, not `SpacesSection.symbols`. A Space icon names a mode — Work,
    /// Study, Home — and a tab icon names a page, so the two vocabularies barely
    /// overlap. Sharing one list would mean choosing a Space icon from a set with "Video"
    /// in it and a tab icon from a set without.
    static let symbols: [(label: String, name: String)] = [
        (String(localized: "Star"), "star"),
        (String(localized: "Heart"), "heart"),
        (String(localized: "Flag"), "flag"),
        (String(localized: "Bookmark"), "bookmark"),
        (String(localized: "Document"), "doc.text"),
        (String(localized: "Mail"), "envelope"),
        (String(localized: "Chat"), "bubble.left"),
        (String(localized: "Calendar"), "calendar"),
        (String(localized: "Code"), "chevron.left.forwardslash.chevron.right"),
        (String(localized: "Terminal"), "terminal"),
        (String(localized: "Music"), "music.note"),
        (String(localized: "Video"), "play.rectangle"),
        (String(localized: "Photo"), "photo"),
        (String(localized: "Cart"), "cart"),
        (String(localized: "Bank"), "banknote"),
        (String(localized: "Bell"), "bell"),
        (String(localized: "Lock"), "lock"),
        (String(localized: "Pin"), "pin")
    ]

}
