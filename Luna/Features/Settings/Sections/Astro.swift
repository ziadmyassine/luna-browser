//
//  Astro.swift
//  Luna
//
//  Astro's page: the agent panel's settings. Which accounts it can run on
//  and signing each in or out — through the tool's own browser sign-in, as
//  the panel does — which one it uses, the keys that show it, and Luna
//  Control, which it cannot work without. The accounts are `AgentCenter`'s,
//  so the page and the panel always agree.
//

import AppKit
import LunaControl

@MainActor
final class AstroSection: SettingsSection {

    static let id = "astro"
    static let title = String(localized: "Astro")
    static let symbolName = "face.smiling"
    static let keywords = ["agent", "ai", "assistant", "claude", "chatgpt", "codex", "openai", "sign in", "login", "rover"]

    private let container = NSView()
    private var body = SettingsBody()
    private var query = ""
    /// Kept across rebuilds, so Astro does not stop mid-blink.
    private let hero = AstroHeroView()
    private let center = AgentCenter.shared
    private var watch: (any NSObjectProtocol)?

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }

    init() {
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
        watch = NotificationCenter.default.addObserver(forName: AgentCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    /// What the page shows, in one value: the panel posts a change for every
    /// word the agent writes, and the page rebuilds only when this moves.
    private var shown: String {
        let accounts = AgentEngine.allCases.map { "\(center.account(for: $0).state)" }
        return accounts.joined(separator: "|") + "|\(AgentEngine.chosen)|\(ControlService.isEnabled)|\(center.blocker == nil)"
    }
    private var built = ""

    private func changed() {
        guard shown != built else { return }
        build()
    }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
    }

    func willAppear() {
        center.checkAccounts()
        build()
    }

    private func build() {
        built = shown
        let body = SettingsBody()
        let chosen = AgentEngine.chosen
        let ready = center.blocker == nil && center.account(for: chosen).state == .signedIn
        hero.show(ready: ready, text: heroLine(ready: ready, engine: chosen))
        body.card(hero, rows: [(view: hero, terms: ["astro", "agent", String(localized: "Your agent in Luna")])])
        body.card(String(localized: "Accounts"), AgentEngine.allCases.map(accountRow))
        body.card(String(localized: "Astro"), [engineRow(chosen), shortcutRow(), controlRow()])
        let privacy = String(localized: """
        Astro runs on your own plan and its limits. Luna starts Claude Code or Codex as you, and your password goes \
        only to the sign-in page in your browser, never through Luna.
        """)
        body.loose(SettingsRow.note(privacy), terms: [privacy, "password", "limits", "plan"])
        body.filter(query)

        self.body.view.removeFromSuperview()
        self.body = body
        container.addSubview(body.view)
        NSLayoutConstraint.activate([
            body.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            body.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            body.view.topAnchor.constraint(equalTo: container.topAnchor),
            body.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func heroLine(ready: Bool, engine: AgentEngine) -> String {
        if !ControlService.isEnabled { return String(localized: "Needs Luna Control") }
        if ready { return String(localized: "Ready on \(engine.name)") }
        return switch center.account(for: engine).state {
        case .unknown: String(localized: "Checking \(engine.name)…")
        case .signingIn: String(localized: "Waiting for your browser…")
        case .signedIn, .signedOut: String(localized: "Sign in to \(engine.name) to start")
        }
    }

    // MARK: - Rows

    private func accountRow(_ engine: AgentEngine) -> (view: NSView, terms: [String]) {
        let account = center.account(for: engine)
        let button = SettingsPushButton(title: "", isDestructive: false)
        var subtitle: String
        switch (engine.executable, account.state) {
        case (nil, _):
            subtitle = String(localized: "\(engine.toolName) isn’t installed. \(engine.installHint)")
            button.isHidden = true
        case (_, .unknown):
            subtitle = String(localized: "Checking…")
            button.isHidden = true
        case (_, .signedIn):
            subtitle = String(localized: "Signed in through \(engine.toolName)")
            button.title = String(localized: "Sign Out…")
            button.onActivate = { [weak self] in self?.signOut(engine) }
        case (_, .signedOut):
            subtitle = String(localized: "Not signed in")
            button.title = String(localized: "Sign In…")
            button.onActivate = { account.startSignIn() }
        case (_, .signingIn):
            subtitle = String(localized: "Finish signing in in your browser")
            button.title = String(localized: "Cancel")
            button.onActivate = { account.cancelSignIn() }
        }
        let row = SettingsRow.accessory(engine.name, subtitle: subtitle, accessory: button)
        return (row, [engine.name, engine.toolName, subtitle, "sign in", "sign out", "login", "account"])
    }

    private func signOut(_ engine: AgentEngine) {
        guard SettingsHost.confirm(
            String(localized: "Sign out of \(engine.name)?"),
            String(localized: """
            This signs \(engine.toolName) out on this Mac, in Terminal as well. Astro can’t use \(engine.name) until you sign in again.
            """),
            action: String(localized: "Sign Out")
        ) else { return }
        center.account(for: engine).signOut()
    }

    private func engineRow(_ chosen: AgentEngine) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Runs on")
        let engines = AgentEngine.allCases
        let row = SettingsRow.segmented(
            title,
            subtitle: String(localized: "New tasks use this. A task keeps the model it started on."),
            options: engines.map(\.name),
            selected: engines.firstIndex(of: chosen) ?? 0
        ) { [weak self] index in self?.center.use(engines[index]) }
        return (row, [title, "model", "claude", "chatgpt"])
    }

    private func shortcutRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Show and hide Astro")
        let keys = KeyBindings.bindings(for: .toggleAgent).first?.display ?? String(localized: "None")
        let label = NSTextField(labelWithString: keys)
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.secondary
        let row = SettingsRow.accessory(title, subtitle: String(localized: "Change it in Shortcuts."), accessory: label)
        return (row, [title, "shortcut", "keys", keys])
    }

    private func controlRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Luna Control")
        let subtitle = String(localized: "Astro’s hands: how it opens tabs, reads pages and clicks.")
        guard ControlService.isEnabled else {
            let row = SettingsRow.button(title, action: String(localized: "Turn On")) { [weak self] in self?.center.turnOnControl() }
            return (row, [title, subtitle, "control", "turn on"])
        }
        let label = NSTextField(labelWithString: String(localized: "On"))
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.secondary
        return (SettingsRow.accessory(title, subtitle: subtitle, accessory: label), [title, subtitle, "control"])
    }
}
