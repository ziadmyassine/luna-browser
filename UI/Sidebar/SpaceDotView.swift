//
//  SpaceDotView.swift
//  Luna
//
//  One §3.5 dot.
//
//  It held §30.9's `+` too, standing where the next Space would be as the swipe
//  ran past the last one. The strip is dots and only dots now — see
//  `SpaceDotsView`'s header — and the `+` is drawn in the column, where the
//  gesture is actually happening (`SpaceCreationView`).
//
//  The dot is its own view because it is four things at once: a click target, a
//  §6.6 landing place, an accessibility element carrying the Space's name, and
//  — since §30.9 — a read-out of a gesture that is still in the user's hand.
//
//  **It is told where to draw its mark; it does not work it out.** `bounds`
//  is the dot's *slot*, which is as wide as the gap to its neighbour and is not
//  necessarily symmetric about the dot: the first and last slots run out to the
//  pill's edges. Centring the mark in the slot is what made the row of dots
//  crooked in the first place — see `SpaceDotsView`'s header — so the strip
//  computes every centre in one pass and hands each dot the one that is its.
//

import AppKit
import BrowserKit

/// One dot.
@MainActor
final class SpaceDotView: NSView {

    let space: Space
    var onActivate: (() -> Void)?
    var onSetGradient: ((GradientPair) -> Void)?
    var onEditSpaces: (() -> Void)?

