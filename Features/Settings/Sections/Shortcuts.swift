//
//  Shortcuts.swift
//  Luna
//
//  §23.1 §3.6: every `MainMenu` command and its key equivalent, grouped by
//  menu, searchable, read-only.
//
//  **Read from the live menu bar, not from a second copy of the key map.**
//  §22.5 declares the map once, in `MainMenu.swift`, and that file belongs to
//  agent A — so this section walks `NSApplication.mainMenu` instead of
//  restating it. That is not only ownership: a hand-maintained table would be
//  wrong the first time somebody adds a menu item, and a shortcuts list that
//  lies is worse than no shortcuts list. Nothing here mutates a menu.
//
//  **Rebinding is disabled**, with §3.6's reason. Making the map editable means
//  moving it out of `MainMenu` and into storage that survives a relaunch, which
//  is a separate piece of work and not one to imply with a live-looking button.
//

import AppKit

@MainActor
final class ShortcutsSection: SettingsSection {

    static let id = "shortcuts"
    static let title = "Shortcuts"
    static let symbolName = "command"

    /// One row of §3.6's table.
    struct Command: Sendable, Hashable {
        /// The menu it lives under — "File", "View".
        var menu: String
        var title: String
        /// Rendered as the user sees it: "⇧⌘T". Empty when the command has no
        /// key equivalent, which is most of them.
        var key: String
    }

    // MARK: Reading the menu bar

    /// Every leaf command under `menu`, in menu order, tagged with the top-level
    /// menu it came from.
    ///
    /// Separators and the menu-bar items themselves are skipped; a submenu's
    /// contents are flattened under the *top-level* title, because "File ▸
    /// Recent" is still a File shortcut to anyone reading this list.
    static func commands(in menu: NSMenu) -> [Command] {
        menu.items.flatMap { top -> [Command] in
            guard let submenu = top.submenu else { return [] }
            return leaves(of: submenu, under: top.title)
        }
    }

    private static func leaves(of menu: NSMenu, under title: String) -> [Command] {
        menu.items.flatMap { item -> [Command] in
            if let submenu = item.submenu { return leaves(of: submenu, under: title) }
            guard !item.isSeparatorItem, !item.title.isEmpty else { return [] }
            return [Command(menu: title, title: item.title, key: keyEquivalent(of: item))]
        }
    }

    /// AppKit's own display order for modifiers: ⌃ ⌥ ⇧ ⌘.
    ///
    /// An **uppercase** `keyEquivalent` implies Shift without it appearing in
    /// `keyEquivalentModifierMask` — that is the convention `MainMenu` uses for
    /// `⇧⌘T`, and reading the mask alone would print it as "⌘T", which is a
    /// different, already-taken shortcut.
    static func keyEquivalent(of item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard let first = key.unicodeScalars.first else { return "" }
        let flags = item.keyEquivalentModifierMask
        let shifted = flags.contains(.shift) || (key.count == 1 && Character(first).isUppercase)
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if shifted { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + displayKey(key)
    }

    /// The private-use scalars `NSLeftArrowFunctionKey` and friends, plus the
    /// whitespace keys that have no glyph of their own.
    private static let named: [UInt32: String] = [
        UInt32(NSLeftArrowFunctionKey): "←", UInt32(NSRightArrowFunctionKey): "→",
        UInt32(NSUpArrowFunctionKey): "↑", UInt32(NSDownArrowFunctionKey): "↓",
        UInt32(NSHomeFunctionKey): "↖", UInt32(NSEndFunctionKey): "↘",
        UInt32(NSPageUpFunctionKey): "⇞", UInt32(NSPageDownFunctionKey): "⇟",
        0x7F: "⌫", 0x0D: "↩", 0x09: "⇥", 0x1B: "⎋", 0x20: "Space"
    ]

    private static func displayKey(_ key: String) -> String {
        guard key.count == 1, let scalar = key.unicodeScalars.first else { return key.uppercased() }
        return named[scalar.value] ?? key.uppercased()
    }

    // MARK: Section

    private let body = SettingsBody()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        body.card(nil, [(rebindingRow(), ["customise shortcuts", "customize shortcuts", "rebind", "change shortcut"])])
        // `NSApplication.mainMenu` is nil in a unit-test host that never
        // installed one; an empty table is the right outcome, not a crash.
        let commands = NSApplication.shared.mainMenu.map(Self.commands(in:)) ?? []
        for menu in commands.map(\.menu).uniqued() {
            let rows = commands.filter { $0.menu == menu }.map { command in
                (view: Self.row(command), terms: [command.title, menu, command.key])
            }
            body.card(menu, rows)
        }
    }

    private static func row(_ command: Command) -> NSView {
        SettingsRow.accessory(command.title, subtitle: nil, accessory: keyLabel(command.key))
    }

    /// A label, not a control: §3.6's table is read-only, so there is nothing
    /// here for `SettingsRow` to build and nothing for the user to operate.
    ///
    /// A command with **no** key equivalent gets a dash rather than an empty
    /// chip: a plate with nothing on it reads as a shortcut that failed to
    /// load, and most of this table is commands that simply have none.
    private static func keyLabel(_ key: String) -> NSView {
        guard !key.isEmpty else {
            let dash = NSTextField(labelWithString: "—")
            dash.font = Tokens.TypeScale.sidebarRow
            dash.textColor = Tokens.Text.tertiary
            dash.setAccessibilityLabel(String(localized: "No shortcut"))
            return dash
        }
        return SettingsKeyChip(key: key)
    }

    private func rebindingRow() -> NSView {
        SettingsRow.button(
            "Customise shortcuts",
            action: "Edit…",
            isEnabled: false,
            disabledReason: "Custom shortcuts are not implemented yet."
        ) {}
    }
}

private extension Array where Element: Hashable {
    /// First-occurrence order, which for a menu bar is the order the menus are
    /// in. `Set` would lose exactly the thing being grouped by.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
