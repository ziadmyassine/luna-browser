//
//  GroupMenu.swift
//  Luna
//
//  §3.4b's folder menu: right-click a folder's header in §3.4's list, and the
//  one item the column's empty plane carries.
//
//  Its own menu rather than a longer §3.4a: half of §3.4a's items mean nothing
//  on a folder — no one address to copy, nothing to duplicate, no sound to mute,
//  and a folder is never a tile — and a menu that greyed out five of its eight
//  items would teach the user to stop opening it. A plain `NSMenu` with the
//  glyphs in `attributedTitle`, for the reasons §3.4a records.
//
//  In the column, neither Rename nor Change Icon asks in a window: a folder is
//  named on its own row, and sixteen icons are a thing to point at, so they are
//  a submenu. Only "Emoji…" ends in an ellipsis, because nothing is decided
//  until the palette it opens is picked from.
//

import AppKit
import BrowserKit

@MainActor
enum GroupMenu {

    /// What the menu can do. The list owns the verbs, as §3.4a's does.
    ///
    /// Renaming is here for the one host that cannot type on the folder: §4's
    /// bar draws a folder as a chip, and a chip is not a line of text there is
    /// room to type on. The column passes `rename` to `build` instead and the
    /// verb is never reached — the same split `TabMenu` already makes.
    struct Actions {
        var rename: (String) -> Void
        var setIcon: (String) -> Void
        /// Nil in a §5.6 private window, where §3.4b's kept tier is not
        /// offered at all — see `BrowserSession.allowsPinning`.
        var setSaved: ((Bool) -> Void)?
        var ungroup: () -> Void
        var close: () -> Void
        /// Nil for a folder with no page in it. `asMarkdown` is the ⌥ alternate.
        var copyLinks: ((_ asMarkdown: Bool) -> Void)?
        /// Always offered: building the menu must not read the clipboard to
        /// decide, which would be macOS's paste prompt. An empty one answers
        /// with a toast.
        var pasteLinks: () -> Void
        /// A Luna Control client's folder: pause, resume or stop the client.
        var agent: AgentActions?
    }

    struct AgentActions {
        var hold: ControlService.Hold?
        var pause: () -> Void
        var resume: () -> Void
        var stop: () -> Void
    }

