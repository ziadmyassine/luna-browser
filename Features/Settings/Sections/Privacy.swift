//
//  Privacy.swift
//  Luna
//
//  docs/SETTINGS-SPEC.md §3.3 — the blocking toggles, the filter-list status
//  block, HTTPS-Only, and §17.7's paragraph.
//
//  These toggles are what the site menu's switch is an exception to. The
//  sliders glyph on the URL pill answers "block on this site" and can only turn
//  off what is on globally, and there is nowhere else to say which filter lists
//  run at all — so the two surfaces are not duplicates, and deleting these
//  would leave the per-site switch with nothing to switch. The per-site
//  exemption list did move out, and is now only in the menu.
//
//  The row stack and §2's search come from `SettingsBody` in `General.swift`;
//  the app wiring and the confirmation dialog come from `SettingsHost`.
//

import AppKit
import BrowserKit
import WebKit

// MARK: - §3.3

@MainActor
final class PrivacySection: SettingsSection {

    static let id = "privacy"
    static let title = String(localized: "Privacy & Passwords")
    static let symbolName = "lock.shield"
    static let keywords = ["cookies", "trackers", "blocking", "https only", "ads", "clear data", "passwords"]
        + PasswordsSection.keywords

    private let body = SettingsBody()
    private let passwords = PasswordsSection()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    init() {
        buildBlocking()
        passwords.add(to: body)
        buildClearing()
        observeStatus()
    }

    // MARK: Rows

    /// The switches and the lists they read from, in one card: the status
    /// line is what tells you the switches above it are doing anything.
    private func buildBlocking() {
        var rows = ContentBlocker.Category.allCases.map(blockingRow)
        rows.append(httpsOnlyRow())
        rows.append(filterListsRow())
        body.card(String(localized: "Blocking"), rows)
    }

    /// The list behind each toggle is named in the subtitle rather than in a
    /// note: "Block trackers" says what it does, "EasyPrivacy" says what it
    /// does it with, and the second is the one a user searches for.
    private func blockingRow(_ category: ContentBlocker.Category) -> (view: NSView, terms: [String]) {
        let title: String
        let list: String
        switch category {
        // §17.2: the ads toggle carries YouTube's in-player ads too, and the
        // subtitle says so because the alternative is what prompts the bug
        // report: a switch that reads "Block ads", is on, and leaves the pre-roll
        // playing. EasyList genuinely cannot do that one: the ad and the video
        // arrive on the same host, in the same `MediaSource`, scheduled by a
        // field inside the same JSON as the video itself.
        case .ads: (title, list) = (String(localized: "Block ads"), "EasyList, plus YouTube's in-player ads")
        case .trackers: (title, list) = (String(localized: "Block trackers"), "EasyPrivacy")
        case .annoyances: (title, list) = (String(localized: "Block annoyances"), "Fanboy Annoyance")
        }
        let row = SettingsRow.toggle(
            title, subtitle: list, value: ContentBlocker.shared.isEnabled(category)
        ) { enabled in
            ContentBlocker.shared.setEnabled(enabled, for: category)
        }
        var terms = [title, list, "blocking"]
        if category == .ads { terms += ["youtube", "video ads", "pre-roll", "mid-roll"] }
        return (row, terms)
    }

    private func httpsOnlyRow() -> (view: NSView, terms: [String]) {
        let title = String(localized: "HTTPS-Only Mode")
        let subtitle = String(localized: "Upgrade http:// pages, and say so when the upgrade fails")
        let row = SettingsRow.toggle(title, subtitle: subtitle, value: ContentBlocker.shared.isHTTPSOnlyEnabled) { on in
            ContentBlocker.shared.isHTTPSOnlyEnabled = on
        }
        return (row, [title, subtitle, "https", "encryption"])
    }

    private func filterListsRow() -> (view: NSView, terms: [String]) {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.font = Tokens.TypeScale.sidebarRow
        statusLabel.textColor = Tokens.Text.secondary
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = SettingsPushButton(title: String(localized: "Refresh Now"), isDestructive: false)
        button.target = self
        button.action = #selector(refreshNow)
        let accessory = NSStackView(views: [statusLabel, spinner, button])
        accessory.orientation = .horizontal
        accessory.spacing = Tokens.Metric.chromeGap

        let title = String(localized: "Filter lists")
        let row = SettingsRow.accessory(title, subtitle: nil, accessory: accessory)
        render(ContentBlocker.shared.status)
        // The search terms carry what a three-sentence signpost used to say in
        // prose: someone hunting for the exemption list types "allowlist" or
        // "per-site", and §2's search brings them to the row the menu switches.
        return (row, [title, "rules", "refresh", "easylist", "update", "exceptions", "allowlist", "per-site"])
    }

    /// Last on the page, and on its own: the one row here that signs you out
    /// of everything.
    private func buildClearing() {
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
    /// wait. What it cannot do is move the compile: `WKContentRuleListStore`
    /// is main-actor API, and compiling the ~186,000 rules across the three
    /// lists stalls the main thread in slices of up to 353 ms. That is the
    /// ceiling of the public API, which is exactly why only this button and the
    /// daily timer ever compile.
    @objc private func refreshNow() {
        Task { await ContentBlocker.shared.refresh(force: true) }
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
            stores += session.spaces.map { session.profileStore.dataStore(for: $0) }
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        Task {
            for store in stores {
                await store.removeData(ofTypes: types, modifiedSince: .distantPast)
            }
        }
    }
}
