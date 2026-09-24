//
//  LunaControl.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10, docs/LUNA-CONTROL.md.
//
//  The switch, and one row per MCP client that says whether Luna is in its
//  config and adds or removes it. The config edits themselves are
//  `ControlApp`'s, in `LunaControl`, where they are tested against a
//  temporary home; nothing here writes a file except in answer to a press.
//

import AppKit
import LunaControl

@MainActor
final class LunaControlSection: NSObject, SettingsSection {

    static let id = "control"
    static let title = String(localized: "Luna Control")
    static let symbolName = "point.3.connected.trianglepath.dotted"
    static let keywords = [
        "mcp", "agent", "ai", "automation", "claude", "codex", "cursor", "vs code", "allow apps to control luna"
    ]

    private let container = NSView()
    private var body = SettingsBody()
    private var query = ""
    /// Apps connected in this window's lifetime that only read their config
    /// at launch, so their row can say so.
    private var awaitingRestart: Set<String> = []

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let helper = ControlService.helperURL

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
    }

    override init() {
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
        // A client connecting changes a row, and so does coming back from
        // Terminal after running Claude Code's command.
        for name in [ControlService.clientsDidChange, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
    }

    @objc private func refresh() { build() }

    func willAppear() { build() }

    /// Rebuilt rather than mutated: every row's words and button follow from
    /// files on disk and the live connections, read fresh each time.
    private func build() {
        body = SettingsBody()
        body.card(nil, [enabledRow()])
        let note = String(localized: "Connected apps use Luna as you, signed in to your sites. Only connect apps you trust.")
        body.loose(SettingsRow.note(note), terms: [note])
        let live = SettingsHost.control?.clientNames ?? []
        body.card(String(localized: "Connect an app"), ControlApp.all.map { appRow($0, live: live) })
        body.card(nil, [otherAppsRow(live: live)])
        body.filter(query)
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

    private func enabledRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Allow apps to control Luna")
        let subtitle = String(localized: "Lets AI apps on this Mac open tabs, read pages and click for you")
        let row = SettingsRow.toggle(title, subtitle: subtitle, value: ControlService.isEnabled) { on in
            ControlService.isEnabled = on
        }
        return (view: row, terms: [title, subtitle, "mcp", "agent", "automation"])
    }

    // MARK: - Apps

    private func appRow(_ app: ControlApp, live: [String]) -> (view: NSView, terms: [String]) {
        let terms = [app.name, "mcp", "connect"]
        guard app.isInstalled(home: home) else {
            let row = SettingsRowView(
                title: app.name,
                subtitle: String(localized: "Not installed"),
                control: nil,
                isEnabled: true,
                disabledReason: nil
            )
            return (view: row, terms: terms)
        }
        let connected = app.isConnected(home: home)
        var status = connected ? String(localized: "Connected") : String(localized: "Not connected")
        if connected, live.contains(where: app.matches(clientName:)) {
            status += String(localized: " · in use now")
        } else if connected, awaitingRestart.contains(app.id) {
            status += String(localized: " · restart \(app.name) to load it")
        }

        let button: SettingsPushButton
        if let command = app.command(connecting: !connected, helper: helper) {
            if !connected { status += String(localized: " · paste the command in Terminal") }
            button = SettingsPushButton(
                title: connected ? String(localized: "Copy Remove Command") : String(localized: "Copy Command"),
                isDestructive: false
            )
            button.onActivate = { [weak self, weak button] in
                self?.copy(command, from: button)
                if !connected { self?.awaitingRestart.insert(app.id) }
            }
        } else {
            button = SettingsPushButton(
                title: connected ? String(localized: "Disconnect") : String(localized: "Connect"),
                isDestructive: false
            )
            button.onActivate = { [weak self] in self?.toggle(app, connected: connected) }
        }
        return (view: SettingsRow.accessory(app.name, subtitle: status, accessory: button), terms: terms)
    }

    private func toggle(_ app: ControlApp, connected: Bool) {
        do {
            if connected {
                try app.disconnect(home: home)
                awaitingRestart.remove(app.id)
            } else {
                try app.connect(home: home, helper: helper)
                if app.needsRestart { awaitingRestart.insert(app.id) }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Luna couldn’t change \(app.name)’s settings")
            alert.informativeText = "\(app.config(in: home).path(percentEncoded: false))\n\n\(error)"
            alert.runModal()
        }
        build()
    }

    // MARK: - Any other app

    private func otherAppsRow(live: [String]) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Other apps")
        let others = live.filter { name in !ControlApp.all.contains { $0.matches(clientName: name) } }
        let subtitle = others.isEmpty
            ? String(localized: "Most MCP apps take this entry in their MCP settings")
            : String(localized: "In use now by \(others.map(ControlClient.displayName(for:)).joined(separator: ", "))")
        let button = SettingsPushButton(title: String(localized: "Copy JSON"), isDestructive: false)
        let json = ControlApp.genericJSON(helper: helper)
        button.onActivate = { [weak self, weak button] in self?.copy(json, from: button) }
        let row = SettingsRow.accessory(title, subtitle: subtitle, accessory: button)
        return (view: row, terms: [title, subtitle, "json", "mcp"])
    }

    /// The button says it worked, briefly, since a copy has nothing else to
    /// show. The row is rebuilt on the way back, which puts the title back.
    private func copy(_ text: String, from button: SettingsPushButton?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let title = button?.title
        button?.title = String(localized: "Copied")
        Task { @MainActor [weak button] in
            try? await Task.sleep(for: Self.copiedLinger)
            if let title { button?.title = title }
        }
    }

    private static let copiedLinger: Duration = .seconds(1.5)
}
