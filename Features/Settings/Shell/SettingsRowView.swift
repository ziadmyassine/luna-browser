//
//  SettingsRowView.swift
//  Luna
//
//  The three views every §4 widget is made of: a control row, a glass-backed
//  card of rows, and a paragraph of explanation. `SettingsRow` is the factory;
//  this file is what it builds.
//
//  **The disabled row is the reason this is a custom view rather than a stack
//  of `NSControl`s.** §4 requires a disabled row to be "dimmed, still focusable,
//  and still read by VoiceOver, with its reason as the accessibility help", and
//  a disabled `NSControl` is none of those things — AppKit drops it out of the
//  key-view loop and VoiceOver skips straight past it. So the *control* is
//  disabled (it must not be operable) while the *row* takes over as the
//  focusable, labelled, helped accessibility element. §30.4: a control nobody
//  can explain is worse than a missing one.
//

import AppKit

/// One control row: a title, an optional subtitle, an optional control, and —
/// when it is disabled — the one-line reason §3 requires.
@MainActor
final class SettingsRowView: NSView {

    /// The labels §2's search matches this row on, lowercased.
    let searchTerms: [String]

    /// Closure bridges for the row's control. AppKit targets are weak, so
    /// without this the row's `onChange` would be deallocated before its first
    /// click.
    private var keepAlive: [AnyObject] = []

    private let titleLabel: NSTextField
    private let rowIsEnabled: Bool
    private let plainTitle: String

    init(
        title: String,
        subtitle: String?,
        control: NSView?,
        isEnabled: Bool,
        disabledReason: String?,
        extraTerms: [String] = []
    ) {
        titleLabel = NSTextField(labelWithString: title)
        rowIsEnabled = isEnabled
        plainTitle = title
        searchTerms = ([title, subtitle, disabledReason].compactMap { $0 } + extraTerms).map { $0.lowercased() }
        super.init(frame: .zero)

        titleLabel.font = Tokens.TypeScale.sidebarRow
        titleLabel.textColor = isEnabled ? Tokens.Text.primary : Tokens.Text.disabled
        titleLabel.lineBreakMode = .byTruncatingTail

        var text: [NSView] = [titleLabel]
        if let subtitle { text.append(Self.caption(subtitle, dimmed: !isEnabled)) }
        // §3: "never a silently dead switch" — the reason is on screen as well
        // as in the accessibility help, because most people do not use VoiceOver.
        if !isEnabled, let disabledReason { text.append(Self.caption(disabledReason, dimmed: false)) }

        build(text: text, control: control)
        describe(title: title, subtitle: subtitle, reason: disabledReason, control: control)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Retains a closure bridge for the life of the row, and hands the row back
    /// so a factory stays one expression.
    func retaining(_ object: AnyObject) -> SettingsRowView {
        keepAlive.append(object)
        return self
    }

    // MARK: - Layout

    private func build(text: [NSView], control: NSView?) {
        let labels = NSStackView(views: text)
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = SettingsMetrics.rowGap
        labels.setHuggingPriority(.defaultLow, for: .horizontal)

        var columns: [NSView] = [labels]
        if let control {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            columns.append(control)
        }
        let row = NSStackView(views: columns)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = SettingsMetrics.controlRowGap
        row.distribution = .fill
        row.edgeInsets = NSEdgeInsets(
            top: SettingsMetrics.controlRowGap,
            left: SettingsMetrics.controlRowGap,
            bottom: SettingsMetrics.controlRowGap,
            right: SettingsMetrics.controlRowGap
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            // A row is at least §1's control height; a subtitle or a reason
            // grows it rather than squashing into it.
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.controlRowHeight)
        ])
    }

    /// `Text.secondary`, not `tertiary`: §21.4's floor is measured on the bare
    /// planes and this text sits on `.control` glass, which spends headroom
    /// `tertiary` does not have.
    private static func caption(_ string: String, dimmed: Bool) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = Tokens.TypeScale.sectionLabel
        label.textColor = dimmed ? Tokens.Text.disabled : Tokens.Text.secondary
        label.isSelectable = false
        return label
    }

    // MARK: - §4's disabled row, §8's accessibility

    private func describe(title: String, subtitle: String?, reason: String?, control: NSView?) {
        // §8: "a label that reads without its visual context" — the control
        // carries the row's title, not the word next to it.
        control?.setAccessibilityLabel(title)
        if let subtitle { control?.setAccessibilityHelp(subtitle) }
        guard !rowIsEnabled else {
            setAccessibilityRole(.group)
            return
        }
        (control as? NSControl)?.isEnabled = false
        control?.setAccessibilityHelp(reason)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        setAccessibilityHelp(reason)
    }

    /// §4: a disabled row stays in the key-view loop. The row stands in for the
    /// control AppKit will not focus.
    override var acceptsFirstResponder: Bool { !rowIsEnabled }

    override var canBecomeKeyView: Bool { acceptsFirstResponder && !isHiddenOrHasHiddenAncestor }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: SettingsMetrics.rowCornerRadius,
            yRadius: SettingsMetrics.rowCornerRadius
        ).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    // MARK: - §2's highlight

    /// Marks `query` inside the row's title. An empty query restores the plain
    /// string, so this is also the "clear it" call.
    func highlight(_ query: String) {
        guard !query.isEmpty,
              let range = plainTitle.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            titleLabel.attributedStringValue = NSAttributedString()
            titleLabel.stringValue = plainTitle
            titleLabel.textColor = rowIsEnabled ? Tokens.Text.primary : Tokens.Text.disabled
            return
        }
        let marked = NSMutableAttributedString(string: plainTitle, attributes: [
            .font: Tokens.TypeScale.sidebarRow,
            .foregroundColor: rowIsEnabled ? Tokens.Text.primary : Tokens.Text.disabled
        ])
        marked.addAttribute(.backgroundColor, value: Tokens.Surface.selected, range: NSRange(range, in: plainTitle))
        titleLabel.attributedStringValue = marked
    }

    /// Every row in `view`'s subtree, in layout order — how the window reaches
    /// rows a section built without having to know how that section is
    /// assembled.
    static func rows(in view: NSView) -> [SettingsRowView] {
        view.subviews.flatMap { child -> [SettingsRowView] in
            if let row = child as? SettingsRowView { return [row] }
            return rows(in: child)
        }
    }
}

/// §1's "grouped control rows sit on `Glass.backing(.control, cornerRadius:
/// rowCornerRadius)`" — one card, with an optional §1 section label above it.
@MainActor
final class SettingsRowGroupView: NSView {

    private let card = NSView()

    init(title: String?, rows: [NSView]) {
        super.init(frame: .zero)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsMetrics.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        var columns: [NSView] = []
        if let title { columns.append(Self.header(title)) }
        columns.append(card)

        let outer = NSStackView(views: columns)
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = SettingsMetrics.rowGap
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ] + columns.map { $0.widthAnchor.constraint(equalTo: outer.widthAnchor) })

        // After the card has its constraints: `Glass.apply` frames its backing
        // from `bounds` and resizes it by autoresizing mask, which is what the
        // browser window's root view does too.
        Glass.apply(.control, to: card, cornerRadius: SettingsMetrics.rowCornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private static func header(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.sectionLabel
        label.textColor = Tokens.Text.secondary
        return label
    }
}
