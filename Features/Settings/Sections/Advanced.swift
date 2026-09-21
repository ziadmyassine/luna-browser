//
//  Advanced.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.9.
//
//  The user-agent row is the one with a trap in it. `applicationNameForUserAgent`
//  appends to WebKit's default UA and WebKit's default carries no `Safari/`
//  token, so the Default option cannot be built by editing that string — it is
//  built by leaving it alone. The three impersonating modes replace the whole
//  UA through `WKWebView.customUserAgent` instead. See `WebViewFactory`.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class AdvancedSection: SettingsSection {

    static let id = "advanced"
    static let title = String(localized: "Advanced")
    static let symbolName = "bolt"

    private let container = NSView()
    private var body = SettingsBody()

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    /// Rebuilt rather than mutated, because "Restore all settings" changes the
    /// value every row in this section is showing.
    private func build() {
        body = SettingsBody()
        body.card(String(localized: "Web content"), [userAgentRow(), customUserAgentRow(), webInspectorRow()])
        body.card(String(localized: "Development"), [developMenuRow()])
        body.card(nil, [revealDatabaseRow(), restoreDefaultsRow()])
        for subview in container.subviews { subview.removeFromSuperview() }
        let stack = body.view
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    // MARK: User agent

    private func userAgentRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "User agent")
        let options = [
            String(localized: "Default"), String(localized: "Safari"),
            String(localized: "Chrome"), String(localized: "Custom")
        ]
        let modes = WebViewFactory.UserAgentMode.allCases
        let subtitle = String(localized: "Takes effect on the next page load, not on the page already open")
        let row = SettingsRow.popup(
            title,
            subtitle: subtitle,
            options: options,
            selected: modes.firstIndex(of: WebViewFactory.userAgentMode) ?? 0,
            onChange: { [weak self] index in
                WebViewFactory.userAgentMode = modes[index]
                self?.applyToLiveWebViews()
            }
        )
        return (view: row, terms: [title, subtitle, "user agent", "ua", "safari", "chrome"])
    }

    /// Empty is not an error state: `WebViewFactory.customUserAgent(for:)`
    /// returns nil for it, so a Custom mode nobody has filled in behaves as
    /// Default rather than sending an empty UA header.
    private func customUserAgentRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Custom user agent")
        let row = SettingsRow.text(
            title,
            value: WebViewFactory.customUserAgentString,
            placeholder: String(localized: "Leave empty to use Luna's own")
        ) { [weak self] text in
            WebViewFactory.customUserAgentString = text
            self?.applyToLiveWebViews()
        }
        return (view: row, terms: [title, "custom user agent", "ua"])
    }

    // MARK: Developer

    private func webInspectorRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Enable Web Inspector")
        let subtitle = String(localized: "Adds “Inspect Element” to the page menu")
        let row = SettingsRow.toggle(title, subtitle: subtitle, value: WebViewFactory.isWebInspectorEnabled) { [weak self] on in
            WebViewFactory.isWebInspectorEnabled = on
            self?.applyToLiveWebViews()
        }
        return (view: row, terms: [title, subtitle, "inspector", "developer", "devtools"])
    }

    /// Dimmed because there is nothing to show: `MainMenu` builds no Develop
    /// menu, so the switch would set a key no menu reads. The Web Inspector
    /// above is the part of this that exists, and it is wired.
    private func developMenuRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Show Develop menu")
        let row = SettingsRow.toggle(
            title,
            subtitle: nil,
            value: false,
            isEnabled: false,
            disabledReason: String(localized: "Luna has no Develop menu yet (§22.5)."),
            onChange: { _ in }
        )
        return (view: row, terms: [title, "develop menu", "developer"])
    }

    /// `customUserAgent` and `isInspectable` are per-web-view, so a setting
    /// changed now has to be pushed onto the views that already exist. A
    /// hibernated tab has no web view at all (§19.2) and gets the new value
    /// when it is woken and rebuilt.
    private func applyToLiveWebViews() {
        guard let session = SettingsHost.session else { return }
        for tab in session.allTabs(includeArchived: false) {
            guard let webView = session.controller(for: tab.id)?.webView else { continue }
            WebViewFactory.applyAdvancedSettings(to: webView)
        }
    }

    // MARK: The two buttons

    /// `BrowserStore` does not expose the file it opened, and `AppDelegate`'s
    /// `databaseURL` is private, so this re-derives the same path. Two copies of
    /// one rule is one too many — `BrowserStore` should carry its own `path`.
    static var databaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "luna.sqlite")
    }

    private func revealDatabaseRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Reveal the database in Finder")
        let url = Self.databaseURL
        let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        let row = SettingsRow.button(
            title,
            action: String(localized: "Reveal"),
            isEnabled: exists,
            disabledReason: exists ? nil : String(localized: "The database has not been created yet.")
        ) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return (view: row, terms: [title, "database", "sqlite", "finder"])
    }

    private func restoreDefaultsRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Restore all settings to defaults")
        let row = SettingsRow.button(
            title,
            action: String(localized: "Restore…"),
            isDestructive: true
        ) { [weak self] in self?.restoreDefaults() }
        return (view: row, terms: [title, "reset", "defaults", "restore"])
    }

    /// Typing the word is the point: this is the one button in Settings whose
    /// damage is invisible afterwards — nothing looks broken, the window just
    /// quietly stops being the one you configured.
    private func restoreDefaults() {
        let word = String(localized: "Restore")
        guard SettingsHost.confirm(
            String(localized: "Restore every setting to its default?"),
            String(localized: """
            Every setting in this window goes back to how Luna shipped. Your tabs, Spaces, \
            history and downloads are untouched. Type \(word) below to confirm.
            """),
            action: word,
            byTyping: word
        ) else { return }
        SettingsDefaults.restoreAll()
        applyToLiveWebViews()
        build()
    }
}
