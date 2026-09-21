//
//  SettingsRowView.swift
//  Luna
//
//  The views §4's widgets are made of: a control row, a card of rows, the rule
//  between two of them, and the four controls the pane draws itself.
//
//  **The disabled row is why a row is a custom view and not a stack of
//  `NSControl`s.** §4 requires a disabled row to be "dimmed, still focusable,
//  and still read by VoiceOver, with its reason as the accessibility help", and
//  a disabled `NSControl` is none of those — AppKit drops it out of the key-view
//  loop and VoiceOver skips it. So the *control* is disabled and the *row* takes
//  over as the focusable, labelled, helped element (§30.4).
//
//  **Nothing in here is glass.** The pane is opaque because a form is read, not
//  looked through; a card of `.control` glass on an opaque plane is a material
//  with nothing to refract, and nine of them stacked down a pane was the whole
//  window asking to be looked at. A card is `Surface.raised` with the hairline
//  every other surface carries, and a control is `Surface.well` or
//  `Surface.selected` — the same three planes the browser's chrome uses.
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

    /// **Explicit constraints, not a horizontal stack.** A stack decides which
    /// of its two views absorbs the spare width, and it decided differently for
    /// a switch (which has an intrinsic size) than for a `SettingsChoice` (which
    /// does not): the switch went to the trailing edge and the segments stayed
    /// beside the label with the spare width spread *between* them. One rule
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

    /// **The ring is a keyboard affordance, and opening a window is not the
    /// keyboard.** A disabled row accepts first responder so VoiceOver and the
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
/// **One card, not a stack of chips.** Its rows butt together and are separated
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

    /// The group's name, above the card and **flush with the card's own edge**,
    /// one step down in ink: at full strength it was the same size, face and
    /// colour as the row beneath it and the eye had to read both to find out
    /// which was the label.
    ///
    /// **Not the card's text inset, which is where it sat.** Lining the name up
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

/// §4's pushbutton, drawn flat.
///
/// AppKit's `.push` bezel is a near-white plate with a shadow: next to a bare
/// popup and a switch it read as the one control dropped in from another app.
/// Still an `NSButton`, so `isEnabled`, the key loop, `performClick` and the
/// `AXButton` role are AppKit's — only the bezel is ours.
@MainActor
final class SettingsPushButton: NSButton {

    var onActivate: (() -> Void)?

    private let isDestructive: Bool
    private var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            redraw()
        }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            redraw()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
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
        heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight).isActive = true
        applyTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func fire() { onActivate?() }

    /// The title is attributed, so `isEnabled` has to dim it by hand — AppKit
    /// only dims the ones it drew itself. `title` is overridden for the same
    /// reason: `attributedTitle` wins once it is set, so assigning the plain
    /// string alone would change nothing on screen.
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            applyTitle()
        }
    }

    override var title: String {
        didSet {
            guard title != oldValue else { return }
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
            .font: Tokens.TypeScale.settingsRow,
            .foregroundColor: ink
        ])
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 2 * SettingsMetrics.controlInset
        size.height = SettingsMetrics.controlHeight
        return size
    }

    private func redraw() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    /// §3.4's two washes, the way round every other control in the app has
    /// them: the resting plate is the 6 %, the pointer takes it to 12 %, and
    /// the press holds it there while the button swells. **It used to be
    /// inverted** — `selected` at rest and `hover` under the pointer — so the
    /// one button in Settings with a word on it was also the one that got
    /// *fainter* when you went for it.
    override func updateLayer() {
        guard let layer else { return }
        let lifted = isEnabled && (isHovering || isPressed)
        layer.cornerRadius = SettingsMetrics.controlCorner
        layer.backgroundColor = (lifted ? Tokens.Surface.selected : Tokens.Surface.hover).cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    /// `wantsUpdateLayer` is false on a control that draws a title, so the plate
    /// is refreshed on the way into `super.draw`.
    override func draw(_ dirtyRect: NSRect) {
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

    /// The press is taken around `NSControl`'s own tracking loop, which does
    /// not return until the mouse comes back up — see `TopBarButton.mouseDown`.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
    }
}