    /// - Parameter rename: opens the name field on the folder's own row. Only
    ///   §3.4's column has one; nil asks in a dialog instead, and the item ends
    ///   in the ellipsis that says so.
    /// - Parameter emoji: opens the same field over the folder's icon, with
    ///   macOS's emoji palette over it. Nil for the same reason, and then the
    ///   palette is opened over the dialog's own field.
    static func build(
        for group: TabGroup,
        actions: Actions,
        rename: (() -> Void)? = nil,
        emoji: (() -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // First, because it is the item someone reaching for this menu while
        // an agent is at work has come for.
        if let agent = actions.agent {
            if agent.hold == nil {
                menu.addItem(SidebarMenu.glyphItem(String(localized: "Pause Agent"), symbol: "pause", action: agent.pause))
            } else {
                menu.addItem(SidebarMenu.glyphItem(String(localized: "Resume Agent"), symbol: "play", action: agent.resume))
            }
            if agent.hold != .stopped {
                menu.addItem(SidebarMenu.glyphItem(String(localized: "Stop Agent"), symbol: "stop", action: agent.stop))
            }
            menu.addItem(.separator())
        }

        if let rename {
            menu.addItem(SidebarMenu.glyphItem(String(localized: "Rename"), symbol: "pencil", action: rename))
        } else {
            menu.addItem(SidebarMenu.glyphItem(String(localized: "Rename…"), symbol: "pencil") {
                askName(for: group, then: actions.rename)
            })
        }
        menu.addItem(iconSubmenu(
            current: group.symbolName,
            actions: actions,
            emoji: emoji ?? { askEmoji(then: actions.setIcon) }
        ))
        menu.addItem(.separator())

        for item in linkItems(actions) { menu.addItem(item) }
        menu.addItem(.separator())

        // §3.4b: a folder stands on one side of the rule or the other, and its
        // tabs stand with it. Above it is pinned — the tier under §3.3's tiles,
        // which holds folders and nothing else; below it is one more thing in
        // among the day's tabs. A folder is never a tile, because §3.3's grid
        // is one tile per page.
        //
        // The separator goes with the item: two rules with nothing between them
        // is what a private window's menu would otherwise draw.
        if let setSaved = actions.setSaved {
            menu.addItem(SidebarMenu.glyphItem(
                group.isSaved ? String(localized: "Unpin Folder") : String(localized: "Pin Folder"),
                symbol: group.isSaved ? "pin.slash" : "pin",
                action: { setSaved(!group.isSaved) }
            ))
            menu.addItem(.separator())
        }

        // The first keeps every page and drops the name; the second ends the
        // pages. Both say which, because "Delete" over a folder of open tabs is
        // a word that could mean either.
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Remove Folder, Keep Tabs"),
            symbol: "rectangle.dashed",
            action: actions.ungroup
        ))
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Close Folder and Tabs"),
            symbol: "xmark",
            action: actions.close
        ))
        return menu
    }

    /// Copy Links, with its Markdown form behind ⌥, and Paste Links.
    private static func linkItems(_ actions: Actions) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let copyLinks = actions.copyLinks {
            items.append(SidebarMenu.glyphItem(String(localized: "Copy Links"), symbol: "link") { copyLinks(false) })
            let markdown = SidebarMenu.glyphItem(String(localized: "Copy Links as Markdown"), symbol: "link") {
                copyLinks(true)
            }
            markdown.isAlternate = true
            markdown.keyEquivalentModifierMask = .option
            items.append(markdown)
        }
        items.append(SidebarMenu.glyphItem(
            String(localized: "Paste Links"),
            symbol: "doc.on.clipboard",
            action: actions.pasteLinks
        ))
        return items
    }

    /// The one item the empty part of the column carries (§3.4b).
    ///
    /// A folder and nothing else. The plane already moves the window on a press
    /// and already swipes between Spaces, and a right-click on it is not a
    /// right-click on any tab — so the only thing it can offer is the one thing
    /// that needs no tab to exist.
    static func plane(newFolder: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "New Folder"),
            symbol: "folder.badge.plus",
            action: newFolder
        ))
        return menu
    }

    /// Asks for a name, for the host that cannot type on the folder itself.
    ///
    /// A blank answer is a cancel rather than a clearing: a folder is a label,
    /// and `createGroup` already refuses to make one with no text in it for the
    /// reason that a nameless row cannot be told from any other.
    private static func askName(for group: TabGroup, then commit: (String) -> Void) {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.stringValue = group.name

        let alert = NSAlert()
        alert.messageText = String(localized: "Rename this folder")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        commit(typed)
    }

    /// The same question for the picture: one character, typed or picked from
    /// macOS's own palette, which `NSApp.orderFrontCharacterPalette` opens over
    /// whatever is in front — here, the dialog's own field.
    private static func askEmoji(then commit: (String) -> Void) {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))

        let alert = NSAlert()
        alert.messageText = String(localized: "Choose an emoji for this folder")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Use Emoji"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        NSApp.orderFrontCharacterPalette(field)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RowEmoji.isEmoji(typed) else { return }
        commit(typed)
    }

    /// The sixteen, with the one the folder is wearing ticked.
    ///
    /// A submenu rather than a dialog, for the reason the file header gives, and
    /// a tick rather than a highlight because `NSMenuItem.state` is the one
    /// "this is the current one" macOS draws without being asked.
    private static func iconSubmenu(current: String, actions: Actions, emoji: @escaping () -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Change Icon"), action: nil, keyEquivalent: "")
        parent.attributedTitle = SidebarMenu.label(symbol: "photo", title: parent.title)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        // First, and with the ellipsis the sixteen below do without: it is the
        // one item here that opens something before it commits. Above them
        // rather than below because it is the open end of the list — the
        // sixteen are a vocabulary and this is every other picture there is.
        submenu.addItem(SidebarMenu.glyphItem(
            String(localized: "Emoji…"),
            symbol: "face.smiling",
            action: emoji
        ))
        // Ticked when the folder is wearing one, which is how the submenu says
        // that the sixteen below are not the only answer.
        submenu.items.first?.state = RowEmoji.isEmoji(current) ? .on : .off
        submenu.addItem(.separator())
        for symbol in symbols {
            let item = SidebarMenu.glyphItem(symbol.label, symbol: symbol.name) { actions.setIcon(symbol.name) }
            item.state = symbol.name == current ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// A curated list, for the reason §3.4a's tab icons give: a symbol name that
    /// does not resolve draws nothing at all, and a text field has no way to say
    /// which of the six thousand names it is.
    ///
    /// Its own list again. A folder names a body of work — a project, a trip,
    /// a shopping list — where a tab names a page and a Space names a mode, so
    /// the three vocabularies only touch at the edges. `folder` leads it because
    /// it is what a folder starts as.
    static let symbols: [(label: String, name: String)] = [
        (String(localized: "Folder"), "folder"),
        (String(localized: "Tray"), "tray.full"),
        (String(localized: "Box"), "shippingbox"),
        (String(localized: "Briefcase"), "briefcase"),
        (String(localized: "Books"), "books.vertical"),
        (String(localized: "Graduation Cap"), "graduationcap"),
        (String(localized: "Flask"), "flask"),
        (String(localized: "Hammer"), "hammer"),
        (String(localized: "Paintbrush"), "paintbrush"),
        (String(localized: "Airplane"), "airplane"),
        (String(localized: "House"), "house"),
        (String(localized: "Cart"), "cart"),
        (String(localized: "Gift"), "gift"),
        (String(localized: "Sparkles"), "sparkles"),
        (String(localized: "Tag"), "tag"),
        (String(localized: "Star"), "star")
    ]
}
