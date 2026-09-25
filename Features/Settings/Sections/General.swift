//
//  General.swift
//  Luna
//
//  §23.1 §3.1, plus `SettingsBody` — the row stack the other three B sections
//  share. It lives here rather than in a fifth file because it is fifty lines;
//  a `Shared/` directory for that is a directory to maintain.
//
//  The page also carries Search, Downloads and Advanced as groups
//  (`SettingsGroup`): each was a page of one card. Only rows that work are on
//  it; a setting nothing reads is not shown.
//

import AppKit
import BrowserKit

// MARK: - Shared scaffolding

/// A section's stack of `SettingsRow` views, plus the label index §2's search
/// needs.
///
/// `SettingsRow` hands back opaque `NSView`s, so nothing downstream can ask a
/// row what it is called. The labels are therefore recorded as the rows are
/// added, which is the only moment they are known — and it makes `filter(_:)`
/// the same three lines in all four sections instead of four guesses.
@MainActor
final class SettingsBody {

    private struct Entry {
        let view: NSView
        var terms: [String]
        /// Index into `cards`, or nil for a row that stands on its own.
        let card: Int?
    }

    let view = NSStackView()
    private var entries: [Entry] = []
    private var cards: [NSView] = []
    /// Whether the last thing added was a card in a run — see `install`.
    private var listRun = false

    init() {
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = Tokens.Metric.settingsGroupGap
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    /// One glass-backed card (§1's "grouped control rows"). Each row carries the
    /// labels a search should match it on — its title first, then any word a
    /// user would plausibly type for it.
    /// `inList` marks one of a run of cards that are the same kind of thing,
    /// which sit `settingsListGap` apart rather than a group's distance.
    func card(_ title: String?, _ rows: [(view: NSView, terms: [String])], inList: Bool = false) {
        install(SettingsRow.group(title, rows.map(\.view)), rows: rows, inList: inList)
    }

    /// A card the section built for itself, with its rows named separately so
    /// §2's search can still empty it.
    ///
    /// The one caller is §3.7's Space card, which is headed by the Space's own
    /// gradient rather than by a line of type — see `SpaceCardView`. Everything
    /// downstream of this point treats it like any other card: the rows hide
    /// one by one as the query narrows, and the card goes when the last of them
    /// does.
    func card(_ made: NSView, rows: [(view: NSView, terms: [String])], inList: Bool = false) {
        install(made, rows: rows, inList: inList)
    }

    /// A heading the cards under it belong to — `SettingsRow.heading`.
    ///
    /// The stack's own spacing is the gap between one group and the next, and
    /// a heading floated out to that distance is a heading for nothing. The
    /// cards that follow sit a card's distance below it instead.
    func heading(_ child: NSView, terms: [String]) {
        entries.append(Entry(view: child, terms: terms.map { $0.lowercased() }, card: nil))
        add(child)
        view.setCustomSpacing(Tokens.Metric.chromeGap, after: child)
        listRun = false
    }

    private func install(_ card: NSView, rows: [(view: NSView, terms: [String])], inList: Bool) {
        // The gap belongs to the pair, so it is set when the second of them
        // arrives: a run's first card is still a group's distance from
        // whatever it follows.
        if inList, listRun, let previous = view.arrangedSubviews.last {
            view.setCustomSpacing(Tokens.Metric.settingsListGap, after: previous)
        }
        listRun = inList
        let index = cards.count
        for row in rows {
            entries.append(Entry(view: row.view, terms: row.terms.map { $0.lowercased() }, card: index))
        }
        cards.append(card)
        add(card)
    }

    /// A standalone row — a note, or the live host below.
    ///
    /// It sits close to the card above it. The stack's own spacing is the
    /// gap between one group and the next; a sentence explaining the card it
    /// follows, floated out to that distance, reads as the opening line of the
    /// next group instead of as a footnote on the last one.
    func loose(_ child: NSView, terms: [String]) {
        entries.append(Entry(view: child, terms: terms.map { $0.lowercased() }, card: nil))
        if let previous = view.arrangedSubviews.last {
            view.setCustomSpacing(Tokens.Metric.chromeGap, after: previous)
        }
        add(child)
        listRun = false
    }

    var searchIndex: [String] { entries.flatMap(\.terms) }

    /// New labels for a row updated in place rather than rebuilt.
    func setTerms(_ terms: [String], for view: NSView) {
        guard let index = entries.firstIndex(where: { $0.view === view }) else { return }
        entries[index].terms = terms.map { $0.lowercased() }
    }

    /// §2: hide the rows that do not match, and the card once none of its rows
    /// do. An empty query restores everything.
    func filter(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var matched = [Bool](repeating: needle.isEmpty, count: cards.count)
        for entry in entries {
            let shown = needle.isEmpty || entry.terms.contains { $0.contains(needle) }
            entry.view.isHidden = !shown
            if shown, let card = entry.card { matched[card] = true }
        }
        for (index, card) in cards.enumerated() { card.isHidden = !matched[index] }
    }

    private func add(_ child: NSView) {
        view.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }
}

// MARK: - §3.1

@MainActor
final class GeneralSection: NSObject, SettingsSection {