/// §4's text field, drawn as the well the browser's own two search fields are:
/// `Surface.well`, a hairline, and the same corner. AppKit's bezel is a white
/// box, which in a dark pane is the brightest thing in the window.
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

    /// Set when what is typed here is not being used — a custom search
    /// template with no `%s` in it. The ink carries it, because the alternative
    /// was a sentence under the row saying the same thing in thirty words.
    var warns = false {
        didSet {
            guard warns != oldValue else { return }
            Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
                context.allowsImplicitAnimation = true
                self.applyTokens()
            }
        }
    }

    private func applyTokens() {
        font = Tokens.TypeScale.settingsRow
        textColor = if !isEnabled {
            Tokens.Text.disabled
        } else if warns {
            Tokens.Accent.danger
        } else {
            Tokens.Text.primary
        }
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = SettingsMetrics.controlHeight
        return size
    }

    override var isEnabled: Bool {
        didSet { applyTokens() }
    }

    override func drawFocusRingMask() {}

    override func draw(_ dirtyRect: NSRect) {
        guard let layer else {
            super.draw(dirtyRect)
            return
        }
        layer.cornerRadius = SettingsMetrics.controlCorner
        layer.backgroundColor = Tokens.Surface.well.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
        super.draw(dirtyRect)
    }

    override static var cellClass: AnyClass? {
        get { SettingsTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}

/// `NSTextFieldCell` draws from the top of whatever rect it is handed and never
/// centres, so a field standing at the pane's control height had its text
/// against the well's top edge. The inset is therefore horizontal *and*
/// vertical, measured from the line height of the font it was given.
@MainActor
final class SettingsTextFieldCell: NSTextFieldCell {

    private func centred(_ rect: NSRect) -> NSRect {
        let line = (font ?? Tokens.TypeScale.settingsRow).boundingRectForFont.height
        let inset = max((rect.height - line) / 2, 0)
        return rect.insetBy(dx: Tokens.Metric.pillTextInset, dy: inset)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centred(rect))
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: centred(rect), in: controlView, editor: editor, delegate: delegate, event: event)
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

/// §4's switch.
///
/// **AppKit's is 54 × 24 and will not be told otherwise.** Measured on macOS 26:
/// `NSSwitch` returns the same fitting size at `.large`, `.regular`, `.small`
/// and `.mini` — the property is accepted and ignored. That is twice the width
/// every other control in the pane was built to (`settingsControl`, 28), and a
/// card of them read as a row of levers rather than of settings.
///
/// So this is the one system control Luna replaces, and it is replaced rather
/// than *scaled*: a layer transform would rasterise the system's crisp rim and
/// then blur it, and would leave the click target somewhere the switch is not.
/// What is re-earned by hand is written out below — the key loop, Space, the
/// `AXCheckBox` role and its value, the focus ring, and Reduce Motion. The
/// on-state keeps the system accent, because a switch that is on is the one
/// place in this window where the user's own accent choice is the answer every
/// other Mac app gives.
@MainActor
final class SettingsSwitch: NSControl {

    var onChange: ((Bool) -> Void)?

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            refresh(animated: true)
        }
    }

    private let track = CALayer()
    private let knob = CALayer()

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let metric = Tokens.Metric.settingsSwitch
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: metric.width),
            heightAnchor.constraint(equalToConstant: metric.height)
        ])
        track.cornerRadius = metric.cornerRadius
        track.cornerCurve = metric.cornerCurve
        track.borderWidth = Tokens.Metric.hairline
        knob.cornerRadius = (metric.height - 2 * Tokens.Metric.settingsSwitchKnobInset) / 2
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        refresh(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var intrinsicContentSize: NSSize { Tokens.Metric.settingsSwitch.size }

    override func layout() {
        super.layout()
        // Bounds-derived, so it may never animate — the knob's *travel* is what
        // animates, and that is driven from `refresh(animated:)`.
        Tokens.Motion.immediately {
            track.frame = bounds
            knob.frame = knobFrame
        }
    }

    private var knobFrame: NSRect {
        let inset = Tokens.Metric.settingsSwitchKnobInset
        let diameter = bounds.height - 2 * inset
        return NSRect(
            x: isOn ? bounds.width - diameter - inset : inset,
            y: inset,
            width: diameter,
            height: diameter
        )
    }

    // MARK: - Paint

    private func refresh(animated: Bool) {
        setAccessibilityValue(isOn)
        let paint = {
            self.track.backgroundColor = self.isOn && self.isEnabled
                ? Tokens.Accent.tint.cgColor
                : Tokens.Surface.well.cgColor
            self.track.borderColor = self.isOn && self.isEnabled
                ? NSColor.clear.cgColor
                : Tokens.Line.border.cgColor
            // White in both themes, exactly as AppKit's own knob is: the knob is
            // the moving part, and it has to read against the accent as well as
            // against the well.
            self.knob.backgroundColor = (self.isEnabled ? NSColor.white : Tokens.Text.disabled).cgColor
            self.knob.frame = self.knobFrame
        }
        guard animated, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately(paint)
            return
        }
        Tokens.Motion.animate(Tokens.Motion.selectedRowMove) { context in
            context.allowsImplicitAnimation = true
            paint()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh(animated: false)
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            setAccessibilityEnabled(isEnabled)
            refresh(animated: false)
        }
    }

    // MARK: - Input

    private func toggle() {
        guard isEnabled else { return }
        isOn.toggle()
        onChange?(isOn)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggle()
    }

    /// Space, which is what AppKit's switch answers to. Return is deliberately
    /// left alone: it belongs to the window's default button, not to a row.
    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        toggle()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

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
        let metric = Tokens.Metric.settingsSwitch
        NSBezierPath(roundedRect: bounds, xRadius: metric.cornerRadius, yRadius: metric.cornerRadius).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        toggle()
        return true
    }
}

/// A key equivalent, on the same well every other read-only value sits in.
///
/// **`isFixed` is the whole of §3.6's "which of these can I change?".** A
/// shortcut the user can move is drawn by `SettingsShortcutRecorder`, which is
/// this chip plus a click target: same well, same border, same corner. Drawn
/// identically, a shortcut that is nobody's to move looked exactly like one
/// that is, and the only way to find out was to click it. A fixed chip
/// therefore drops the well and the border and prints flat, so the boxes down
/// the right-hand side of the table are precisely the rows that are yours.
@MainActor
final class SettingsKeyChip: NSView {

    private let label: NSTextField
    private let isFixed: Bool

    init(key: String, isFixed: Bool = false) {
        label = NSTextField(labelWithString: key)
        self.isFixed = isFixed
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = Tokens.TypeScale.settingsRow
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.controlHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.chromeGap),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.chromeGap),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(isFixed ? String(localized: "Shortcut \(key). This one cannot be changed.") : key)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func applyTint() {
        label.textColor = isFixed ? Tokens.Text.tertiary : Tokens.Text.secondary
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = SettingsMetrics.controlCorner
        // Nothing drawn at all, rather than a paler well: a faint box is still a
        // box, and at a glance it would read as a control that happens to be
        // dimmed — which is the one thing this must not say.
        guard !isFixed else {
            layer?.backgroundColor = nil
            layer?.borderWidth = 0
            return
        }
        layer?.backgroundColor = Tokens.Surface.well.cgColor
        layer?.borderWidth = Tokens.Metric.hairline
        layer?.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }
}
