//
//  Privacy.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.3 — the blocking toggles, the filter-list status
//  block, HTTPS-Only, the per-site exemption list, and §17.7's paragraph.
//
//  The row stack and §2's search come from `SettingsBody` in `General.swift`;
//  the app wiring and the two confirmation dialogs come from `SettingsHost` in
//  `Shell/`.
//

import AppKit
import BrowserKit
import WebKit

// MARK: - §3.3

@MainActor
final class PrivacySection: SettingsSection {

    static let id = "privacy"
    static let title = String(localized: "Privacy & Blocking")
    static let symbolName = "lock.shield"

    private let body = SettingsBody()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let exemptions = NSStackView()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        buildBlocking()
        buildFilterLists()
        buildSites()
        buildSafeBrowsingNote()
        observeStatus()
        Task { await reloadExemptions() }
    }

    // MARK: Rows

    private func buildBlocking() {
        var rows = ContentBlocker.Category.allCases.map(blockingRow)
        rows.append(httpsOnlyRow())
        body.card(String(localized: "Blocking"), rows)
    }

    /// The list behind each toggle is named in the subtitle rather than in a
    /// note: "Block trackers" says what it does, "EasyPrivacy" says what it
    /// does it with, and the second is the one a user searches for.
    private func blockingRow(_ category: ContentBlocker.Category) -> (view: NSView, terms: [String]) {
        let title: String
        let list: String
        switch category {
        case .ads: (title, list) = (String(localized: "Block ads"), "EasyList")
        case .trackers: (title, list) = (String(localized: "Block trackers"), "EasyPrivacy")
        case .annoyances: (title, list) = (String(localized: "Block annoyances"), "Fanboy Annoyance")
        }
        let row = SettingsRow.toggle(
            title, subtitle: list, value: ContentBlocker.shared.isEnabled(category)
        ) { enabled in
            ContentBlocker.shared.setEnabled(enabled, for: category)
        }
        return (row, [title, list, "blocking"])
    }

    private func httpsOnlyRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "HTTPS-Only Mode")
        let subtitle = String(localized: "Upgrade http:// pages, and say so when the upgrade fails")
        let row = SettingsRow.toggle(title, subtitle: subtitle, value: ContentBlocker.shared.isHTTPSOnlyEnabled) { on in
            ContentBlocker.shared.isHTTPSOnlyEnabled = on
        }
        return (row, [title, subtitle, "https", "encryption"])
    }

    private func buildFilterLists() {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.font = Tokens.TypeScale.sidebarRow
        statusLabel.textColor = Tokens.Text.secondary
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = NSButton(title: String(localized: "Refresh Now"), target: self, action: #selector(refreshNow))
        button.bezelStyle = .push
        let accessory = NSStackView(views: [statusLabel, spinner, button])
        accessory.orientation = .horizontal
        accessory.spacing = Tokens.Metric.chromeGap

        let title = String(localized: "Filter lists")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: accessory)
        body.card(nil, [(row, [title, "rules", "refresh", "easylist", "update"])])
        render(ContentBlocker.shared.status)
    }

    private func buildSites() {
        exemptions.orientation = .vertical
        exemptions.alignment = .leading
        exemptions.spacing = Tokens.Metric.rowGap
        let title = String(localized: "Sites with blocking turned off")
        body.card(title, [(exemptions, [title, "exceptions", "allowlist", "per-site"])])
    }

    /// §17.7, and it is required copy rather than a nicety. Luna has no Safe
    /// Browsing service and no plan for one; a privacy section that stays quiet
    /// about that lets the user believe they are protected against something
    /// they are not.
    private func buildSafeBrowsingNote() {
        let text = String(localized: """
        Luna does not check the addresses you visit against a malware or phishing list. \
        No such list is downloaded and nothing about your browsing leaves this Mac. \
        macOS still applies XProtect and Gatekeeper to anything you download and run.
        """)
        body.loose(SettingsRow.note(text), terms: ["malware", "phishing", "safe browsing", "xprotect", "gatekeeper"])

        let clear = String(localized: "Clear all site data")
        let row = SettingsRow.button(clear, action: String(localized: "Clear…"), isDestructive: true) { [weak self] in
            self?.clearSiteData()
        }
        body.card(nil, [(row, [clear, "cookies", "cache", "storage"])])
    }

    // MARK: Filter-list status

    /// `onStatusChange` is a single slot, so the previous observer is chained
    /// rather than dropped — whoever registered first is not ours to break.
    private func observeStatus() {
        let previous = ContentBlocker.shared.onStatusChange
        ContentBlocker.shared.onStatusChange = { [weak self] status in
            previous?(status)
            self?.render(status)
        }
    }

    private func render(_ status: ContentBlocker.Status) {
        switch status {
        case .notReady:
            statusLabel.stringValue = String(localized: "No lists yet — they are fetched, never bundled.")
        case .updating:
            statusLabel.stringValue = String(localized: "Updating…")
        case let .ready(rules, updated):
            let when = updated.formatted(.relative(presentation: .named))
            statusLabel.stringValue = String(localized: "\(rules.formatted()) rules · updated \(when)")
        case let .failed(reason):
            statusLabel.stringValue = String(localized: "Update failed: \(reason)")
        }
        if case .updating = status { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    /// `refresh(force:)` is `async` and does the fetch and the ~1.4 s of parsing
    /// off the main actor, so this returns at once and the spinner carries the
    /// wait. What it cannot do is move the **compile**: `WKContentRuleListStore`
    /// is main-actor API, and compiling the ~186,000 rules across the three
    /// lists stalls the main thread in slices of up to 353 ms. That is the
    /// ceiling of the public API, which is exactly why only this button and the
    /// daily timer ever compile.
    @objc private func refreshNow() {
        Task { await ContentBlocker.shared.refresh(force: true) }
    }

    // MARK: Per-site exemptions

    private func reloadExemptions() async {
        var hosts: [String] = []
        if let store = SettingsHost.store {
            hosts = ((try? await store.blockingExemptions())?.blockingDisabled ?? []).sorted()
        }
        for view in exemptions.arrangedSubviews { view.removeFromSuperview() }
        guard !hosts.isEmpty else {
            let empty = NSTextField(labelWithString: String(localized: "None. Blocking is on everywhere."))
            empty.font = Tokens.TypeScale.sidebarRow
            empty.textColor = Tokens.Text.secondary
            exemptions.addArrangedSubview(empty)
            return
        }
        for host in hosts {
            let remove = NSButton(title: String(localized: "Remove"), target: self, action: #selector(removeHost(_:)))
            remove.bezelStyle = .push
            remove.identifier = NSUserInterfaceItemIdentifier(host)
            exemptions.addArrangedSubview(SettingsRow.accessory(host, subtitle: nil, accessory: remove))
        }
    }

    @objc private func removeHost(_ sender: NSButton) {
        guard let host = sender.identifier?.rawValue else { return }
        ContentBlocker.shared.setDisabled(false, forHost: host)
        Task { await reloadExemptions() }
    }

    // MARK: Clearing

    /// Every store, not just the default one: a Space's cookies live in its own
    /// identified `WKWebsiteDataStore` (§5.1), and "all" has to mean all.
    ///
    /// `removeData(ofTypes:modifiedSince:)` works while the store is in use. It
    /// is `remove(forIdentifier:)` — deleting the store itself, which §3.7's
    /// profile row needs and does not have — that fails against a live web view.
    private func clearSiteData() {
        guard SettingsHost.confirm(
            String(localized: "Clear all site data?"),
            String(localized: """
            Cookies, caches and local storage are deleted for every Space. You will be \
            signed out of sites you are signed in to. This cannot be undone.
            """),
            action: String(localized: "Clear")
        ) else { return }

        var stores: [WKWebsiteDataStore] = [.default()]
        if let session = SettingsHost.session {
            stores += session.spaces
                .compactMap { session.profile(for: $0) }
                .map { session.profileStore.dataStore(for: $0) }
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        Task {
            for store in stores {
                await store.removeData(ofTypes: types, modifiedSince: .distantPast)
            }
        }
    }
}
