//
//  Shortcuts.swift
//  Luna
//
//  §23.1 §3.6: every `MainMenu` command and its key equivalent, grouped by
//  menu, searchable — and, for the ones that are Luna's to move, editable.
//
//  Read from the live menu bar, not from a second copy of the key map. The
//  rows, their titles and the menus they are grouped under come from walking
//  `NSApplication.mainMenu`. A hand-maintained list would be wrong the first
//  time somebody added a menu item, and a shortcuts list that lies is worse
//  than none.
//
//  Items are joined to their `BrowserCommand` by selector, which is the one
//  thing a menu item and a command table are guaranteed to agree about. A
//  customisable match gets a recorder; anything else keeps its label. So the
//  numbered families — nine Spaces, nine sidebar rows, built per session — are
//  listed and are not editable, which is the truth about them.
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
        /// The table entry this item matched, if that entry is Luna's to
        /// move. Nil is what makes a row read-only, so there is one answer to
        /// "can I change this?" rather than a match and a separate flag.
        var editableID: String?
        /// Why it cannot be moved, short enough to sit under the title as a
        /// tag. Nil when it can be, and nil for the ordinary case — the flat
        /// printing already says a row is fixed, and only the two families that
        /// would be mistaken for macOS's need a sentence on top of it.
        var fixedReason: String?
    }

    // MARK: Reading the menu bar

    /// Every leaf command under `menu`, in menu order, tagged with the top-level
    /// menu it came from.
    ///
    /// Separators and the menu-bar items themselves are skipped; a submenu's
    /// contents are flattened under the top-level title, because "File ▸
    /// Recent" is still a File shortcut to anyone reading this list.
    ///
    /// Hidden items are skipped too, which they did not used to be. They
    /// carry real shortcuts — a command's alternate bindings are hidden items,
    /// and so are the sidebar rows a Space has not grown into yet — but every
    /// one of them duplicates a row that is already visible, so listing them
    /// prints the same command twice with two different keystrokes beside it.
    static func commands(in menu: NSMenu) -> [Command] {
        menu.items.flatMap { top -> [Command] in
            guard let submenu = top.submenu else { return [] }
            return leaves(of: submenu, under: top.title)
        }
    }

    private static func leaves(of menu: NSMenu, under title: String) -> [Command] {
        menu.items.flatMap { item -> [Command] in
            if let submenu = item.submenu { return leaves(of: submenu, under: title) }
            guard !item.isSeparatorItem, !item.isHidden, !item.title.isEmpty else { return [] }
            let editable = command(for: item).flatMap { $0.isCustomisable ? $0 : nil }
            return [Command(
                menu: title,
                title: item.title,
                key: keyEquivalent(of: item),
                editableID: editable?.id,
                fixedReason: editable == nil ? reason(for: item) : nil
            )]
        }
    }

    /// Why a shortcut is not the user's to move — only where the drawing
    /// would otherwise mislead.
    ///
    /// Everything else says it by being printed flat, and a caption repeated
    /// down forty rows of the app, Edit and Window menus is noise that stops
    /// being read by the third one. The numbered families are the exception,
    /// and they earn it: `⌘1…⌘9` and `⌃1…⌃9` are Luna's own, so a user who
    /// assumes they are the platform's goes looking for a setting that cannot
    /// exist. They are built per session from the sidebar rows and Spaces that
    /// exist right now, which is why there is no one thing to rebind.
    private static func reason(for item: NSMenuItem) -> String? {
        switch item.action {
        case #selector(AppDelegate.goToSidebarItem(_:)):
            return String(localized: "Numbered from your sidebar")
        case #selector(AppDelegate.switchToSpace(_:)):
            return String(localized: "Numbered from your Spaces")
        default:
            return nil
        }
    }

    /// The table entry a menu item is an instance of. Matched on selector: the
    /// title is the user's to change through a rename and the key equivalent is
    /// the user's to change outright, so neither can be the join.
    private static func command(for item: NSMenuItem) -> BrowserCommand? {
        guard let action = item.action else { return nil }
        return BrowserCommand.all.first { $0.action == action }
    }

    /// AppKit's own display order for modifiers: ⌃ ⌥ ⇧ ⌘.
    ///
    /// An uppercase `keyEquivalent` implies Shift without it appearing in
    /// `keyEquivalentModifierMask`. `BrowserCommand` never spells a shortcut
    /// that way — `KeyBinding` normalises shift into the mask — but AppKit's own
    /// items and anything built by hand still can, and reading the mask alone
    /// would print such an item as "⌘T", which is a different, already-taken
    /// shortcut.
    static func keyEquivalent(of item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard let first = key.unicodeScalars.first else { return "" }
        var modifiers = item.keyEquivalentModifierMask
        if key.count == 1, Character(first).isUppercase { modifiers.insert(.shift) }
        return KeyBinding(key, modifiers).display
    }

    // MARK: Section

    private let body = SettingsBody()
    /// Every recorder on screen, by command id — so Reset All can re-print them
    /// all without rebuilding the pane.
    private var recorders: [String: SettingsShortcutRecorder] = [:]
    private var resetButtons: [String: NSButton] = [:]

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        body.card(nil, [(resetAllRow(), ["reset shortcuts", "restore defaults", "customise", "customize"])])
        // Above the table, not below it. It is the key to the drawing, and
        // a legend a reader only meets after scrolling past sixty rows they
        // could not interpret has been printed too late to have been a legend.
        body.loose(SettingsRow.note(String(localized: """
        Shortcuts in a box are yours to change: click one and press the new keys. \
        Escape cancels, Delete clears it, and a shortcut needs ⌘, ⌃ or ⌥ — without one it would be \
        typed into the page instead. The rest are printed flat: they belong to macOS, or are numbered \
        from your Spaces and sidebar, and cannot be moved.
        """)), terms: ["help", "how to change a shortcut", "editable", "cannot be changed", "locked"])
        // `NSApplication.mainMenu` is nil in a unit-test host that never
        // installed one; an empty table is the right outcome, not a crash.
        let commands = NSApplication.shared.mainMenu.map(Self.commands(in:)) ?? []
        for menu in commands.map(\.menu).uniqued() {
            let rows = commands.filter { $0.menu == menu }.map { command in
                (view: row(command), terms: Self.terms(command))
            }
            body.card(menu, rows)
        }
    }

    /// §2's search matches a row on what it says and on what it is, so
    /// "editable" lists everything that can be rebound and nothing else.
    private static func terms(_ command: Command) -> [String] {
        [command.title, command.menu, command.key]
            + (command.fixedReason.map { [$0] } ?? [])
            + [command.editableID == nil
                ? String(localized: "cannot be changed")
                : String(localized: "editable")]
    }

    // MARK: Rows

    private func row(_ command: Command) -> NSView {
        guard let id = command.editableID, let entry = BrowserCommand.command(id: id) else {
            return SettingsRow.accessory(
                command.title,
                subtitle: command.fixedReason,
                accessory: Self.keyLabel(command.key)
            )
        }
        return SettingsRow.accessory(command.title, subtitle: nil, accessory: editor(for: entry))
    }

    /// The recorder, and the Reset that only exists once there is something to
    /// reset to.
    private func editor(for command: BrowserCommand) -> NSView {
        let recorder = SettingsShortcutRecorder(binding: KeyBindings.primary(for: command))
        recorder.onRecord = { [weak self] binding in self?.record(binding, for: command) }
        recorders[command.id] = recorder

        let reset = Self.resetButton()
        reset.target = self
        reset.action = #selector(resetOne(_:))
        reset.identifier = NSUserInterfaceItemIdentifier(command.id)
        reset.isHidden = !KeyBindings.isCustomised(command)
        resetButtons[command.id] = reset

        let stack = NSStackView(views: [reset, recorder])
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.rowGap
        stack.alignment = .centerY
        return stack
    }

    /// Borderless and unlabelled: it is one glyph beside the chip it undoes, and
    /// a bezelled button there would be the loudest thing in the pane.
    private static func resetButton() -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "arrow.counterclockwise",
            accessibilityDescription: String(localized: "Reset to the default shortcut")
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = Tokens.Text.tertiary
        button.setAccessibilityLabel(String(localized: "Reset to the default shortcut"))
        return button
    }

    // MARK: Editing

    /// Commits a recorded keystroke, or refuses it and says who has it.
    ///
    /// Refuses rather than steals. Taking a shortcut off whichever command
    /// held it would leave that command silently unbound, discoverable only by
    /// pressing it and watching nothing happen — and the user cannot see the
    /// other row from here to know what they just cost themselves.
    private func record(_ binding: KeyBinding?, for command: BrowserCommand) {
        if let binding, let clash = KeyBindings.conflict(for: binding, ignoring: command) {
            recorders[command.id]?.show(KeyBindings.primary(for: command))
            let alert = NSAlert()
            alert.messageText = String(localized: "\(binding.display) is already taken.")
            alert.informativeText = String(localized: """
            \(clash.explanation) Change that one first, or pick a different keystroke for \(command.title).
            """)
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }
        KeyBindings.set(binding, for: command)
        refresh(command)
    }

    @objc private func resetOne(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let command = BrowserCommand.command(id: id) else { return }
        KeyBindings.reset(command)
        refresh(command)
    }

    private func refresh(_ command: BrowserCommand) {
        recorders[command.id]?.show(KeyBindings.primary(for: command))
        resetButtons[command.id]?.isHidden = !KeyBindings.isCustomised(command)
    }

    private func resetAllRow() -> NSView {
        SettingsRow.button(
            "Shortcuts you have changed",
            action: "Reset All",
            isDestructive: true
        ) { [weak self] in
            self?.confirmResetAll()
        }
    }

    /// Asks first: it throws away every override in one go, and the only record
    /// of what they were is the table the user is looking at.
    private func confirmResetAll() {
        guard KeyBindings.hasAnyCustomisation else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Nothing to reset.")
            alert.informativeText = String(localized: "Every shortcut is the one Luna ships with.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset every shortcut?")
        alert.informativeText = String(localized: "Each one goes back to the keystroke Luna ships with.")
        alert.addButton(withTitle: String(localized: "Reset All"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        KeyBindings.resetAll()
        for command in BrowserCommand.all { refresh(command) }
    }

    /// A label, not a control: a command macOS owns, or one built from live data
    /// rather than from the table, is read-only — so there is nothing here for
    /// the user to operate, and `isFixed` takes the box away to say so.
    ///
    /// A command with no key equivalent gets a dash rather than an empty
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
        return SettingsKeyChip(key: key, isFixed: true)
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
