//
//  SpaceEditorControls.swift
//  Luna
//
//  The two pieces `SpaceEditorView` is assembled from that are not already in
//  the sidebar's kit: the plate a group of the form sits on, and the one
//  labelled button at the foot of it.
//
//  A card, because three settings in a column are three settings and not a
//  list. The form used to be a label, a field, a label, a grid, a label and
//  another grid, all on the same glass with nothing but vertical gaps to say
//  where one thing stopped and the next began — and a gap is the weakest
//  boundary a layout has. `Surface.chromeFill` with the chrome's own hairline
//  round it is the boundary the rest of Luna uses for a well (§3.2's pill,
//  §3.3's tiles), so a group reads as one object at a glance rather than as
//  two labels that happen to be near their grids.
//
//  A labelled button, because a bare tick is a guess. The circle at the
//  bottom carried `checkmark` and nothing else, which is legible only if you
//  already know what it will do — and "it closes the form you are looking at"
//  and "it makes the Space" are both plausible readings of a tick. The word is
//  the fix, and it is the only control in the sidebar that needs one.
//
//  Its own file rather than `SpaceEditorView`'s, for that file's own reason:
//  §3's column is laid out by hand and the layout is the long half. A control
//  that draws and tracks a pointer is read when something looks wrong, and the
//  arithmetic is read when something lands in the wrong place.
//

import AppKit

/// One group of `SpaceEditorView`'s form, on its own plate.
///
/// The `.control` glass the sidebar's buttons wear would be the wrong material
/// here: the editor is already a pane of `.sidebar` glass over the Space's
/// gradient, and a second material inside the first is a refraction of a
/// refraction. This is a wash on top, which is what §3.2's pill is.
@MainActor
final class SpaceEditorCard: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Tokens.Metric.rowCornerRadius
        layer.backgroundColor = Tokens.Surface.chromeFill.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The editor's one action, spelled out: a full-width pill with a word on it.
///
/// Not a `GlassButton`, which takes a symbol and a shape and has no room for a
/// title, and not `SettingsPushButton`, which pins its own height with a
/// constraint — §3's column sets frames by hand, and a view that argues with
/// its parent about its size is a view that ends up at the origin.
@MainActor
final class SpaceEditorButton: NSView {

    /// Fired on a click that both went down and came up inside the pill, and
    /// on Space or Return while it holds the focus.
    var onActivate: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            // The swell is the press's alone. Hanging it off `refresh`
            // would re-spring the pill every time the pointer crossed its
            // edge, which is a button that twitches at rest.
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        titleLabel.stringValue = title
        titleLabel.font = Tokens.TypeScale.settingsRow
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        let height = ceil(titleLabel.fittingSize.height)
        titleLabel.frame = NSRect(
            x: Tokens.Metric.pillTextInset,
            y: ((bounds.height - height) / 2).rounded(),
            width: max(bounds.width - 2 * Tokens.Metric.pillTextInset, 0),
            height: height
        )
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        applyTokens()
    }

    /// §3.1's answer to a pointer, on the two washes every other chrome control
    /// uses: 6 % on hover and 12 % under the finger. The resting fill is the
    /// lighter of the two, because this is the thing the form is for and a
    /// button that is invisible until you find it is not one.
    private func applyTokens() {
        guard let layer else { return }
        layer.cornerRadius = bounds.height / 2
        layer.backgroundColor = (isPressed || isHovering ? Tokens.Surface.selected : Tokens.Surface.hover).cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
        titleLabel.textColor = Tokens.Text.primary
    }

    /// The wash cross-fades on §6's `controlHover`; the press also swells
    /// the pill 5 % and springs it back (`Motion.controlPress`), which is
    /// what every other button in the chrome does under a finger. It carries
    /// its own material — there is no capsule around it to hand the gesture
    /// to — so the swell is this view's.
    private func refresh() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Pointer and keyboard

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        // A finger that has slid off the button is a press being called off,
        // and it should look like one before it is let go.
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        guard inside else { return }
        onActivate?()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Space and Return, the two keys AppKit presses a focused button with.
        guard event.charactersIgnoringModifiers == " " || event.keyCode == 36 else {
            super.keyDown(with: event)
            return
        }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
