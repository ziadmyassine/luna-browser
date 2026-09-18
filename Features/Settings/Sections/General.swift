//
//  General.swift
//  Luna
//
//  §23.1 §3.1, plus the two pieces of scaffolding the other three B sections
//  share — `SettingsBody` and `SettingsNoteHost`. They live here rather than in
//  a fifth file because between them they are ninety lines and one of them is
//  three properties; a `Shared/` directory for that is a directory to maintain.
//
//  **Two of §3.1's four rows ship disabled, and that is a finding rather than a
//  shortcut.** §3.1 lists "On launch" as wired to `general.onLaunch` +
//  `BrowserSession.restored`, and "Confirm before closing" to
//  `general.confirmClose`. Neither key has a *reader*: `AppDelegate` restores
//  unconditionally and `BrowserWindowController` implements no
//  `windowShouldClose`. Writing them anyway would produce exactly the silently
//  dead switch §30.4 forbids, so they render dimmed with the reason, the typed
//  accessors below are published for whoever wires them, and the gap is in the
//  report instead of in the UI.
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
        let terms: [String]
        /// Index into `cards`, or nil for a row that stands on its own.
        let card: Int?
    }

    let view = NSStackView()
    private var entries: [Entry] = []
    private var cards: [NSView] = []

    init() {
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = Tokens.Metric.settingsGroupGap
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    /// One glass-backed card (§1's "grouped control rows"). Each row carries the
    /// labels a search should match it on — its title first, then any word a
    /// user would plausibly type for it.
    func card(_ title: String?, _ rows: [(view: NSView, terms: [String])]) {
        let index = cards.count
        for row in rows {
            entries.append(Entry(view: row.view, terms: row.terms.map { $0.lowercased() }, card: index))
        }
        let card = SettingsRow.group(title, rows.map(\.view))
        cards.append(card)
        add(card)
    }

    /// A standalone row — a note, or the live host below.
    ///
    /// **It sits close to the card above it.** The stack's own spacing is the
    /// gap between one *group* and the next; a sentence explaining the card it
    /// follows, floated out to that distance, reads as the opening line of the
    /// next group instead of as a footnote on the last one.
    func loose(_ child: NSView, terms: [String]) {
        entries.append(Entry(view: child, terms: terms.map { $0.lowercased() }, card: nil))
        if let previous = view.arrangedSubviews.last {
            view.setCustomSpacing(Tokens.Metric.chromeGap, after: previous)
        }
        add(child)
    }

    var searchIndex: [String] { entries.flatMap(\.terms) }

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

/// A `SettingsRow.note` whose text changes while the window is open.
///
/// The declared row API has no mutable note and no subtitle on a button, yet
/// §3.1 wants a *live* default-browser status line and §3.4 wants live
/// validation of the custom engine. Rebuilding the note into a host is the
/// smallest honest answer: one view in the hierarchy, one string to set.
final class SettingsNoteHost: NSView {

    private var text: String?

    func setText(_ next: String) {
        guard next != text else { return }
        text = next
        subviews.forEach { $0.removeFromSuperview() }
        let note = SettingsRow.note(next)
        note.translatesAutoresizingMaskIntoConstraints = false
        addSubview(note)
        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: leadingAnchor),
            note.trailingAnchor.constraint(equalTo: trailingAnchor),
            note.topAnchor.constraint(equalTo: topAnchor),
            note.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - §3.1

@MainActor
final class GeneralSection: NSObject, SettingsSection {

    static let id = "general"
    static let title = "General"
    static let symbolName = "gearshape"

    // MARK: Keys and typed accessors

    /// §3.1's launch behaviour. **Nothing reads this yet** — see the file
    /// header. Published so `AppDelegate` can, in one `switch`.
    enum OnLaunch: String, Sendable, CaseIterable {
        case restoreSession
        case newTab
        case specificSpace

        var title: String {
            switch self {
            case .restoreSession: "Restore last session"
            case .newTab: "New tab"
            case .specificSpace: "Specific Space"
            }
        }
    }

    static let onLaunchKey = "general.onLaunch"
    static let confirmCloseKey = "general.confirmClose"

    static var onLaunch: OnLaunch {
        UserDefaults.standard.string(forKey: onLaunchKey).flatMap(OnLaunch.init(rawValue:)) ?? .restoreSession
    }

    /// Defaults **on**: closing a window full of tabs is the one destructive
    /// thing a browser does by accident, and §3.1 asks for the guard rather
    /// than for the speed.
    static var confirmClose: Bool {
        UserDefaults.standard.object(forKey: confirmCloseKey) as? Bool ?? true
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

    /// The §3.1 status line. Names the *other* browser when it is not Luna —
    /// "Luna is not your default browser" tells the user nothing they can act
    /// on, and the name is what makes the button's effect predictable.
    static var statusLine: String {
        if isDefaultBrowser { return "Luna opens web links from other apps." }
        guard let other = defaultBrowser else { return "macOS has no default browser set for web links." }
        return "\(FileManager.default.displayName(atPath: other.path)) currently opens web links."
    }

    // MARK: Section

    private let body = SettingsBody()
    private let status = SettingsNoteHost()

    var view: NSView { body.view }
    var searchIndex: [String] { body.searchIndex }
    func filter(_ query: String) { body.filter(query) }

    override init() {
        super.init()
        body.card(nil, [
            (defaultBrowserRow(), ["default browser", "set as default", "links"])
        ])
        body.loose(status, terms: ["default browser"])
        body.card("Startup and tabs", [
            (onLaunchRow(), ["on launch", "startup", "restore last session", "new tab"]),
            (autoArchiveRow(), ["auto-archive tabs after", "archive", "idle tabs", "6 hours", "12 hours", "24 hours", "never"]),
            (confirmCloseRow(), ["confirm before closing a window with multiple tabs", "close", "warn"])
        ])
        status.setText(Self.statusLine)
        // The user can change the handler in System Settings while this window
        // is open, and macOS posts nothing when they do — so the status is
        // re-read whenever Luna comes back to the front, which is the moment
        // after they would have done it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func refreshStatus() {
        status.setText(Self.statusLine)
    }

    private func defaultBrowserRow() -> NSView {
        SettingsRow.button(
            "Default browser",
            action: Self.isDefaultBrowser ? "Luna is the default" : "Set as Default",
            isEnabled: !Self.isDefaultBrowser,
            disabledReason: Self.isDefaultBrowser ? "Luna is already the default browser." : nil
        ) { [weak self] in
            self?.setAsDefault()
        }
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

    private func onLaunchRow() -> NSView {
        let options = OnLaunch.allCases
        return SettingsRow.popup(
            "On launch",
            options: options.map(\.title),
            selected: options.firstIndex(of: Self.onLaunch) ?? 0,
            isEnabled: false,
            disabledReason: "Luna always restores the last session; the launch choice is not read yet."
        ) { index in
            UserDefaults.standard.set(options[index].rawValue, forKey: Self.onLaunchKey)
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
            "Auto-archive tabs after",
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

    private func confirmCloseRow() -> NSView {
        SettingsRow.toggle(
            "Confirm before closing a window with multiple tabs",
            value: Self.confirmClose,
            isEnabled: false,
            disabledReason: "Luna's window controller does not ask before closing yet."
        ) { value in
            UserDefaults.standard.set(value, forKey: Self.confirmCloseKey)
        }
    }
}
