//
//  LunaControl.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10, docs/LUNA-CONTROL.md.
//
//  The switch, and one row per MCP client that says whether Luna is in its
//  config and adds or removes it. Then the safety side: how much a connected
//  app may do before Luna asks, the sites allowed per app, and the last calls
//  from the activity log. The config edits themselves are
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
        for name in [ControlService.clientsDidChange, ControlService.activityDidChange,
                     NSApplication.didBecomeActiveNotification] {
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
        if let control = SettingsHost.control {
            body.card(String(localized: "Permissions"), [modeRow(control)])
            body.card(String(localized: "Allowed sites"), grantRows(control))
            body.card(String(localized: "Recent activity"), activityRows(control))
        }
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

    // MARK: - Permissions and activity

    private static let modes: [(ControlMode, String)] = [
        (.ask, String(localized: "Ask")),
        (.allowPerSite, String(localized: "Per Site")),
        (.allowAll, String(localized: "Allow All"))
    ]

    private func modeRow(_ control: ControlService) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Before an app acts on a page")
        let subtitle = String(localized: """
        Ask every time, ask once per site, or allow everything. Reading never asks; local files and pages \
        that talk to the agent always do.
        """)
        let current = Self.modes.firstIndex { $0.0 == control.permissions.mode } ?? 0
        let row = SettingsRow.segmented(
            title, subtitle: subtitle, options: Self.modes.map(\.1), selected: current
        ) { index in control.setMode(Self.modes[index].0) }
        return (view: row, terms: [title, subtitle, "permission", "approve", "ask"])
    }

    private func grantRows(_ control: ControlService) -> [(view: NSView, terms: [String])] {
        let grants = control.permissions.grants.sorted { ($0.site, $0.client) < ($1.site, $1.client) }
        guard !grants.isEmpty else {
            let empty = String(localized: "No sites yet. In Per Site mode, Allow on a request adds one here.")
            return [(view: SettingsRow.status(empty), terms: [empty])]
        }
        return grants.map { grant in
            let button = SettingsPushButton(title: String(localized: "Revoke"), isDestructive: true)
            button.onActivate = { control.revoke(grant) }
            let row = SettingsRow.accessory(grant.site, subtitle: grant.client, accessory: button)
            return (view: row, terms: [grant.site, grant.client, "revoke"])
        }
    }

    /// The last calls, newest first. The whole log is `activity.jsonl` in
    /// the Control folder.
    private func activityRows(_ control: ControlService) -> [(view: NSView, terms: [String])] {
        let records = ControlAudit.read(from: control.auditURL, limit: Self.activityShown)
        guard !records.isEmpty else {
            let empty = String(localized: "Nothing yet.")
            return [(view: SettingsRow.status(empty), terms: [empty])]
        }
        return records.map { record in
            let time = record.time.formatted(date: .omitted, time: .shortened)
            let subtitle = [record.site, record.decision, record.outcome == "error" ? "failed" : nil, time]
                .compactMap(\.self).joined(separator: " · ")
            let row = SettingsRowView(
                title: "\(record.client): \(record.summary)", subtitle: subtitle,
                control: nil, isEnabled: true, disabledReason: nil
            )
            return (view: row, terms: ["activity", "log"])
        }
    }

    private static let activityShown = 20

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
