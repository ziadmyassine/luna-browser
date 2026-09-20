//
//  GlassButton+Keyboard.swift
//  Luna
//
//  §20.2: every chrome control is reachable from the keyboard, and §30.1: a
//  control on a draggable plane is not part of the plane.
//
//  Split out of `GlassButton.swift` for the reason `CommandBarPanelLayout.swift`
//  was split out of `CommandBarPanel.swift`: that file crosses SwiftLint's
//  400-line limit once the button answers a press as well as a hover. Nothing
//  changed on the way across.
//

import AppKit

extension GlassButton {

    // MARK: - Keyboard (§20.2 — every chrome control is reachable)

    /// §30.1: the sidebar's *plane* moves the window; a control on it does
    /// not. Without this the press that should have picked a pinned tile up
    /// picked the window up instead — `NSView` answers `true` by default for
    /// anything that draws no background of its own, which is every glass
    /// surface in the app.
    override var mouseDownCanMoveWindow: Bool { false }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        if shape.cornerCurve == .circular {
            NSBezierPath(ovalIn: bounds).fill()
        } else {
            NSBezierPath(roundedRect: bounds, xRadius: shape.cornerRadius, yRadius: shape.cornerRadius).fill()
        }
    }

    /// **The ring is a keyboard affordance, and a click is not the keyboard.**
    ///
    /// AppKit makes a clicked view that accepts first responder the window's
    /// first responder, and then draws the accent ring round it — a blue halo
    /// on a pinned tile, which is the one colour Luna's chrome never uses
    /// anywhere. A press already says which control you are on, because the
    /// material lights up under it. The ring comes back the moment focus
    /// arrives from the key loop instead, which is the case §20.2 is about.
    override func becomeFirstResponder() -> Bool {
        focusRingType = NSApp.currentEvent?.type == .keyDown ? .default : .none
        noteFocusRingMaskChanged()
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let pressed = event.charactersIgnoringModifiers ?? ""
        guard isEnabled, pressed == " " || pressed == "\r" || pressed == "\u{3}" else {
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
