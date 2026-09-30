//
//  About.swift
//  Luna
//
//  SETTINGS-SPEC §3.11: what this Luna is, and whether there is a newer one.
//
//  The app's icon, name and version at the head, then one card: when Luna
//  last looked for an update and a button to look now, the switch that lets
//  it install on its own, and — when there is one — the newer build with the
//  one thing left to do about it. The card is rebuilt whenever the updater
//  says anything, because every row in it is a sentence about its state.
//

import AppKit

@MainActor
final class AboutSection: SettingsSection {

    static let id = "about"
    static let title = String(localized: "About")
    static let symbolName = "info.circle"
    static let keywords = ["about", "version", "update", "updates", "check for updates", "install", "release"]

    private let container = NSView()
    private var body = SettingsBody()
    private let updater = Updater.shared

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        container.translatesAutoresizingMaskIntoConstraints = false
        build()
        NotificationCenter.default.addObserver(
            forName: Updater.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.build() } }
    }

    private func build() {
        body = SettingsBody()
        body.heading(AboutHeader(), terms: ["luna", "version", Updater.version.description])
        var rows = [checkRow(), installRow()]
        if let release = releaseRow() { rows.append(release) }
        body.card(nil, rows)
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

    // MARK: - Rows

    private func checkRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Updates")
        let button = SettingsPushButton(title: String(localized: "Check Now"), isDestructive: false)
        button.onActivate = { [weak self] in self?.updater.check() }
        button.isEnabled = updater.stage != .checking
        let subtitle = Self.checkLine(stage: updater.stage, lastChecked: updater.lastChecked)
        let row = SettingsRowView(title: title, subtitle: subtitle, control: button, isEnabled: true, disabledReason: nil)
        return (row, [title, "check now", "check for updates"])
    }

    private func installRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Install updates on their own")
        let subtitle = updater.canInstall
            ? String(localized: "Off, Luna still looks once a day and tells you, and installs only when you press Install")
            : String(localized: "This copy of Luna was built on this Mac, so it only tells you when a new one is out")
        let row = SettingsRow.toggle(
            title,
            subtitle: subtitle,
            value: updater.installsOnItsOwn,
            isEnabled: updater.canInstall,
            disabledReason: updater.canInstall ? nil : subtitle
        ) { [weak self] on in self?.updater.installsOnItsOwn = on }
        return (row, [title, "automatic updates", "install automatically"])
    }

    /// The newer build and the one thing left to do about it, or nil when
    /// there is none.
    private func releaseRow() -> (view: NSView, terms: [String])? {
        let release: UpdateRelease
        let subtitle: String?
        let action: String
        let run: () -> Void
        switch updater.stage {
        case let .available(found) where updater.canInstall:
            (release, subtitle, action) = (found, found.notes, String(localized: "Install"))
            run = { [weak self] in self?.updater.install(found) }
        case let .available(found), let .failed(found?, _):
            let reason: String? = if case let .failed(_, why) = updater.stage { why } else { found.notes }
            (release, subtitle, action) = (found, reason, String(localized: "Download"))
            run = { [weak self] in self?.updater.openReleasePage(found) }
        case let .installing(found):
            let working = String(localized: "Downloading and checking…")
            (release, subtitle, action) = (found, working, String(localized: "Install"))
            run = {}
        case let .ready(found):
            let ready = String(localized: "Ready. It opens the next time you start Luna.")
            (release, subtitle, action) = (found, ready, String(localized: "Restart"))
            run = { [weak self] in self?.updater.relaunch() }
        case .idle, .checking, .current, .failed(nil, _):
            return nil
        }
        let title = String(localized: "Luna \(release.version.description)")
        let button = SettingsPushButton(title: action, isDestructive: false)
        button.onActivate = run
        if case .installing = updater.stage { button.isEnabled = false }
        let row = SettingsRowView(title: title, subtitle: subtitle, control: button, isEnabled: true, disabledReason: nil)
        return (row, [title, action])
    }

    /// The Updates row's second line: what the updater is doing, or when it
    /// last looked. Pure, so each wording can be asserted.
    static func checkLine(stage: Updater.Stage, lastChecked: Date?, now: Date = Date()) -> String {
        switch stage {
        case .checking:
            return String(localized: "Checking…")
        case let .failed(nil, why):
            return why
        case .current:
            return String(localized: "Luna is up to date. Checked once a day on its own.")
        case .idle, .available, .installing, .ready, .failed:
            guard let lastChecked else { return String(localized: "Checked once a day on its own") }
            let ago = RelativeDateTimeFormatter().localizedString(for: lastChecked, relativeTo: now)
            return String(localized: "Checked once a day on its own. Last checked \(ago).")
        }
    }
}

/// The head of the section: the icon, the name, and which version this is.
@MainActor
final class AboutHeader: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: String(localized: "Luna"))
        name.font = Tokens.TypeScale.settingsHeading
        name.textColor = Tokens.Text.primary
        let build = Updater.build.isEmpty ? "" : " (\(Updater.build))"
        let version = NSTextField(labelWithString: String(localized: "Version \(Updater.version.description)\(build)"))
        version.font = Tokens.TypeScale.settingsRow
        version.textColor = Tokens.Text.secondary
        let words = NSStackView(views: [name, version])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = Tokens.Metric.rowGap
        let row = NSStackView(views: [icon, words])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Tokens.Metric.chromeGapWide
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let side = Tokens.Metric.aboutIcon
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: side),
            icon.heightAnchor.constraint(equalToConstant: side),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Luna, \(version.stringValue)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }
}
