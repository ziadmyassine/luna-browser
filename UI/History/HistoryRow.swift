//
//  HistoryRow.swift
//  Luna
//
//  The two pieces §6.4's panel is made of: one archived tab as a row, and the
//  filter above them.
//
//  Both are §3.4's shapes rather than new ones — the row is the sidebar's tab
//  row (favicon, title, a quieter subtitle, a fill that lifts on hover) and the
//  filter is §3.2's URL pill (a `Surface.well` recess with a hairline catching
//  its edge). The history panel is a view of the tab list; it should look like
//  one.
//

import AppKit

/// One archived tab, flattened for display. A value rather than a `Tab` so the
/// row cannot reach back into the session for anything it was not handed.
struct HistoryEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    /// Where the tab was — the host, or the whole URL when there is no host to
    /// take. **Not the time**: the two used to be one string, and see
    /// ``HistoryTimestamp`` for what that cost.
    let subtitle: String
    /// When it was closed, already formatted. See ``HistoryTimestamp``.
    let when: String
    /// The archived tab's host, for the favicon cache. An archived tab has no
    /// live controller and therefore no in-session icon; the on-disk cache is
    /// the only place its icon still exists (§4.7).
    let host: String
    /// Lower-cased title and host, which is what the filter matches on.
    let searchText: String
}

/// When an archived tab was closed, in the width a 320 pt pop-out has for it.
///
/// **A cut date is worse than a coarse one.** The row used to carry
/// `"github.com · Sep 20, 2026 at 12:24 PM"` as one middle-truncated label,
/// and at the panel's width that is what the reader actually got:
/// `"github…:24 PM"` — a host you cannot identify and a time you cannot
/// place, from the one part of the row that was supposed to say *when*. The
/// full date and time measures 135 pt beside a 156 pt title and a 59 pt host in
/// a text column 244 pt wide; there was never room for all three, and the
/// truncation only decided which of them lost.
///
/// So the time is spent where it tells the reader something they do not already
/// know. Today's tabs are the panel's whole business — this is where a tab you
/// closed by accident goes — and for those the day is not in question, so the
/// row gives the clock. Anything older gives the date instead, and the year
/// only once it is not this one. Every case fits, which is the point.
///
/// Pure and locale-taking, so the three branches can be asserted at a fixed
/// date without waiting for a year to turn.
enum HistoryTimestamp {

    /// - Parameter now: today, injectable for the tests.
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock.string(from: date) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return (sameYear ? day : dayAndYear).string(from: date)
    }

    /// `setLocalizedDateFormatFromTemplate`, not a literal format: the template
    /// says *which* fields, and the locale keeps the order it puts them in.
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

    private static let day = formatter(template: "d MMM")
    private static let dayAndYear = formatter(template: "d MMM y")
}

/// One row of the panel.
@MainActor
final class HistoryRowView: NSView {

    var onClick: (() -> Void)?
    /// The pointer arrived on this row. §9.1's list moves one pill rather than
    /// filling a row, so the row reports and the list decides.
    var onHover: (() -> Void)?

    let entry: HistoryEntry

    /// **This row is the highlighted one.** It carries no fill of its own — the
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

    init(entry: HistoryEntry, icon image: NSImage?) {
        self.entry = entry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.image?.isTemplate = image == nil
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = entry.title
        title.lineBreakMode = .byTruncatingTail
        subtitle.stringValue = entry.subtitle
        // Tail, not middle: a host is identified by its front, and `github…`
        // is a site where `gi…om` is a shrug.
        subtitle.lineBreakMode = .byTruncatingTail
        when.stringValue = entry.when
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

        // **`rowInset` is where the pill's edge is, not where the content
        // starts.** The row is the full width of the list and the highlight is
        // inset `rowInset` into it, so content at that same number sits flush
        // against the glass — the favicon touched the pill's left edge while
        // the right end of it ran on empty, and the highlight read as shifted
        // off the row. A second `panelInset` puts the content inside the pill,
        // which is what `CommandBarResultsView` does with the same two numbers.
        let inset = Tokens.Metric.rowInset + Tokens.Metric.panelInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowHeight),
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
        setAccessibilityLabel(entry.title)
        setAccessibilityHelp(String(localized: "Reopen this tab"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    /// **Who gives way, in a row that is always one label too wide.**
    ///
    /// The time never does. It is the shortest of the three, it is the answer
    /// to the question the panel is for, and half a timestamp is not a shorter
    /// timestamp — it is a wrong one. The host yields first (a clipped URL is
    /// still a URL) and the title second, which is `CommandBarResultsView`'s
    /// order with a third column added in front of it.
    ///
    /// One over `.defaultHigh` rather than `.required`: the time outranks the
    /// title without being able to out-argue the row's own width, so a list
    /// laid out before it has been given one narrows quietly instead of
    /// breaking a constraint.
    ///
    /// The hugging priorities are the other half. Slack goes to the lowest,
    /// which is the host — so the time sits against the row's trailing edge and
    /// the dates line up down the panel instead of stepping in and out with the
    /// titles in front of them.
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
        // came out *heavier* than the title it was supposed to sit under.
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
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// §6.4's filter. §3.2's pill shape, because it is the same gesture: a recess
/// in the surface with a hairline on its edge.
@MainActor
final class HistoryFilterField: NSView, NSTextFieldDelegate {

    var onChange: ((String) -> Void)?
    /// `esc` with nothing typed — the panel takes it as "close".
    var onCancel: (() -> Void)?
    /// `↓` / `↑`. The field has focus, so it is where they land.
    var onMoveSelection: ((Int) -> Void)?
    /// `↩` on the highlighted row.
    var onCommit: (() -> Void)?

    private let field = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.urlPill.height),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.pillTextInset),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.pillTextInset),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyTokens()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }

    private func applyTokens() {
        field.font = Tokens.TypeScale.urlPill
        field.textColor = Tokens.Text.primary
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Search history"),
            attributes: [
                .font: Tokens.TypeScale.urlPill,
                .foregroundColor: Tokens.Text.tertiary
            ]
        )
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// Clicking anywhere in the pill puts the caret in the field, not just the
    /// 13 pt of text inside it.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(field) ?? false
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            onMoveSelection?(1)
        case #selector(NSResponder.moveUp(_:)):
            onMoveSelection?(-1)
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
        case #selector(NSResponder.cancelOperation(_:)):
            // The query first, the panel second: `esc` on a filtered list means
            // "show me everything again", and only then "close".
            guard field.stringValue.isEmpty else {
                field.stringValue = ""
                onChange?("")
                return true
            }
            onCancel?()
        default:
            return false
        }
        return true
    }
}
