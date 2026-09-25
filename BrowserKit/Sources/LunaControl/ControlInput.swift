import Foundation

/// Keys and modifiers as trusted input needs them: a virtual key code and
/// the characters an `NSEvent` carries. Here rather than beside the stage so
/// a bad key name is refused when the call is decoded, before anything runs.
///
/// Key codes are the US layout's (HIToolbox `kVK_*`). Pages read `event.key`,
/// which comes from the characters; the code only feeds `event.code`.
public enum ControlInput {

    /// Why a trusted click at a spot the library's `locate` routed elsewhere
    /// is refused: a native select, date or colour picker, or a file dialog,
    /// runs on the user's screen however it is opened.
    public static func refusal(routing route: String?) -> String? {
        switch route {
        case "form_input":
            "That opens a native picker on the user's screen, so Luna does not click it. Set it with form_input."
        case "file_upload":
            "That opens a file dialog on the user's screen, so Luna does not click it. Use file_upload with its ref."
        default:
            nil
        }
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let shift = Modifiers(rawValue: 1)
        public static let control = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public struct Key: Sendable, Equatable {
        public var keyCode: UInt16
        public var characters: String
        public var charactersIgnoringModifiers: String
        public var modifiers: Modifiers
    }

    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "meta": .command,
        "ctrl": .control, "control": .control,
        "alt": .option, "option": .option, "opt": .option,
        "shift": .shift
    ]

    /// Lower-cased name to key code and the character AppKit gives it; the
    /// arrows and the rest of the navigation block are AppKit's function-key
    /// characters (`NSUpArrowFunctionKey` and its neighbours).
    private static let named: [String: (UInt16, String)] = [
        "enter": (36, "\r"), "return": (36, "\r"), "tab": (48, "\t"), "space": (49, " "),
        "escape": (53, "\u{1b}"), "esc": (53, "\u{1b}"), "backspace": (51, "\u{7f}"),
        "delete": (117, "\u{F728}"), "arrowup": (126, "\u{F700}"), "arrowdown": (125, "\u{F701}"),
        "arrowleft": (123, "\u{F702}"), "arrowright": (124, "\u{F703}"), "up": (126, "\u{F700}"),
        "down": (125, "\u{F701}"), "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
        "home": (115, "\u{F729}"), "end": (119, "\u{F72B}"), "pageup": (116, "\u{F72C}"), "pagedown": (121, "\u{F72D}"),
        "f1": (122, "\u{F704}"), "f2": (120, "\u{F705}"), "f3": (99, "\u{F706}"), "f4": (118, "\u{F707}"),
        "f5": (96, "\u{F708}"), "f6": (97, "\u{F709}"), "f7": (98, "\u{F70A}"), "f8": (100, "\u{F70B}"),
        "f9": (101, "\u{F70C}"), "f10": (109, "\u{F70D}"), "f11": (103, "\u{F70E}"), "f12": (111, "\u{F70F}")
    ]

    /// Unshifted characters to their key.
    private static let plain: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50, " ": 49
    ]

    /// Shifted characters to the unshifted one on the same key.
    private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`"
    ]

    /// "cmd+shift" and the like; empty is none.
    public static func modifiers(_ spec: String) throws -> Modifiers {
        var result: Modifiers = []
        for part in spec.split(separator: "+") where !part.isEmpty {
            guard let modifier = modifierNames[part.lowercased()] else {
                throw ControlError("“\(part)” is not a modifier. Use cmd, ctrl, alt/option or shift.")
            }
            result.insert(modifier)
        }
        return result
    }

    /// One press: a named key or a single character, after any modifiers —
    /// "Enter", "cmd+a", "shift+Tab".
    public static func key(_ combo: String) throws -> Key {
        var parts = combo.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "cmd++" presses plus.
        if combo.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
        let name = parts.removeLast()
        let modifiers = try Self.modifiers(parts.joined(separator: "+"))
        if let (code, character) = named[name.lowercased()] {
            return Key(keyCode: code, characters: character, charactersIgnoringModifiers: character, modifiers: modifiers)
        }
        guard name.count == 1, let character = name.first else {
            throw ControlError("“\(name)” is not a key. Use a name like Enter, Tab, Escape, ArrowDown, F5, or one character.")
        }
        var key = self.key(for: character)
        key.modifiers.formUnion(modifiers)
        if key.modifiers.contains(.shift), key.charactersIgnoringModifiers == key.characters {
            key.characters = key.characters.uppercased()
        }
        return key
    }

    /// The presses that type `text`, one per character. A newline is Enter.
    public static func keys(typing text: String) -> [Key] {
        text.map { $0 == "\n" ? Key(keyCode: 36, characters: "\r", charactersIgnoringModifiers: "\r", modifiers: [])
            : key(for: $0) }
    }

    /// A character with no key on the US layout — an accent, an emoji — still
    /// goes as itself; WebKit inserts the event's characters whatever the code.
    private static func key(for character: Character) -> Key {
        let text = String(character)
        if let code = plain[character] {
            return Key(keyCode: code, characters: text, charactersIgnoringModifiers: text, modifiers: [])
        }
        let lower = Character(text.lowercased())
        if character.isUppercase, let code = plain[lower] {
            return Key(keyCode: code, characters: text, charactersIgnoringModifiers: String(lower), modifiers: .shift)
        }
        if let base = shifted[character], let code = plain[base] {
            return Key(keyCode: code, characters: text, charactersIgnoringModifiers: String(base), modifiers: .shift)
        }
        return Key(keyCode: 0, characters: text, charactersIgnoringModifiers: text, modifiers: [])
    }
}
