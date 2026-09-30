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
    private var hero: AccountHeroView?
    private var card: AccountSyncCard?
    /// Whether the page was built for the signed build. The one change that
    /// rebuilds it: the iCloud data card's rows fix their enabled state when
    /// made (`SettingsRowView`). Anything else updates in place.
    private var builtSigned: Bool?
    /// Shown only while Safari's bookmarks cannot be written for want of Full
    /// Disk Access.
    private var safariAccess: NSView?
    private var safariObserver: NSObjectProtocol?

    convenience init() {
        self.init(sync: .shared)
    }

    init(sync: SyncSettings, confirm: @escaping Confirm = SettingsHost.confirm) {
        self.sync = sync
        self.confirm = confirm
        view.translatesAutoresizingMaskIntoConstraints = false
        build()
        observer = NotificationCenter.default.addObserver(forName: SyncSettings.didChange, object: sync, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncChanged() }
        }
        safariObserver = NotificationCenter.default.addObserver(
            forName: SafariFavorites.didChange, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSafariAccess() }
        }
    }

    var searchIndex: [String] { body.searchIndex }

    func filter(_ query: String) {
        self.query = query
        body.filter(query)
        showSafariAccess()
    }

    /// "Synced 2 minutes ago" goes stale while the window is closed.
    func willAppear() { syncChanged() }

    /// Rebuilding the body swapped the switch for a new one while it was still
    /// sliding — twice per flip, once for the zones and once for the status —
    /// and the flip stuttered. So a change updates what is on the page.
    private func syncChanged() {
        let signed = sync.status != .needsSignedBuild
        guard signed == builtSigned, let hero, let card else { return build() }
        hero.isOn = sync.isOn
        card.update()
        body.setTerms([String(localized: "Sync Now"), "fetch", "refresh", sync.status.line()], for: card.footer)
    }

    // MARK: Rows

    /// The page draws its own head (`AccountHeroView`), so the picture that
    /// opens it is the one the sidebar's account row carries.
    private func build() {
        let body = SettingsBody()
        let hero = AccountHeroView(isOn: sync.isOn)
        body.card(hero, rows: [])
        let card = AccountSyncCard(sync: sync)
        self.hero = hero
        self.card = card
        builtSigned = sync.status != .needsSignedBuild
        let zones = zip(SyncZone.switched, card.zoneRows).map { zone, row in (view: row as NSView, terms: [zone.title]) }
        body.card(
            SettingsRow.group(String(localized: "Sync"), [card]),
            rows: [(card.header, [String(localized: "Sync with iCloud"), "icloud", "sync", "status"])]
                + zones
                + [(card.footer, [String(localized: "Sync Now"), "fetch", "refresh", sync.status.line()])]
        )
        body.loose(
            AccountSyncCard.cookieNote(Self.cookieLine),
            terms: [Self.cookieLine, "cookies", "logins", "passwords"]
        )
        body.card(String(localized: "Safari"), [safariRow()])
        let access = safariAccessNote()
        body.loose(access, terms: ["full disk access", "safari", "privacy"])
        safariAccess = access
        body.card(String(localized: "iCloud data"), [manageRow(), removeRow()])
        body.filter(query)
        showSafariAccess()

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

    /// docs/SAFARI-FAVORITES.md: the pinned tabs, as bookmarks in Safari's
    /// Favorites that Safari's own iCloud sync takes to the iPhone.
    private func safariRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Show pinned tabs in Safari’s Favorites")
        let row = SettingsRow.toggle(title, value: SafariFavorites.shared.isOn) { on in SafariFavorites.shared.isOn = on }
        return (row, [title, "safari", "iphone", "favorites", "bookmarks", "pinned"])
    }

    private func safariAccessNote() -> NSView {
        let open = SettingsPushButton(title: String(localized: "Open Privacy Settings…"), isDestructive: false)
        open.onActivate = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
        return SettingsRow.heading(String(localized: "Turn on Full Disk Access for Luna so it can reach Safari."), accessory: open)
    }

    /// Only while the switch is on and Full Disk Access is what stands in the way.
    private func showSafariAccess() {
        guard let safariAccess else { return }
        let needed = SafariFavorites.shared.isOn && SafariFavorites.shared.status == .needsAccess
        let needle = query.lowercased()
        let matches = needle.isEmpty || ["full disk access", "safari", "privacy"].contains { $0.contains(needle) }
        safariAccess.isHidden = !needed || !matches
    }

    private func manageRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "Manage iCloud storage")
        let row = SettingsRow.button(title, action: String(localized: "Open…")) {
            // Apple Account in System Settings, where iCloud's storage is.
            if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
                NSWorkspace.shared.open(url)
            }
        }
        return (row, [title, "storage", "apple account"])
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

    /// The five with a check of their own on the Sync card; `meta` comes with
    /// any of them. The master switch turns all five on.
    static let switched: [SyncZone] = [.spaces, .sites, .settings, .history, .devices]
}
