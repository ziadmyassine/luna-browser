//
//  HistoryRow.swift
//  Luna
//
//  One visited page as a row: the value it is drawn from, how the time on it is
//  written, and the view itself.
//
//  It is §3.4's shape rather than a new one — the sidebar's tab row, with a
//  favicon, a title, a quieter subtitle and a fill that lifts on hover. The
//  history panel is a view of the tab list; it should look like one.
//

import AppKit

/// One visited page, flattened for display. A value rather than a
/// `HistoryHit` so the row is handed exactly what it draws.
struct HistoryEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    /// Where the page is — the host, or the whole URL when there is no host to
    /// take. Not the time, which is a label of its own; ``HistoryTimestamp``
    /// says why.
    let subtitle: String
    /// When it was last visited, already formatted. See ``HistoryTimestamp``.
    let when: String
    /// The page's host, for the favicon cache (§4.7), which is where the icon
    /// of a page with no open tab is kept.
    let host: String
    /// What choosing the row opens.
    let url: URL
    /// The header of the day it belongs under (§11.3), already formatted.
    /// Entries in a row with the same `day` are one group; empty is no header.
    var day: String = ""
}

/// When a page was last visited, as its row and its day's header write it.
///
/// The header carries the day, so the row carries only the clock. A row once
/// carried both, and host, date and time as one middle-truncated label came
/// out as `"github…:24 PM"` in the 320 pt pop-out.
///
/// Pure and locale-taking, so each branch can be asserted at a fixed date.
enum HistoryTimestamp {

    static func string(for date: Date) -> String { clock.string(from: date) }

    /// The header over a day's pages: Today, Yesterday, the weekday for the
    /// five days before that — inside a week a weekday names one day — and
    /// the date further back, with the year only once it is not this one.
    ///
    /// - Parameter now: today, injectable for the tests.
    static func day(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let daysAgo = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch daysAgo {
        case ...0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        case 2...6: return weekday.string(from: date)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return (sameYear ? fullDate : fullDateAndYear).string(from: date)
        }
    }

    /// `setLocalizedDateFormatFromTemplate`, not a literal format: the template
    /// says which fields, and the locale keeps the order it puts them in.
    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let weekday = formatter(template: "EEEE")
    private static let fullDate = formatter(template: "EEEE d MMMM")
    private static let fullDateAndYear = formatter(template: "EEEE d MMMM y")
}

/// One row of the panel.
@MainActor
final class HistoryRowView: NSView {

    /// A click, with the modifiers held: ⌘ and ⇧ mark rows rather than open
    /// one (§11.3).
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    /// A right-click: the menu for this row, from the list, which knows what
    /// else is marked.
    var onMenu: (() -> NSMenu?)?
    /// The pointer arrived on this row. §9.1's list moves one pill rather than
    /// filling a row, so the row reports and the list decides.
    var onHover: (() -> Void)?

    /// Nil until `configure` has been called. A recycled row exists before it
    /// has anything to say, which is the whole point of recycling it.
    private(set) var entry: HistoryEntry?

    /// This row is the highlighted one. It carries no fill of its own — the
    /// highlight is `HistoryListView`'s single glass pill, exactly as it is in
    /// the Command Bar. All a row does is brighten its text, which is §3.4's
    /// "brighter text on the selected row".
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            applyTokens()
            setAccessibilitySelected(isSelected)
        }
    }

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let when = NSTextField(labelWithString: "")

    /// Built empty and filled afterwards, because `HistoryListView` recycles
    /// these. A row that took its entry in `init` would be a row per entry, and
    /// history has no ceiling on it.
    ///
    /// `translatesAutoresizingMaskIntoConstraints` stays on: an `NSTableView`
    /// positions its cell views by frame, and the constraints below are all
    /// internal to the row, which is a combination AppKit is happy with.
    init() {
        super.init(frame: .zero)

        icon.imageScaling = .scaleProportionallyUpOrDown
        title.lineBreakMode = .byTruncatingTail
        // Tail, not middle: a host is identified by its front, and `github…`
        // is a site where `gi…om` is a shrug.
        subtitle.lineBreakMode = .byTruncatingTail
        when.alignment = .right

        let text = NSStackView(views: [title, subtitle, when])
        text.orientation = .horizontal
        text.alignment = .firstBaseline
        text.spacing = Tokens.Metric.panelInset
        applyTextPriorities()

        let stack = NSStackView(views: [icon, text])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.rowIconGap
        // The row's slack belongs to the text, not to the space after it: the
        // favicon is a fixed 16 pt either way, and a `text` that hugs is a
        // `text` that stops short of the row's trailing edge — which takes the
        // timestamp with it and leaves the column of stamps ragged.
        icon.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        text.setHuggingPriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // `rowInset` is where the pill's edge is, not where the content
        // starts: content at that same number sat flush against the glass and
        // the highlight read as shifted off the row. A second `panelInset` puts
        // it inside the pill, as `CommandBarResultsView` does.
        let inset = Tokens.Metric.rowInset + Tokens.Metric.panelInset
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize)
        ])

        applyTokens()
        // §21.2 / contract rule 4: Increase Contrast is not an appearance on
        // macOS 26.5, so every token colour has to be re-assigned when it flips.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(String(localized: "Reopen this tab"))
    }

    /// What this row is showing now. Everything the row is made of was built
    /// once; this is the part that changes as the row is scrolled back into
    /// use under a different entry.
    func configure(_ entry: HistoryEntry, icon image: NSImage?) {
        self.entry = entry
        icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.image?.isTemplate = image == nil
        title.stringValue = entry.title
        subtitle.stringValue = entry.subtitle
        when.stringValue = entry.when
        setAccessibilityLabel(entry.title)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    /// Who gives way, in a row that is always one label too wide.
    ///
    /// The time never does: it is the shortest of the three, it answers the
    /// question the panel is for, and half a timestamp is a wrong one. The host
    /// yields first (a clipped URL is still a URL) and the title second —
    /// `CommandBarResultsView`'s order with a third column in front of it. One
    /// over `.defaultHigh` rather than `.required`, so a list laid out before
    /// it has a width narrows quietly instead of breaking a constraint.
    ///
    /// Slack goes to the host, the lowest hugger, so the time sits against the
    /// trailing edge and the dates line up down the panel.
    private func applyTextPriorities() {
        let overTitle = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1
        )
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        when.setContentCompressionResistancePriority(overTitle, for: .horizontal)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        when.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    private func applyTokens() {
        title.font = Tokens.TypeScale.sidebarRow
        // Not `sectionLabel`: that is semibold tabular, for a heading, and it
        // came out heavier than the title it was supposed to sit under.
        subtitle.font = Tokens.TypeScale.settingsCaption
        // §1 asks for tabular digits wherever a number is shown, and a column
        // of clock times is the case it was written for.
        when.font = Tokens.TypeScale.rowTimestamp
        title.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        subtitle.textColor = Tokens.Text.tertiary
        when.textColor = Tokens.Text.tertiary
        if icon.image?.isTemplate ?? false {
            icon.contentTintColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    // MARK: - Hover (§6)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }

    /// Swallowed, not ignored: the panel's scrim dismisses on `mouseDown`, and
    /// letting a row's press walk up there would tear the panel down before the
    /// `mouseUp` that was meant to choose this row arrived.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?([])
        return true
    }
}
