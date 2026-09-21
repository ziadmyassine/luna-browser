//
//  KeyBinding.swift
//  Luna
//
//  One keystroke, as a value — the thing a menu item wears, the thing the user
//  records in Settings, and the thing that has to survive a relaunch.
//
//  Shift is always in the mask, never in the letter. AppKit accepts two
//  spellings of ⇧⌘T: `keyEquivalent "T"` with `.command`, or `keyEquivalent "t"`
//  with `[.command, .shift]`. `MainMenu` used the first, which is fine for a
//  table written by hand and wrong for one a user can edit — it makes the shift
//  bit live in two places, so a recorded keystroke and a declared default of the
//  same shortcut compare unequal and the conflict check misses. Everything here
//  normalises to the second spelling: the key is lowercased, and shift is a
//  modifier like the other three.
//
//  A shifted symbol keeps whatever the layout produced — ⇧⌘[ records as ⇧⌘{
//  on a US keyboard, because that is the character AppKit will be matching
//  against. It fires correctly; it is only the printed glyph that is the shifted
//  one. Left alone deliberately: unshifting it needs `UCKeyTranslate` and a
//  layout round-trip, which is a lot of machinery to make a label prettier.
//

import AppKit

/// A key equivalent: the character AppKit matches, plus the modifiers held with
/// it. Nil is not represented here — a command with no shortcut has no
/// `KeyBinding` at all.
struct KeyBinding: Hashable {

    /// Lowercased. For arrows and friends this is the private-use scalar
    /// `NSLeftArrowFunctionKey` and its neighbours name, not a printable glyph.
    let key: String

    /// Only ever ⌘ ⌥ ⌃ ⇧ — `deviceIndependentFlagsMask` minus the lock keys.
    let modifiers: NSEvent.ModifierFlags

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection(Self.allowed)
    }

    /// An arrow or other function key, which is an `Int` constant in the
    /// private-use plane rather than a character — `"←"` in a source file is a
    /// different scalar entirely and matches nothing.
    init(function: Int, _ modifiers: NSEvent.ModifierFlags) {
        self.init(UnicodeScalar(UInt32(function)).map { String(Character($0)) } ?? "", modifiers)
    }

    static let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// Hand-written because `NSEvent.ModifierFlags` is an `OptionSet` and stops
    /// at `Equatable` — it has no `Hashable` conformance to synthesise from.
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    // MARK: - Display

    /// As the user sees it, in AppKit's own modifier order: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.displayKey(key)
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

    static func displayKey(_ key: String) -> String {
        guard key.count == 1, let scalar = key.unicodeScalars.first else { return key.uppercased() }
        return named[scalar.value] ?? key.uppercased()
    }

    // MARK: - Storage

    /// `"cmd+shift+t"` — a form that survives a `UserDefaults` round trip and
    /// reads as itself in `defaults read`. The key comes last and is escaped as
    /// a scalar when it is not printable, which is how an arrow makes it
    /// through a string-keyed store intact.
    var stored: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(Self.isPrintable(key) ? key : "u\(key.unicodeScalars.first?.value ?? 0)")
        return parts.joined(separator: "+")
    }

    /// **The modifiers are eaten from the front, and whatever is left is the
    /// key — separators included.** Cutting at the last `+` instead looks
    /// obviously right and loses ⌘+: `"cmd++"` splits into `"cmd+"` and `""`,
    /// and Zoom In comes back from `UserDefaults` with no key at all. The
    /// modifier names are a closed vocabulary, so reading them left to right is
    /// unambiguous in a way that reading the key right to left is not.
    init?(stored: String) {
        var tokens = stored.components(separatedBy: "+")
        var modifiers: NSEvent.ModifierFlags = []
        let known: [String: NSEvent.ModifierFlags] = [
            "ctrl": .control, "alt": .option, "shift": .shift, "cmd": .command
        ]
        while let first = tokens.first, let flag = known[first] {
            modifiers.insert(flag)
            tokens.removeFirst()
        }
        guard let key = Self.unescape(tokens.joined(separator: "+")), !key.isEmpty else { return nil }
        self.init(key, modifiers)
    }

    private static func isPrintable(_ key: String) -> Bool {
        guard let scalar = key.unicodeScalars.first else { return false }
        return scalar.value > 0x20 && scalar.value < 0x7F
    }

    private static func unescape(_ raw: String) -> String? {
        guard raw.first == "u", raw.count > 1, let value = UInt32(raw.dropFirst()) else { return raw }
        return UnicodeScalar(value).map { String(Character($0)) }
    }

    // MARK: - Recording

    /// The keystroke an event describes, or nil for one that cannot be a
    /// shortcut.
    ///
    /// At least one of ⌘ ⌃ ⌥ is required, and shift alone does not count: a
    /// menu key equivalent fires wherever the app is focused, so a bare letter —
    /// or ⇧-letter — would be swallowed out of every text field in the browser,
    /// including the address bar. Nothing else is refused here; whether the
    /// keystroke is already taken is `KeyBindings`' question, not this one.
    init?(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
        let modifiers = event.modifierFlags.intersection(Self.allowed)
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.init(characters, modifiers)
    }
}
