//
//  Account.swift
//  Luna
//
//  The iCloud page the account row opens (docs/SYNC-PLAN.md §5), and
//  `SyncSettings`, the one thing it and the row know about sync. The page
//  is not in `SettingsSectionRegistry.all`: it has no ⌘-number and no line in
//  the list.
//

import AppKit
import BrowserKit

/// What Settings shows of sync and the four things it can ask of it.
///
/// Closures rather than the coordinator itself: constructing a `CKSyncEngine`
/// without the iCloud entitlement crashes, so the page is built and tested
/// against these, and the app points them at `SyncCoordinator`. Until it does,
/// the status is the unsigned build's and every switch is disabled.
@MainActor
final class SyncSettings {

    static let shared = SyncSettings()

    /// Posted with the instance as its object whenever `status` or `zones` changes.
    static let didChange = Notification.Name("luna.syncSettings.didChange")

    var status = SyncStatus.needsSignedBuild { didSet { changed() } }
    /// The zones that are on; empty while sync is off (`syncZones`).
    var zones: Set<SyncZone> = [] { didSet { changed() } }

    /// The master switch.
    var setEnabled: (Bool) -> Void = { _ in }
    var setZone: (SyncZone, Bool) -> Void = { _, _ in }
    /// Fetch, then send.
    var syncNow: () -> Void = {}
    /// Delete every zone, wipe this Mac's sync state and turn sync off.
    var removeAll: () -> Void = {}

    var isOn: Bool { !zones.isEmpty }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

@MainActor
final class AccountSection: SettingsSection {

    static let id = "icloud"
    static let title = String(localized: "iCloud")
    static let symbolName = "icloud"
    static let keywords = ["sync", "icloud", "account", "other macs"]

    static let cookieLine = String(localized: "Cookies, logins and website data stay on this Mac.")

    typealias Confirm = @MainActor (_ message: String, _ informative: String, _ action: String) -> Bool

    /// The body is rebuilt on every change, because a row's enabled state is
    /// fixed when it is made (`SettingsRowView`); the view the window holds
    /// stays put around it.
    let view = NSView()
    private var body = SettingsBody()
    private var query = ""
    private let sync: SyncSettings
    private let confirm: Confirm
    private var observer: NSObjectProtocol?

    convenience init() {
        self.init(sync: .shared)
    }

    init(sync: SyncSettings, confirm: @escaping Confirm = SettingsHost.confirm) {
        self.sync = sync
        self.confirm = confirm
        view.translatesAutoresizingMaskIntoConstraints = false
        build()
        observer = NotificationCenter.default.addObserver(forName: SyncSettings.didChange, object: sync, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.build() }
        }
    }

    var searchIndex: [String] { body.searchIndex }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
    }

    /// "Synced 2 minutes ago" goes stale while the window is closed.
    func willAppear() { build() }

    // MARK: Rows

    private func build() {
        let body = SettingsBody()
        body.card(nil, [syncSwitch()])
        body.card(String(localized: "Sync"), SyncZone.switched.map(zoneRow))
        body.loose(SettingsRow.note(Self.cookieLine), terms: [Self.cookieLine, "cookies", "logins", "passwords"])
        body.card(nil, [syncNowRow(), removeRow()])
        body.filter(query)

        self.body.view.removeFromSuperview()
        self.body = body
        view.addSubview(body.view)
        NSLayoutConstraint.activate([
            body.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.view.topAnchor.constraint(equalTo: view.topAnchor),
            body.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// The status line is the switch's second line, and when the switch is
    /// disabled it is the reason instead: said once either way.
    private func syncSwitch() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Sync with iCloud")
        let line = sync.status.line()
        let available = sync.status != .needsSignedBuild
        let row = SettingsRow.toggle(
            title,
            subtitle: available ? line : nil,
            value: sync.isOn,
            isEnabled: available,
            disabledReason: line
        ) { [sync] on in sync.setEnabled(on) }
        return (row, [title, "icloud", "sync", "status"])
    }

    private func zoneRow(_ zone: SyncZone) -> (view: NSView, terms: [String]) {
        let title = zone.title
        let needsSpaces = zone == .history && !sync.zones.contains(.spaces)
        let row = SettingsRow.toggle(
            title,
            value: sync.zones.contains(zone) && !needsSpaces,
            isEnabled: sync.isOn && !needsSpaces,
            disabledReason: sync.isOn
                ? String(localized: "Needs Spaces, tabs and Favorites.")
                : String(localized: "Turn on Sync with iCloud first.")
        ) { [sync] on in sync.setZone(zone, on) }
        return (row, [title])
    }

    private func syncNowRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Sync Now")
        let row = SettingsRow.button(
            String(localized: "Fetch and send changes"),
            action: title,
            isEnabled: sync.isOn,
            disabledReason: String(localized: "Turn on Sync with iCloud first.")
        ) { [sync] in sync.syncNow() }
        return (row, [title, "fetch", "refresh"])
    }

    private func removeRow() -> (view: NSView, terms: [String]) {
        let action = String(localized: "Remove Luna Data from iCloud…")
        let row = SettingsRow.button(
            String(localized: "Delete what Luna keeps in iCloud"),
            action: action,
            isDestructive: true,
            isEnabled: sync.status != .needsSignedBuild,
            disabledReason: sync.status.line()
        ) { [weak self] in self?.remove() }
        return (row, [action, "delete", "remove"])
    }

    private func remove() {
        guard confirm(
            String(localized: "Remove Luna's data from iCloud?"),
            String(localized: """
            Your Spaces, tabs, settings and history are deleted from iCloud and sync turns off on this \
            Mac. What is on this Mac stays. Other Macs keep their copy and stop syncing.
            """),
            String(localized: "Remove")
        ) else { return }
        sync.removeAll()
    }
}

extension SyncZone {

    /// The five with a switch of their own; `meta` comes with any of them. The
    /// master switch turns all five on.
    static let switched: [SyncZone] = [.spaces, .sites, .settings, .history, .devices]
}

private extension SyncZone {

    var title: String {
        switch self {
        case .spaces: String(localized: "Spaces, tabs and Favorites")
        case .sites: String(localized: "Site settings")
        case .settings: String(localized: "Settings and shortcuts")
        case .history: String(localized: "Typed history")
        case .devices: String(localized: "Tabs on other Macs")
        case .meta: ""
        }
    }
}
