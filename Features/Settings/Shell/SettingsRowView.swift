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

    private func build(text: [NSView], control: NSView?) {
        let labels = NSStackView(views: text)
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = SettingsMetrics.rowGap
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)

        // **Explicit constraints, not a horizontal stack.** A stack decides
        // which of its two views absorbs the row's spare width, and it decided
        // differently for a switch (which has an intrinsic size) than for a
        // `SettingsChoice` (which does not): the switch went to the trailing
        // edge and the segments stayed beside the label with the spare width
        // spread *between* the segments. The reference has one rule — the
        // label starts at the card's text inset, the control ends at it — so
        // that is what is written here, and nothing infers it.
        let inset = SettingsMetrics.cardInset
        let pad = SettingsMetrics.controlRowGap
        var layout: [NSLayoutConstraint] = [
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            labels.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: pad),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -pad),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            // A row is at least §1's card-row height; a subtitle or a disabled
            // reason grows it rather than squashing into it.
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
    /// planes and this text sits on `.control` glass, which spends headroom
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
            .font: Tokens.TypeScale.settingsRow,
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

        // **One card, not a stack of chips.** The reference butts its rows
        // together and rules between them, starting the rule at the row's own
        // text rather than at the card's edge — which is what makes six
        // settings read as one group instead of as six small panels. A gap
        // between them says the opposite.
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

        // After the card has its constraints: `Glass.apply` frames its backing
        // from `bounds` and resizes it by autoresizing mask, which is what the
        // browser window's root view does too.
        Glass.apply(.control, to: card, cornerRadius: SettingsMetrics.rowCornerRadius)
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

    /// The group's name, sitting **above** the card and indented to the card's
    /// own text grid, so it reads as the label on the rows rather than as a
    /// heading floating over the pane.
    private static func header(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Tokens.TypeScale.settingsRow
        // **A step below the rows it names.** At full strength the header was
        // the same ink, the same size and the same face as the row under it,
        // so a card opened with two lines of identical type and the eye had to
        // read both to find out which one was the group. The reference keeps
        // the size and the position and drops the ink one step, which says
        // "label" without spending a second type size on it.
        label.textColor = Tokens.Text.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SettingsMetrics.cardInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
            label.topAnchor.constraint(equalTo: host.topAnchor),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }
}

/// The hairline between two rows of a card. Inset to the card's text grid on
/// the leading side and run to the card's edge on the trailing one, which is
/// how every grouped list on the platform draws it.
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

/// §4's pushbutton, drawn flat.
///
/// **AppKit's `.push` bezel is the loudest thing in the pane.** It is a
/// near-white plate with a shadow under it, and next to a bare popup and a
/// switch it read as the one control that had been dropped in from another
/// app — "Set as Default" pulled the eye before the row it belonged to. The
/// reference's button is the row's own wash with a hairline round it and the
/// label at full strength, which is what this draws.
///
/// Still an `NSButton`, so `isEnabled`, the key-view loop, `⌥`-clicking,
/// VoiceOver's `AXButton` role and the `performClick` path are AppKit's and
/// not re-earned here — only `draw` is ours, and only because the bezel is.
@MainActor
final class SettingsPushButton: NSButton {

    var onActivate: (() -> Void)?

    private let isDestructive: Bool
    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            needsDisplay = true
        }
    }

    init(title: String, isDestructive: Bool) {
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        isBordered = false
        self.title = title
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsButtonHeight).isActive = true
        applyTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() { onActivate?() }

    /// The title is attributed, so `isEnabled` has to dim it by hand — AppKit
    /// only dims the ones it drew itself.
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            applyTitle()
        }
    }

    private func applyTitle() {
        let ink: NSColor = if !isEnabled {
            Tokens.Text.disabled
        } else if isDestructive {
            Tokens.Accent.danger
        } else {
            Tokens.Text.primary
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Tokens.TypeScale.sidebarRow,
            .foregroundColor: ink
        ])
        needsDisplay = true
    }

    /// Room either side of the label — a flat button with none is a word.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 2 * Tokens.Metric.settingsButtonInset
        size.height = Tokens.Metric.settingsButtonHeight
        return size
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = SettingsMetrics.fieldCorner
        layer.backgroundColor = (isHovering && isEnabled ? Tokens.Surface.hover : Tokens.Surface.selected).cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        // `wantsUpdateLayer` is false on a control that draws a title, so the
        // plate is refreshed on the way into `super.draw`.
        updateLayer()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTitle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }
}

