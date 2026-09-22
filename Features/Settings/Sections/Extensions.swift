//
//  Extensions.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.8 — entirely disabled, on purpose.
//
//  No list, no install button, no "coming soon" placeholder row. TODO.md §32
//  decided general extension support is out of v1, and §30.14's copy warning is
//  exactly this mistake in miniature: a surface that implies a store we do not
//  have is a promise broken in the first five minutes.
//

import AppKit

@MainActor
final class ExtensionsSection: SettingsSection {

    static let id = "extensions"
    static let title = String(localized: "Extensions")
    static let symbolName = "puzzlepiece.extension"
    static let keywords = ["add-ons", "plug-ins", "web extensions"]

    private let body = SettingsBody()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        let text = String(localized: """
        Luna has no extensions yet.

        When it does, they will be Safari Web Extensions — the same kind Safari loads, \
        hosted by WebKit's own `WKWebExtensionController`. The host side of that is not \
        built (§16), so there is nothing here to turn on.

        Extensions written for Chrome will not all work. Safari Web Extensions share \
        Chrome's manifest and most of its APIs, but not all of them, and an extension \
        that leans on the parts WebKit does not implement will misbehave rather than \
        refuse to install (§26). Luna will say which ones when there is something to say it about.
        """)
        body.loose(SettingsRow.note(text), terms: [
            "extensions", "safari web extensions", "chrome", "add-ons", "plugins"
        ])
    }
}