    static let id = "general"
    static let title = String(localized: "General")
    static let symbolName = "gearshape"
    /// Its own words and its three groups': their names and their keywords,
    /// so typing "downloads" in the Command Bar still finds where Downloads is.
    static let keywords = ["startup", "search", "downloads", "advanced"]
        + SearchSection.keywords + DownloadsSection.keywords + AdvancedSection.keywords

    // MARK: Keys and typed accessors

    static let confirmQuitKey = "general.confirmQuit"

    /// Defaults on, and read:
    /// `AppDelegate.applicationShouldTerminate` puts `QuitSheetView` up. ⌘Q is
    /// next to ⌘W and takes every window with it, so the guard is the default
    /// and the sheet's own third answer is how it comes off — a preference you
    /// can only turn off from a dialog is a trap, so it is also here.
    static var confirmQuit: Bool {
        UserDefaults.standard.object(forKey: confirmQuitKey) as? Bool ?? true
    }

    // MARK: Default browser

    /// Any `https` URL resolves the handler; the host is never contacted.
    private static let probe = URL(string: "https://example.com")!

    static var defaultBrowser: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    static var isDefaultBrowser: Bool {
        guard let current = defaultBrowser else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    // MARK: Section

    private let container = NSView()
    private var body = SettingsBody()
    /// Owned rather than built by `SettingsRow.button`, because it is the one
    /// control in the pane whose title changes while the window is open.
    private let setDefault = SettingsPushButton(title: "", isDestructive: false)
    private let search = SearchSection()
    private let downloads = DownloadsSection()
    private let advanced = AdvancedSection()

    var view: NSView { container }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    override init() {
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        advanced.onRestore = { [weak self] in self?.build() }
        build()
        // The user can change the handler in System Settings while this window
        // is open, and macOS posts nothing when they do — so it is re-read
        // whenever Luna comes back to the front, which is the moment after they
        // would have done it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Rebuilt whole after Restore, since every group's values just changed.
    private func build() {
        body = SettingsBody()
        body.card(nil, [
            (defaultBrowserRow(), ["default browser", "set as default", "links"])
        ])
        body.card(String(localized: "Startup"), [
            (
                autoArchiveRow(),
                ["move idle tabs to history after", "history", "archive", "idle tabs", "6 hours", "12 hours", "24 hours", "never"]
            ),
            (confirmQuitRow(), ["ask before quitting luna", "quit", "confirm", "command q", "warn"])
        ])
        for group in [search, downloads, advanced] as [any SettingsGroup] {
            group.add(to: body)
        }
        refreshStatus()

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

    /// The button is the status: "Set as Default" means Luna is not, and a
    /// dimmed "Luna is the default" means it is. A sentence underneath naming
    /// whichever other browser holds the handler said nothing the user could
    /// act on from here, and it was the one line in §3.1 that went stale.
    @objc private func refreshStatus() {
        let isDefault = Self.isDefaultBrowser
        setDefault.title = isDefault ? String(localized: "Luna is the default") : String(localized: "Make Luna Default")
        setDefault.isEnabled = !isDefault
    }

    private func defaultBrowserRow() -> NSView {
        setDefault.onActivate = { [weak self] in self?.setAsDefault() }
        return SettingsRow.accessory("Default browser", subtitle: nil, accessory: setDefault)
    }

    /// Both schemes, because a handler for `https` alone still leaves plain
    /// `http` links opening elsewhere. macOS shows its own confirmation sheet;
    /// Luna must not draw a second one.
    private func setAsDefault() {
        let bundle = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: "https") { _ in
            // Back on the main actor before the second call: `NSWorkspace` is
            // not `Sendable`, so it is fetched again here rather than captured.
            Task { @MainActor in
                NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: "http") { _ in
                    Task { @MainActor in self.refreshStatus() }
                }
            }
        }
    }

    /// The one §3.1 row that is wired end to end today: `BrowserSession`'s
    /// lifecycle sweep re-reads `luna.autoArchiveHours` from defaults on every
    /// pass, so a change here takes effect on the next sweep with nothing else
    /// to notify. The key keeps its `luna.` prefix (§6, recorded as debt).
    private func autoArchiveRow() -> NSView {
        let choices = AutoArchive.choices
        let current = TabLifecycle.autoArchiveHours
        return SettingsRow.popup(
            "Move idle tabs to History after",
            options: choices.map(Self.hoursTitle),
            selected: choices.firstIndex(of: current) ?? choices.firstIndex(of: AutoArchive.defaultHours) ?? 0
        ) { index in
            UserDefaults.standard.set(choices[index], forKey: TabLifecycle.autoArchiveHoursKey)
        }
    }

    /// `AutoArchive` spells "never" as 0 hours (§6.3).
    static func hoursTitle(_ hours: Double) -> String {
        hours > 0 ? "\(Int(hours)) hours" : "Never"
    }

    /// Read on every ⌘Q.
    private func confirmQuitRow() -> NSView {
        SettingsRow.toggle(
            "Ask before quitting Luna",
            value: Self.confirmQuit
        ) { value in
            UserDefaults.standard.set(value, forKey: Self.confirmQuitKey)
        }
    }
}
