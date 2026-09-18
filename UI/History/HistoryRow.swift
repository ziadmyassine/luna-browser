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
    let subtitle: String
    /// The archived tab's host, for the favicon cache. An archived tab has no
    /// live controller and therefore no in-session icon; the on-disk cache is
    /// the only place its icon still exists (§4.7).
    let host: String
    /// Lower-cased title and host, which is what the filter matches on.
    let searchText: String
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
        subtitle.lineBreakMode = .byTruncatingMiddle

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .horizontal
        text.alignment = .firstBaseline
        text.spacing = Tokens.Metric.panelInset
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, text])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Tokens.Metric.rowIconGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.rowInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.rowInset),
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

    private func applyTokens() {
        title.font = Tokens.TypeScale.sidebarRow
        // Not `sectionLabel`: that is semibold tabular, for a heading, and it
        // came out *heavier* than the title it was supposed to sit under.
        subtitle.font = Tokens.TypeScale.settingsCaption
        title.textColor = isSelected ? Tokens.Text.primary : Tokens.Text.secondary
        subtitle.textColor = Tokens.Text.tertiary
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