    /// This is the Space the window is actually in.
    ///
    /// **It is the accessibility answer, not the drawn one.** `wearsRing` is
    /// what the eye follows, and mid-swipe that is the Space you are *about* to
    /// be in — which is the right thing to show a hand and the wrong thing to
    /// tell VoiceOver, because nothing has happened yet.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            setAccessibilitySelected(isActive)
        }
    }

    /// §6.6's lift is over this dot. Set by `SpaceDotsView`, which is the only
    /// thing that knows where the lift is.
    var isDropTarget = false { didSet { needsDisplay = true } }

    /// Where in the slot the 6 pt mark goes, from the slot's leading edge.
    var markCentreX: CGFloat = 0 {
        didSet {
            guard markCentreX != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 0…1 — how much of §3.5's "100 % / 35 %" step this dot has. 1 on the
    /// Space you are in, and a fraction of it mid-swipe, so the ink moves from
    /// one dot to the next with the finger rather than jumping at the end.
    var presence: CGFloat = 0 {
        didSet {
            guard presence != oldValue else { return }
            needsDisplay = true
        }
    }

    /// The dot a release would land on. Normally the active one; during a
    /// §30.9 swipe it is the Space you are about to get.
    var wearsRing = false { didSet { needsDisplay = true } }

    /// §6's press, handed to whoever owns the material under the dot — which
    /// is the pill, not this. `NavCluster` does the same thing for the same
    /// reason: a control with no surface of its own has nothing to swell.
    var onPressChange: ((Bool) -> Void)?

    // A gradient layer, because §8.2a's dot is the Space's own pair of stops
    // rather than a shared ink — `updateLayer` sets `colors` on it.
    private let mark = CAGradientLayer()
    /// §3.4's wash, under the mark: the dot is 6 pt of ink and a 6 pt hover
    /// target would be no target at all, so the chip is the dot's whole slot
    /// (`Metric.spaceDotChip`) and the pointer lights it from anywhere in it.
    /// It carries the mark rather than sitting beside it, so the two are one
    /// shape and the slot's asymmetry stays in `markCentreX` where it belongs.
    private let chip = CALayer()
    private var isHovering = false
    private var isPressed = false

    init(space: Space, position: Int, of count: Int) {
        self.space = space
        super.init(frame: .zero)
        wantsLayer = true
        chip.cornerCurve = .continuous
        chip.addSublayer(mark)
        layer?.addSublayer(chip)
        // §8/§21.2: the name, not the gradient, is what identifies a Space.
        toolTip = space.name
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(space.name)
        setAccessibilityValue("\(position) of \(count)")
        setAccessibilitySelected(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let size = Tokens.Metric.spaceDot
        let side = Tokens.Metric.spaceDotChip
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The chip is centred on the mark, and the mark is centred in the chip
        // — so the two are one shape from here on and the slot's own asymmetry
        // stays where it belongs, in `markCentreX`.
        chip.frame = NSRect(
            x: markCentreX - side / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        ).pixelAligned
        chip.cornerRadius = side / 2
        mark.frame = NSRect(
            x: (side - size) / 2,
            y: (side - size) / 2,
            width: size,
            height: size
        ).pixelAligned
        mark.cornerRadius = size / 2
        // §8.2a's full intensity, and the whole point of the twelve pairs: the
        // dots were `Text.primary` / `Text.tertiary`, so every Space looked
        // identical no matter what gradient it carried.
        //
        // **A Space nobody has coloured is drawn in the chrome's own ink**, not
        // in neutral's grey. `Gradient.neutral` is a real pair of greys because
        // §8.2a needs *something* to interpolate a wash toward, but painting it
        // is the same mistake `SpaceWashView.washColors` refuses to make: "no
        // colour" then reads as a thirteenth colour, and the dot for the Space
        // you are in — the one mark on the strip that has to be unmissable —
        // came out dimmer than the tab titles above it. Uncoloured, it is
        // `Text.primary`: full white in the dark, and §3.5's own 45 % step
        // still separates it from the Spaces either side.
        let ink = Tokens.Gradient.isNeutral(space.gradient)
            ? (start: Tokens.Text.primary, end: Tokens.Text.primary)
            : Tokens.Gradient.planes(space.gradient, at: .full, in: effectiveAppearance)
        mark.startPoint = CGPoint(x: 0, y: 1)
        mark.endPoint = CGPoint(x: 1, y: 0)
        mark.colors = [ink.start.cgColor, ink.end.cgColor]
        // §3.5's "100 % / 35 %" step, kept — but the inactive dot is now a
        // dimmer version of *its own* colour rather than of a shared ink, and
        // the step is crossed continuously so a swipe can sit between two.
        mark.opacity = Float(Self.restingInk + (1 - Self.restingInk) * max(0, min(presence, 1)))
        // §21.2 Differentiate Without Colour: exactly one dot wears a ring, so
        // "which Space am I in" never depends on being able to tell two hues
        // apart — and mid-swipe it is the answer to "which one am I getting".
        // The drop ring outranks it: during a §6.6 drag the question is where
        // the tab is about to land.
        mark.borderWidth = isDropTarget || wearsRing ? Tokens.Metric.hairline : 0
        mark.borderColor = isDropTarget ? Tokens.Accent.tint.cgColor : Tokens.Text.primary.cgColor
        CATransaction.commit()
    }

    /// §3.5's inactive dot, as a fraction of full ink.
    static let restingInk: CGFloat = 0.45

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        // A dynamic `NSColor` resolved into a `CGColor` does not follow the
        // appearance it was resolved in, so the chip is repainted rather than
        // left in the old one's ink.
        applyWash(animated: false)
    }

    // MARK: - §3.4's two washes

    /// Nothing at rest, `Surface.hover` under the pointer, `Surface.selected`
    /// under a press — the same two steps every other button in the chrome
    /// answers with, on the one control in the sidebar that had no answer at
    /// all: the dots took a click and said nothing until the Space changed.
    private var washColour: NSColor? {
        if isPressed { return Tokens.Surface.selected }
        return isHovering ? Tokens.Surface.hover : nil
    }

    private func applyWash(animated: Bool = true) {
        Tokens.Motion.wash(chip, to: washColour, animated: animated)
    }

    // MARK: - Input

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }

    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        applyWash()
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    /// The press follows the pointer out of the dot and back in, like every
    /// other button's: a finger that has slid off the control is no longer
    /// pressing it, and the wash has to say so before the mouse comes up.
    override func mouseDragged(with event: NSEvent) {
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        // **No `mouseExited` arrives while a button is down**, so a release
        // that lands off the dot has to clear the hover itself — otherwise the
        // chip is left lit on a dot the pointer is nowhere near.
        setHovering(inside)
        guard inside else { return }
        onActivate?()
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        applyWash()
        onPressChange?(pressed)
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    // MARK: - §8.2 / §13.6 the colour menu

    /// Right-click a dot to recolour its Space, to — the part Arc needed a help
    /// article for — leave a colour again, and to open §6.2's other five
    /// settings in the window that holds them.
    ///
    /// A menu on the dot rather than only a Settings pane because the dot is
    /// the one place a Space is *visible*: Arc's "How Do I Restore the Default
    /// Theme" exists because getting out of a theme was somewhere else
    /// entirely, and Zen has an open issue for not being able to unset a
    /// gradient at all. Colour stays here, in the hand; renaming, reordering
    /// and the Profile are a window away rather than a menu deeper.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(SidebarMenu.header("Colour for \(space.name)"))
        for (index, gradient) in Tokens.Gradient.spacePalette.enumerated() {
            let item = SidebarMenu.item(title: Tokens.Gradient.spacePaletteNames[index]) { [weak self] in
                self?.onSetGradient?(gradient)
            }
            item.image = SidebarMenu.swatch(gradient, in: effectiveAppearance)
            item.state = gradient == space.gradient ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // §13.6's one click back to neutral. Always present, never conditional
        // on the Space already carrying a colour — a way out that only appears
        // once you are lost is not a way out.
        let reset = SidebarMenu.item(title: "No Colour") { [weak self] in
            self?.onSetGradient?(Tokens.Gradient.neutral)
        }
        reset.image = SidebarMenu.swatch(Tokens.Gradient.neutral, in: effectiveAppearance)
        reset.state = Tokens.Gradient.isNeutral(space.gradient) ? .on : .off
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(SidebarMenu.item(title: String(localized: "Edit “\(space.name)”…")) { [weak self] in
            self?.onEditSpaces?()
        })
        menu.addItem(.separator())
        // Arc's own documentation shouts this, and it is the combination that
        // works: colour is per Space, Light/Dark is not. Saying so here is
        // cheaper than the support article that follows from not saying it.
        menu.addItem(SidebarMenu.header("Light and Dark apply to every Space"))
        return menu
    }
}
