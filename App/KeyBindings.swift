//
//  KeyBindings.swift
//  Luna
//
//  §3.6's overrides: which keystroke each command actually wears, once the user
//  has had their say.
//
//  `UserDefaults`, one key per command (`luna.shortcut.<id>`), like every other
//  preference Luna keeps. One key per command rather than a single dictionary so
//  that a command that is renamed, retired or not yet written simply has no key —
//  a stored blob would have to be migrated, and the thing being migrated is a
//  keystroke.
//
//  **An override is a full replacement, and an empty one is a real answer.**
//  There are three states, not two: no key at all (the default stands), a stored
//  keystroke, and `none` — the user deliberately taking a shortcut away. The
//  third is why the absence of a value cannot mean "no shortcut".
//
//  Nothing here touches a menu. `MainMenu` rebuilds itself when `didChange`
//  arrives, which is the only way a binding reaches the menu bar — see
//  `MainMenu.rebuild`.
//

import AppKit

@MainActor
enum KeyBindings {

    /// Posted after any binding changes. `AppDelegate` rebuilds the menu bar on it.
    static let didChange = Notification.Name("luna.shortcuts.didChange")

    private static let prefix = "luna.shortcut."
    /// The stored value for "this command has no shortcut" — distinct from no
    /// stored value at all, which means "whatever ships".
    private static let cleared = "none"

    private static func key(_ command: BrowserCommand) -> String { prefix + command.id }

    // MARK: - Reading

    /// Every keystroke that fires `command`: the printed one first, then the
    /// alternates. An override replaces the list entirely (see
    /// `BrowserCommand`'s header).
    static func bindings(for command: BrowserCommand) -> [KeyBinding] {
        guard let stored = UserDefaults.standard.string(forKey: key(command)) else { return command.defaults }
        guard stored != cleared else { return [] }
        return KeyBinding(stored: stored).map { [$0] } ?? command.defaults
    }

    /// What the menu prints, and what §3.6's table shows.
    static func primary(for command: BrowserCommand) -> KeyBinding? { bindings(for: command).first }

    /// Whether this row has been moved off what Luna ships — the only thing the
    /// Reset affordance keys off.
    static func isCustomised(_ command: BrowserCommand) -> Bool {
        UserDefaults.standard.string(forKey: key(command)) != nil
    }

    static var hasAnyCustomisation: Bool {
        BrowserCommand.all.contains(where: isCustomised)
    }

    // MARK: - Writing

    /// Records `binding` — or, for nil, records that this command has no
    /// shortcut at all. Silent about conflicts: `conflict(for:ignoring:)` is the
    /// caller's to ask before it commits, because only the caller can say what
    /// to do about the answer.
    static func set(_ binding: KeyBinding?, for command: BrowserCommand) {
        guard command.isCustomisable else { return }
        UserDefaults.standard.set(binding?.stored ?? cleared, forKey: key(command))
        announce()
    }

    /// Back to what Luna ships, alternates and all.
    static func reset(_ command: BrowserCommand) {
        UserDefaults.standard.removeObject(forKey: key(command))
        announce()
    }

    static func resetAll() {
        for command in BrowserCommand.all {
            UserDefaults.standard.removeObject(forKey: key(command))
        }
        announce()
    }

    private static func announce() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Conflicts

    /// What already answers to a keystroke.
    enum Conflict {
        /// Another command in the table — the common case.
        case command(BrowserCommand)
        /// One of the numbered families, which are built per Space and per tab
        /// and so are not in the table. The string is what to tell the user.
        case reserved(String)

        var explanation: String {
            switch self {
            case let .command(other):
                String(localized: "\(other.title) already uses that shortcut.")
            case let .reserved(what):
                String(localized: "\(what) already uses that shortcut.")
            }
        }
    }

    /// Who owns `binding` today, or nil if it is free. `ignoring` is the command
    /// being edited — a shortcut is never in conflict with itself.
    ///
    /// **Alternates count.** ⇧⌘] is not printed anywhere, because it is Show
    /// Next Tab's second binding, and handing it to something else would leave
    /// two live menu items on one keystroke with AppKit picking the winner by
    /// menu order.
    static func conflict(for binding: KeyBinding, ignoring command: BrowserCommand) -> Conflict? {
        if let reserved = reserved(binding) { return .reserved(reserved) }
        let owner = BrowserCommand.all.first { other in
            other.id != command.id && bindings(for: other).contains(binding)
        }
        return owner.map(Conflict.command)
    }

    /// The two families of numbered shortcuts, which are built from live data —
    /// nine Spaces, nine sidebar rows — and so have no row in the table to
    /// collide with. They are still taken, and taking one back would break a
    /// menu that is rebuilt from the session rather than from here.
    ///
    /// ⌘0 is deliberately not in the range: it is Zoom to Actual Size, and the
    /// sidebar rows start at one.
    private static func reserved(_ binding: KeyBinding) -> String? {
        guard binding.key.count == 1, let digit = Int(binding.key), (1...9).contains(digit) else { return nil }
        if binding.modifiers == .command { return String(localized: "Going to a sidebar item") }
        if binding.modifiers == .control { return String(localized: "Switching Space") }
        return nil
    }
}
