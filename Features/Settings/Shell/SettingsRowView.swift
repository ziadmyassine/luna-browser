//
//  SettingsRowView.swift
//  Luna
//
//  The views §4's widgets are made of: a control row, a card of rows, the rule
//  between two of them, and the four controls the pane draws itself.
//
//  The disabled row is why a row is a custom view rather than a stack of
//  `NSControl`s. §4 requires a disabled row to be "dimmed, still focusable, and
//  still read by VoiceOver, with its reason as the accessibility help", and a
//  disabled `NSControl` is none of those — AppKit drops it out of the key-view
//  loop and VoiceOver skips it. So the control is disabled and the row becomes
//  the focusable, labelled, helped element (§30.4).
//
//  Nothing here is glass. The pane is opaque because a form is read, not looked
//  through; a card of `.control` glass on an opaque plane is a material with
//  nothing to refract, and nine of them stacked down a pane was the whole
//  window asking to be looked at. A card is `Surface.raised` with the usual
//  hairline, and a control is `Surface.well` or `Surface.selected`.
//

import AppKit

/// One control row: a title, an optional subtitle, an optional control, and —
/// when it is disabled — the one-line reason §3 requires.
@MainActor
final class SettingsRowView: NSView {

    /// The labels §2's search matches this row on, lowercased.
    let searchTerms: [String]

    /// AppKit targets are weak, so a row retains its control's closure bridge.
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

        titleLabel.font = Tokens.TypeScale.settingsRow
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

    /// Explicit constraints, not a horizontal stack. A stack decides which
    /// of its two views absorbs the spare width, and it decided differently for
    /// a switch (which has an intrinsic size) than for a `SettingsChoice` (which
    /// does not): the switch went to the trailing edge and the segments stayed
    /// beside the label with the spare width spread between them. One rule
    /// instead — the label starts at the card's text inset, the control ends at
    /// it — written down rather than inferred.
    private func build(text: [NSView], control: NSView?) {
        let labels = NSStackView(views: text)
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)

        let inset = SettingsMetrics.cardInset
        let pad = SettingsMetrics.controlRowGap
        var layout: [NSLayoutConstraint] = [
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            labels.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: pad),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -pad),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            // A subtitle or a disabled reason grows the row rather than
            // squashing into it.
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsMetrics.cardRowHeight)
        ]

        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(control)
            layout += [
                control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                control.centerYAnchor.constraint(equalTo: centerYAnchor),
                control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: pad),
                control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -pad),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -pad)
            ]
        } else {
            layout.append(labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset))
        }
        NSLayoutConstraint.activate(layout)
    }

    /// `Text.secondary`, not `tertiary`: §21.4's floor is measured on the bare
    /// planes and this sits on `Surface.raised`, which spends headroom
    /// `tertiary` does not have.
    private static func caption(_ string: String, dimmed: Bool) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = Tokens.TypeScale.settingsCaption
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

    /// §4: a disabled row stays in the key-view loop, standing in for the
    /// control AppKit will not focus.
    override var acceptsFirstResponder: Bool { !rowIsEnabled }

    override var canBecomeKeyView: Bool { acceptsFirstResponder && !isHiddenOrHasHiddenAncestor }

    /// The ring is a keyboard affordance, and opening a window is not the
    /// keyboard. A disabled row accepts first responder so VoiceOver and the
    /// key loop can still reach it (§4), and AppKit repaid that by making the
    /// first one the window's initial responder and drawing the accent ring
    /// round it — a blue halo on a dimmed row, on a pane that uses no accent
    /// colour anywhere. `GlassButton` solved this the same way: the ring comes
    /// back the moment focus arrives from a key press.
    override func becomeFirstResponder() -> Bool {
        focusRingType = NSApp.currentEvent?.type == .keyDown ? .default : .none
        noteFocusRingMaskChanged()
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
            .font: Tokens.TypeScale.settingsRow,
            .foregroundColor: rowIsEnabled ? Tokens.Text.primary : Tokens.Text.disabled
        ])
        marked.addAttribute(.backgroundColor, value: Tokens.Surface.selected, range: NSRange(range, in: plainTitle))
        titleLabel.attributedStringValue = marked
    }

    /// Every row in `view`'s subtree, in layout order — how the window reaches
    /// rows a section built without knowing how that section is assembled.
    static func rows(in view: NSView) -> [SettingsRowView] {
        view.subviews.flatMap { child -> [SettingsRowView] in
            if let row = child as? SettingsRowView { return [row] }
            return rows(in: child)
        }
    }
}

/// §1's card of rows, with an optional label above it.
///
/// One card, not a stack of chips. Its rows butt together and are separated
/// by a hairline that starts at the row's own text inset, which is what makes
/// six settings read as one group; a gap between them says the opposite.
@MainActor
final class SettingsRowGroupView: NSView {

    private let card = SettingsCardView()

    init(title: String?, rows: [NSView]) {
        super.init(frame: .zero)

        let stack = NSStackView(views: Self.ruled(rows))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        for row in stack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        var columns: [NSView] = []
        if let title { columns.append(Self.header(title)) }
        columns.append(card)

        let outer = NSStackView(views: columns)
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = SettingsMetrics.controlRowGap
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The rows with a hairline between each pair — never above the first or
    /// below the last, where the card's own edge already ends the group.
    private static func ruled(_ rows: [NSView]) -> [NSView] {
        rows.enumerated().flatMap { index, row in
            index == 0 ? [row] : [SettingsRuleView(), row]
        }
    }

    /// The group's name, above the card and flush with the card's own edge,
    /// one step down in ink: at full strength it was the same size, face and
    /// colour as the row beneath it and the eye had to read both to find out
    /// which was the label.
    ///
    /// Not the card's text inset, which is where it sat. Lining the name up
    /// with the row titles below it looked like the tidier of the two and reads
    /// as the worse one: the name then starts a `cardInset` inside the only
    /// vertical rule the pane has — the edge every card is drawn to — so it
    /// hangs in from nothing and sits closer to the card above it than to the
    /// one it names. Starting it on that edge is what makes a name and its card
    /// one block. The rows stay on their own inset; a label is not a row.
    private static func header(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.settingsRow
        label.textColor = Tokens.Text.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
            label.topAnchor.constraint(equalTo: host.topAnchor),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }
}

/// The plane a card is drawn on: `Surface.raised`, the hairline, and §1's
/// corner. One step above the pane and nothing more.
@MainActor
final class SettingsCardView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = SettingsMetrics.rowCornerRadius
        layer.backgroundColor = Tokens.Surface.raised.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The hairline between two rows: inset to the card's text grid on the leading
/// side and run to the card's edge on the trailing one, as every grouped list
/// on the platform draws it.
@MainActor
final class SettingsRuleView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: Tokens.Metric.hairline).isActive = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Tokens.Line.hairline.setFill()
        NSRect(
            x: SettingsMetrics.cardInset,
            y: 0,
            width: max(bounds.width - SettingsMetrics.cardInset, 0),
            height: bounds.height
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
