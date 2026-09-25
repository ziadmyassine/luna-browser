//
//  SettingsHost.swift
//  Luna
//
//  How a `SettingsSection` reaches the running app, and the two dialogs every
//  destructive row in Settings goes through.
//
//  It lives in `Shell/` because all five of the sections that clear data, delete
//  a Space or restore defaults need it, and a shared helper parked inside one
//  section's file is a helper nobody finds.
//

import AppKit
import BrowserKit

// MARK: - Shared by the C sections

/// The app's own wiring and Settings' two dialogs.
///
/// `SettingsSection.init()` takes no arguments, so a section that needs the
/// session looks it up rather than being handed it. Both are optional on
/// purpose: Settings can be open before `startSession` has finished, and a
/// section that assumes otherwise crashes on a cold launch.
@MainActor
enum SettingsHost {

    static var session: BrowserSession? { (NSApp.delegate as? AppDelegate)?.session }
    static var store: BrowserStore? { (NSApp.delegate as? AppDelegate)?.store }
    static var control: ControlService? { (NSApp.delegate as? AppDelegate)?.control }

    /// Every destructive button in Settings goes through here first.
    static func confirm(_ message: String, _ informative: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: String(localized: "Cancel"))
        // Escape must map to Cancel, and a stray Return must not pick the
        // destructive answer.
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// §3.9's "requires the word to be typed". Not theatre: it is the one
    /// dialog in Luna that muscle-memory Return cannot answer.
    static func confirm(_ message: String, _ informative: String, action: String, byTyping word: String) -> Bool {
        guard let typed = ask(message, informative, action: action, placeholder: word) else { return false }
        return typed.caseInsensitiveCompare(word) == .orderedSame
    }

    /// One line of text, or nil if the user cancelled or typed nothing.
    static func ask(_ message: String, _ informative: String, action: String, placeholder: String) -> String? {
        let field = NSTextField(frame: NSRect(origin: .zero, size: Tokens.Metric.urlPill.size))
        field.placeholderString = placeholder
        field.setAccessibilityLabel(message)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.accessoryView = field
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
