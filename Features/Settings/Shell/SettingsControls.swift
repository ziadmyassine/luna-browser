//
//  SettingsControls.swift
//  Luna
//
//  The five controls §4's rows are filled with: the pushbutton, the text field
//  and its cell, the switch, and §3.6's key chip.
//
//  Split out of `SettingsRowView.swift` for that file's length limit, along the
//  seam it already had — above are the row and the containers it sits in, here
//  are the things that go inside one.
//
//  Each of these replaces an AppKit control rather than restyling it, and each
//  says why at its own declaration. The common thread is that AppKit's bezels
//  are the only bright plates in an otherwise dark pane, and that `NSSwitch` is
//  a fixed 54 × 24 whatever `controlSize` it is given.
//

import AppKit

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
    /// the press holds it there while the button swells. It used to be
    /// inverted — `selected` at rest and `hover` under the pointer — so the
    /// one button in Settings with a word on it was also the one that got
    /// fainter when you went for it.
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
/// against the well's top edge. The inset is therefore horizontal and
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
/// AppKit's is 54 × 24 and will not be told otherwise. Measured on macOS 26:
/// `NSSwitch` returns the same fitting size at `.large`, `.regular`, `.small`
/// and `.mini` — the property is accepted and ignored. That is twice the width
/// every other control in the pane was built to (`settingsControl`, 28), and a
/// card of them read as a row of levers rather than of settings.
///
/// So this is the one system control Luna replaces, and it is replaced rather
/// than scaled: a layer transform would rasterise the system's crisp rim and
/// blur it, and would leave the click target somewhere the switch is not. What
/// is re-earned by hand is below — the key loop, Space, the `AXCheckBox` role
/// and value, the focus ring, Reduce Motion. The on-state keeps the system
/// accent, because a switch that is on is the one place in this window where
/// the user's accent choice is the answer every other Mac app gives.
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
        // Bounds-derived, so it may never animate — the knob's travel is what
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
/// `isFixed` is the whole of §3.6's "which of these can I change?". A
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