/// §4's text field, drawn as a well.
///
/// **AppKit's bezel is a white plate in a dark pane.** The stock field arrives
/// with a light background and a hard border, so a Space's name sat in the one
/// bright rectangle in the window and pulled harder than the Space it named.
/// The reference's fields are the recess the search field is: `Surface.well`,
/// the same corner, no outline, and the text at the row's own size.
///
/// Still an `NSTextField`, so editing, the field editor, undo, Services and
/// VoiceOver are AppKit's — only the bezel is redrawn.
@MainActor
final class SettingsTextField: NSTextField {

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTokens() {
        font = Tokens.TypeScale.settingsRow
        textColor = isEnabled ? Tokens.Text.primary : Tokens.Text.disabled
        needsDisplay = true
    }

    /// Room either side of the text, and the height the rest of the row's
    /// controls stand at.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = Tokens.Metric.capsuleHeight - Tokens.Metric.chromeGap
        return size
    }

    /// A field with no inset puts its caret against the corner.
    override var isEnabled: Bool {
        didSet { applyTokens() }
    }

    override func drawFocusRingMask() {}

    override func draw(_ dirtyRect: NSRect) {
        guard let layer else {
            super.draw(dirtyRect)
            return
        }
        layer.cornerRadius = SettingsMetrics.fieldCorner
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = 0
        super.draw(dirtyRect)
    }

    /// The text sits off the well's edge on both sides, the same inset the
    /// search field gives its own.
    override class var cellClass: AnyClass? {
        get { SettingsTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}

/// The inset that keeps a field's text and its caret off the well's corner.
@MainActor
final class SettingsTextFieldCell: NSTextFieldCell {

    /// **`NSTextFieldCell` does not centre its text.** It draws from the top of
    /// whatever rect it is handed, so a field standing at the row's control
    /// height had its text against the well's top edge. The inset is therefore
    /// horizontal *and* vertical, measured from the line height the cell
    /// reports for the font it was given.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centred(rect))
    }

    private func centred(_ rect: NSRect) -> NSRect {
        let line = (font ?? Tokens.TypeScale.settingsRow).boundingRectForFont.height
        let inset = max((rect.height - line) / 2, 0)
        return rect.insetBy(dx: Tokens.Metric.pillTextInset, dy: inset)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centred(rect),
            in: controlView,
            editor: editor,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor: NSText,
        delegate: Any?,
        start: Int,
        length: Int
    ) {
        super.select(
            withFrame: centred(rect),
            in: controlView,
            editor: editor,
            delegate: delegate,
            start: start,
            length: length
        )
    }
}

/// A key equivalent, drawn the way the reference draws one: the glyphs on a
/// small recessed plate rather than loose at the end of the row.
///
/// **It is a label, not a control** — §3.6's table is read-only — so it carries
/// no hover, no press and nothing for the key loop. The plate is there because
/// `⌥⌘H` set as plain text next to a sentence reads as part of the sentence;
/// on a chip it reads as a key.
@MainActor
final class SettingsKeyChip: NSView {

    private let label: NSTextField

    init(key: String) {
        label = NSTextField(labelWithString: key)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = Tokens.TypeScale.sidebarRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let inset = Tokens.Metric.chromeGap
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsSegmentHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(key)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTint() {
        label.textColor = Tokens.Text.secondary
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Tokens.Metric.settingsSegmentCorner
        layer?.backgroundColor = Tokens.Surface.well.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }
}
