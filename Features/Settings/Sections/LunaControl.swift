//
//  LunaControl.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.10, docs/LUNA-CONTROL.md ("The Settings pane").
//
//  The sky with the switch in it, and one row per MCP client that says
//  whether Luna is in its config and adds or removes it. Then the safety
//  side: how much a connected app may do before Luna asks, the sites allowed
//  per app, and the last calls from the activity log. The config edits
//  themselves are `ControlApp`'s, in `LunaControl`, where they are tested
//  against a temporary home; nothing here writes a file except in answer to a
//  press.
//

import AppKit
import LunaControl

@MainActor
final class LunaControlSection: NSObject, SettingsSection {

    static let id = "control"
    static let title = String(localized: "Luna Control")
    static let symbolName = "moon.fill"
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

    /// Kept across rebuilds: the sky and the permission cards are animating
    /// while the rows around them are replaced.
    private let sky = ControlSkyView(
        title: String(localized: "Allow apps to control Luna"),
        subtitle: String(localized: "Lets AI apps on this Mac open tabs, read pages and click for you")
    )
    private let modes = ControlModePicker(title: String(localized: "Before an app acts on a page"))
    private let flights = ControlFlightView()
    /// Each connected app's planet in the current rows, so a flight knows
    /// where to start.
    private var planets: [String: ControlPlanetView] = [:]
    /// The newest activity already shown. Anything newer is a call made since,
    /// which beams to the moon and fades into the log.
    private var lastSeen: Date?
    private var pendingLaunch: String?

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
    }

    override init() {
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(flights)
        NSLayoutConstraint.activate([
            flights.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            flights.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            flights.topAnchor.constraint(equalTo: container.topAnchor),
            flights.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        sky.onToggle = { [weak self] on in
            ControlService.isEnabled = on
            self?.build()
        }
        modes.onChange = { [weak self] mode in
            SettingsHost.control?.setMode(mode)
            self?.build()
        }
        build()
        // A client connecting changes a row, and so does coming back from
        // Terminal after running Claude Code's command.
        for name in [ControlService.clientsDidChange, ControlService.activityDidChange,
                     NSApplication.didBecomeActiveNotification, Settings.didChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
    }

    @objc private func refresh() { build() }

    func willAppear() {
        build()
        sky.rise()
    }

    /// Rebuilt rather than mutated: every row's words and button follow from
    /// files on disk and the live connections, read fresh each time.
    private func build() {
        let live = SettingsHost.control?.clientNames ?? []
        let isOn = ControlService.isEnabled
        body = SettingsBody()
        planets = [:]

        sky.setOn(isOn, animated: sky.window != nil)
        sky.setSatellites(satellites(live: live, isOn: isOn))
        let status = skyStatus(live: live, isOn: isOn)
        sky.setStatus(status.text, dot: status.dot)
        body.card(sky, rows: [(view: sky, terms: [
            "Allow apps to control Luna", "Lets AI apps on this Mac open tabs, read pages and click for you",
            "luna control", "mcp", "agent", "automation"
        ])])
        body.card(String(localized: "Connect an app"), ControlApp.all.enumerated().map { appRow($1, index: $0, live: live) })
        body.card(nil, [otherAppsRow(live: live)])
        let fresh = SettingsHost.control.map { permissionsAndActivity($0) } ?? []
        body.filter(query)
        install()
        for row in fresh { fadeIn(row) }
        launchIfPending()
    }

    private func install() {
        for subview in container.subviews where subview !== flights { subview.removeFromSuperview() }
        let stack = body.view
        container.addSubview(stack, positioned: .below, relativeTo: flights)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    // MARK: - The sky

    private func satellites(live: [String], isOn: Bool) -> [ControlSkyView.Satellite] {
        ControlApp.all.enumerated().compactMap { index, app in
            guard app.isInstalled(home: home), app.isConnected(home: home) else { return nil }
            return ControlSkyView.Satellite(
                id: app.id, name: app.name, colour: Tokens.Moon.satellite(index),
                icon: ControlAppIcon.image(for: app.id), orbit: index % 2,
                startAngle: 0.6 + CGFloat(index) * 2.2,
                isLive: isOn && live.contains(where: app.matches(clientName:))
            )
        }
    }

    private func skyStatus(live: [String], isOn: Bool) -> (text: String, dot: ControlStatusDot.State) {
        guard isOn else { return (String(localized: "Off · apps can’t reach Luna"), .off) }
        let connected = ControlApp.all.filter { $0.isInstalled(home: home) && $0.isConnected(home: home) }
        let inUse = connected.filter { app in live.contains(where: app.matches(clientName:)) }.map(\.name)
        var text = connected.isEmpty
            ? String(localized: "On · no apps connected yet")
            : String(localized: "On · \(connected.count) connected")
        if !inUse.isEmpty { text += String(localized: " · \(inUse.joined(separator: ", ")) in use") }
        return (text, live.isEmpty ? .on : .live)
    }

    /// The colour an app's calls carry in the log: its light's, when it is one
    /// of the apps Luna knows, and otherwise one picked from its name that
    /// stays the same from launch to launch.
    private func colour(ofClient client: String) -> NSColor {
        if let index = ControlApp.all.firstIndex(where: { $0.name == client || $0.matches(clientName: client) }) {
            return Tokens.Moon.satellite(index)
        }
        return Tokens.Moon.satellite(client.unicodeScalars.reduce(0) { $0 + Int($1.value) })
    }

    private func satelliteID(ofClient client: String) -> String? {
        ControlApp.all.first { $0.name == client || $0.matches(clientName: client) }?.id
    }

    // MARK: - Apps

    private func appRow(_ app: ControlApp, index: Int, live: [String]) -> (view: NSView, terms: [String]) {
        let terms = [app.name, "mcp", "connect"]
        let colour = Tokens.Moon.satellite(index)
        guard app.isInstalled(home: home) else {
            let row = ControlAppRowView(
                name: app.name, colour: colour, icon: ControlAppIcon.image(for: app.id),
                status: String(localized: "Not installed"), dot: .off,
                isInstalled: false, isConnected: false, accessory: nil
            )
            return (view: row, terms: terms)
        }
        let connected = app.isConnected(home: home)
        let inUse = connected && live.contains(where: app.matches(clientName:))
        var status = connected ? String(localized: "Connected") : String(localized: "Not connected")
        if inUse {
            status += String(localized: " · in use now")
        } else if connected, awaitingRestart.contains(app.id) {
            status += String(localized: " · restart \(app.name) to load it")
        }

        if !connected, copiesCommand(app) { status += String(localized: " · paste the command in Terminal") }
        let button = connectButton(for: app, connected: connected)
        let row = ControlAppRowView(
            name: app.name, colour: colour, icon: ControlAppIcon.image(for: app.id), status: status,
            dot: inUse ? .live : (connected ? .on : .off), isInstalled: true, isConnected: connected, accessory: button
        )
        if connected { planets[app.id] = row.planet }
        return (view: row, terms: terms)
    }

    private func toggle(_ app: ControlApp, connected: Bool) {
        do {
            if connected {
                try app.disconnect(home: home)
            } else {
                try app.connect(home: home, helper: helper)
            }
            changed(app, connected: !connected)
        } catch {
            refuse(app, error)
        }
        build()
    }

    /// A newly connected app's light flies from its planet up into orbit.
    /// Straight into orbit instead when there is nothing to see it by: Luna
    /// Control off, the sky scrolled away, or Reduce Motion.
    private func launchIfPending() {
        guard let id = pendingLaunch else { return }
        pendingLaunch = nil
        guard ControlService.isEnabled, !Tokens.Motion.reduceMotion else { return }
        sky.hold(id)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.container.layoutSubtreeIfNeeded()
            let duration = Tokens.Motion.satelliteLaunch.duration
            guard let planet = self.planets[id], !self.sky.visibleRect.isEmpty,
                  let target = self.sky.predictedPoint(of: id, after: duration) else {
                return self.sky.release(id)
            }
            let start = self.flights.convert(CGPoint(x: planet.bounds.midX, y: planet.bounds.midY), from: planet)
            let end = self.flights.convert(target, from: self.sky)
            self.flights.fly(from: start, to: end, colour: Tokens.Moon.satellite(
                ControlApp.all.firstIndex { $0.id == id } ?? 0
            )) { [weak self] in self?.sky.release(id) }
        }
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

}

// MARK: - Connecting

extension LunaControlSection {

    /// Connect and Disconnect, or for an app whose tool Luna cannot find, a
    /// button that copies the command to run instead.
    private func connectButton(for app: ControlApp, connected: Bool) -> SettingsPushButton {
        let button: SettingsPushButton
        if let run = app.invocation(connecting: !connected, helper: helper),
           let tool = ControlCLI.locate(run.tool, home: home) {
            button = SettingsPushButton(
                title: connected ? String(localized: "Disconnect") : String(localized: "Connect"),
                isDestructive: false
            )
            button.onActivate = { [weak self, weak button] in
                self?.run(app, tool: tool, arguments: run.arguments, connected: connected, from: button)
            }
        } else if let command = app.command(connecting: !connected, helper: helper) {
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
        return button
    }

    /// An app connected by a command Luna cannot run, because its tool is in
    /// none of `ControlCLI`'s folders.
    private func copiesCommand(_ app: ControlApp) -> Bool {
        guard let run = app.invocation(connecting: true, helper: helper) else { return false }
        return ControlCLI.locate(run.tool, home: home) == nil
    }

    /// An app whose config only its own tool may write: the tool makes the
    /// change, off the main thread, while the button says so.
    private func run(
        _ app: ControlApp, tool: URL, arguments: [String], connected: Bool, from button: SettingsPushButton?
    ) {
        button?.isEnabled = false
        button?.title = connected ? String(localized: "Disconnecting…") : String(localized: "Connecting…")
        Task { @MainActor [weak self] in
            do {
                _ = try await ControlCLI.run(tool, arguments: arguments)
                self?.changed(app, connected: !connected)
            } catch {
                self?.refuse(app, error)
            }
            self?.build()
        }
    }

    private func changed(_ app: ControlApp, connected: Bool) {
        if connected {
            if app.needsRestart { awaitingRestart.insert(app.id) }
            pendingLaunch = app.id
        } else {
            awaitingRestart.remove(app.id)
        }
    }

    private func refuse(_ app: ControlApp, _ error: any Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Luna couldn’t change \(app.name)’s settings")
        alert.informativeText = "\(app.config(in: home).path(percentEncoded: false))\n\n\(error)"
        alert.runModal()
    }
}

// MARK: - Permissions and activity

extension LunaControlSection {

    /// The three lower groups. Returns the activity rows that are new since
    /// the last build, for `build` to fade in once they are on screen.
    private func permissionsAndActivity(_ control: ControlService) -> [NSView] {
        let mode = control.permissions.mode
        modes.select(mode, animated: false)
        body.card(modes, rows: [(view: modes, terms: [
            "Before an app acts on a page", "permission", "approve", "ask", "per site", "allow all"
        ])])

        let sites = grantRows(control)
        let grants = SettingsRow.group(String(localized: "Allowed sites"), sites.map(\.view))
        // The list only counts in Per Site mode; in the other two it stays
        // visible, so a revoke is still to hand, but steps back.
        grants.alphaValue = mode == .allowPerSite ? 1 : 0.5
        body.card(grants, rows: sites)

        let (rows, fresh) = activityRows(control)
        let log = timeline(String(localized: "Recent activity"), rows.map(\.view))
        body.card(log, rows: rows)
        return fresh
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

    /// The last calls, newest first, each on the rail in its app's colour.
    /// The whole log is `activity.jsonl` in the Control folder.
    private func activityRows(
        _ control: ControlService
    ) -> (rows: [(view: NSView, terms: [String])], fresh: [NSView]) {
        let records = ControlAudit.read(from: control.auditURL, limit: Self.activityShown)
        guard !records.isEmpty else {
            let empty = String(localized: "Nothing yet.")
            return ([(view: SettingsRow.status(empty), terms: [empty])], [])
        }
        let seen = lastSeen
        lastSeen = records.first?.time
        var fresh: [NSView] = []
        let rows = records.enumerated().map { index, record -> (view: NSView, terms: [String]) in
            let time = record.time.formatted(date: .omitted, time: .shortened)
            let subtitle = [record.site, record.decision, record.outcome == "error" ? "failed" : nil]
                .compactMap(\.self).joined(separator: " · ")
            let place: ControlActivityRowView.Place = records.count == 1 ? .only
                : index == 0 ? .first : (index == records.count - 1 ? .last : .middle)
            let row = ControlActivityRowView(
                time: time, title: "\(record.client): \(record.summary)", subtitle: subtitle,
                colour: colour(ofClient: record.client), place: place
            )
            if let seen, record.time > seen {
                fresh.append(row)
                if fresh.count <= Self.beamsAtOnce, let id = satelliteID(ofClient: record.client) { sky.beam(from: id) }
            }
            return (view: row, terms: ["activity", "log", record.client, record.summary])
        }
        return (rows, fresh)
    }

    /// A group like `SettingsRow.group`, without the rules between rows: the
    /// rail already runs between them.
    private func timeline(_ title: String, _ rows: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = Tokens.TypeScale.settingsRow
        header.textColor = Tokens.Text.secondary
        let card = SettingsCardView()
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: Tokens.Metric.chromeGap / 2, left: 0, bottom: Tokens.Metric.chromeGap / 2, right: 0)
        list.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(list)
        let column = NSStackView(views: [header, card])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsMetrics.controlRowGap
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            list.topAnchor.constraint(equalTo: card.topAnchor),
            list.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(equalTo: column.widthAnchor)
        ] + rows.map { $0.widthAnchor.constraint(equalTo: list.widthAnchor) })
        return column
    }

    /// A call that arrived while the pane was open eases into the log rather
    /// than appearing in place of the line above it.
    private func fadeIn(_ row: NSView) {
        guard !Tokens.Motion.reduceMotion else { return }
        row.alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { _ in row.animator().alphaValue = 1 }
    }

    private static let activityShown = 20
    /// A burst of calls lands as a few beams, not a sky full of them.
    private static let beamsAtOnce = 3

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
