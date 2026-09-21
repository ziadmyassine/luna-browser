//
//  GroupMenu.swift
//  Luna
//
//  §3.4b's group menu: right-click a group header in §3.4's list.
//
//  Its own menu rather than a longer §3.4a. A group and a tab are different
//  nouns — one is a page, the other is a name around several — and half of
//  §3.4a's items have no meaning on a group at all: there is no address to copy,
//  nothing to duplicate, no sound to mute, and pinning is the one thing §3.4b
//  says a group may never be. A menu that greyed out five of its eight items
//  would teach the user not to open it.
//
//  Five items in three groups: the two that change what the group *is*, the one
//  that moves it across the rule, and the two that end it. A plain `NSMenu`, and
//  the glyphs ride in `attributedTitle`, for the reasons §3.4a records.
//
//  This file also owns the one dialog that makes a group, because it is the same
//  question asked from two places — the group menu's *Rename…* and §3.4a's
//  *New Group…* — and a second copy of it would be a second set of defaults.
//

import AppKit
import BrowserKit

@MainActor
enum GroupMenu {

    /// What the menu can do. The list owns the verbs, as §3.4a's does.
    struct Actions {
        var rename: (String) -> Void
        var setIcon: (String) -> Void
        var setSaved: (Bool) -> Void
        var ungroup: () -> Void
        var close: () -> Void
    }

    static func build(for group: TabGroup, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(SidebarMenu.glyphItem(String(localized: "Rename…"), symbol: "pencil") {
            ask(
                title: String(localized: "Rename this group"),
                confirm: String(localized: "Rename"),
                name: group.name,
                symbolName: group.symbolName
            ) { name, symbol in
                actions.rename(name)
                actions.setIcon(symbol)
            }
        })
        menu.addItem(.separator())

        // §3.4b: a group stands on one side of the rule or the other, and its
        // tabs stand with it. There is no third answer — a group cannot be
        // pinned, because §3.3's grid is one tile per tab.
        menu.addItem(SidebarMenu.glyphItem(
            group.isSaved ? String(localized: "Remove from Saved") : String(localized: "Save Group"),
            symbol: group.isSaved ? "tray.and.arrow.up" : "tray.and.arrow.down",
            action: { actions.setSaved(!group.isSaved) }
        ))
        menu.addItem(.separator())

        // Ungroup keeps every page and drops the name; Close is the one that
        // ends the pages, and it says so rather than hiding behind "Delete".
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Ungroup"),
            symbol: "rectangle.dashed",
            action: actions.ungroup
        ))
        menu.addItem(SidebarMenu.glyphItem(
            String(localized: "Close Group"),
            symbol: "xmark",
            action: actions.close
        ))
        return menu
    }

    // MARK: - The question a group is made with

    /// Asks for a name and an icon together, and hands both over.
    ///
    /// One dialog rather than two, unlike §3.4a's *Rename…* and *Change Icon…*,
    /// and the difference is real: a tab arrives already named by its page and
    /// already wearing a favicon, so each of those two is a correction. A group
    /// arrives as nothing at all, and asking for its two halves in sequence
    /// would put a second sheet in front of the user for one action.
    ///
    /// Nothing is handed over on cancel and nothing is handed over for a blank
    /// name: a group is a label, and a label with no text is a row the user
    /// cannot tell from any other.
    static func ask(
        title: String,
        confirm: String,
        name: String = "",
        symbolName: String = TabGroup.defaultSymbolName,
        then commit: (String, String) -> Void
    ) {
        let field = NSTextField(frame: .zero)
        field.stringValue = name
        field.placeholderString = String(localized: "Group name")

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for symbol in symbols { picker.addItem(withTitle: symbol.label) }
        picker.selectItem(at: symbols.firstIndex { $0.name == symbolName } ?? 0)

        // Laid out with arithmetic rather than constraints, like the rest of
        // Luna's chrome. An `NSAlert` sizes its accessory from this frame.
        let width = Tokens.Metric.urlPill.width
        let row = Tokens.Metric.urlPill.height
        let gap = Tokens.Metric.rowInset
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 2 * row + gap))
        picker.frame = NSRect(x: 0, y: 0, width: width, height: row)
        field.frame = NSRect(x: 0, y: row + gap, width: width, height: row)
        accessory.addSubview(field)
        accessory.addSubview(picker)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(localized: """
        A group keeps tabs together under one name. Drag it above the line to save it — then \
        closing a tab inside it leaves the tab where it is instead of throwing it away.
        """)
        alert.accessoryView = accessory
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let choice = picker.indexOfSelectedItem
        commit(typed, symbols.indices.contains(choice) ? symbols[choice].name : TabGroup.defaultSymbolName)
    }

    /// A curated list, for the reason §3.4a's tab icons give: a symbol name that
    /// does not resolve draws nothing at all, and a text field has no way to say
    /// which of the six thousand names it is.
    ///
    /// Its own list again. A group names a *body of work* — a project, a trip,
    /// a shopping list — where a tab names a page and a Space names a mode, so
    /// the three vocabularies only touch at the edges. `folder` leads it because
    /// it is what a group starts as.
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
