//
//  OnboardingButton.swift
//  Luna — §30.17
//
//  The two answers at the foot of the left column: one solid, one quiet.
//
//  Its own control rather than `SpaceEditorButton` because that one lives at
//  the sidebar's type size, in a column the user can drag; this is a page, and
//  a page's buttons are set to be read across a room.
//

import AppKit

@MainActor
final class OnboardingButton: NSView {

    var onActivate: (() -> Void)?

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            alphaValue = isEnabled ? 1 : 0.4
            refresh()
        }
    }

    var title: String = "" {
        didSet {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let isPreferred: Bool
    private var isHovering = false { didSet { if isHovering != oldValue { refresh() } } }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            refresh()
            Tokens.Motion.swell(self, to: isPressed ? Tokens.Motion.pressSwell : 1)
        }
    }

    init(title: String, isPreferred: Bool) {
        self.isPreferred = isPreferred
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.stringValue = title
        self.title = title
        label.font = Tokens.TypeScale.commandBarRow
        label.alignment = .center
        addSubview(label)
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
        let height = ceil(label.fittingSize.height)
        label.frame = NSRect(
            x: Tokens.Metric.pillTextInset,
            y: ((bounds.height - height) / 2).rounded(),
            width: max(bounds.width - 2 * Tokens.Metric.pillTextInset, 0),
            height: height
        )
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { applyTokens() }

    /// The preferred answer takes the accent and AppKit's own variants of it,
    /// so it moves with whichever colour the user picked (§5.2's exception).
    private func applyTokens() {
        guard let layer else { return }
        layer.cornerRadius = bounds.height / 2
        layer.backgroundColor = fill.cgColor
        layer.borderWidth = isPreferred ? 0 : Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
        label.textColor = isPreferred ? Tokens.Accent.onTint : Tokens.Text.primary
    }

    private var fill: NSColor {
        guard isEnabled else { return isPreferred ? Tokens.Accent.tint : .clear }
        guard isPreferred else {
            return isPressed || isHovering ? Tokens.Surface.selected : Tokens.Surface.hover
        }
        if isPressed { return Tokens.Accent.tint.withSystemEffect(.pressed) }
        return isHovering ? Tokens.Accent.tint.withSystemEffect(.rollover) : Tokens.Accent.tint
    }

    private func refresh() {
        Tokens.Motion.animate(Tokens.Motion.controlHover) { _ in
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// §30.1: the window's background moves the window; a control on it does
    /// not. Without this the page's own buttons are a drag handle — AppKit
    /// takes the press for `isMovableByWindowBackground` before the control
    /// ever sees it.
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = isEnabled }

    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) { isPressed = isEnabled }

    override func mouseDragged(with event: NSEvent) {
        isPressed = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        guard inside, isEnabled else { return }
        onActivate?()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " || event.keyCode == 36 else {
            super.keyDown(with: event)
            return
        }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onActivate?()
        return true
    }
}
