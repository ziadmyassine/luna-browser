//
//  GlassButton.swift
//  Luna
//
//  Every round or squircular glass control in the sidebar: the §3.1 toggle /
//  back / reload cluster, the §3.3 Essentials tiles, the §3.5 avatar and
//  archive circles. One class, because they differ only in shape and glyph —
//  a second implementation would be a second set of hover, focus-ring and
//  VoiceOver bugs.
//
//  **Hover lifts the fill, not the border** (§3.1). Luna has no translucent
//  "hover fill" token — `Surface.raised`/`glassFallback` are opaque and the
//  `Line.*` tokens are line colours — so the lift is expressed on the glyph
//  (`Text.secondary` → `Text.primary`) and the border is left alone, which is
//  the half of the rule that matters most. See the milestone report:
//  `Tokens.Surface.hover` is the missing token.
//

import AppKit

@MainActor
final class GlassButton: NSView {

    /// Fired on click, Space or Return.
    var onActivate: (() -> Void)?
    /// Makes the button draggable (§6.6 — an Essentials tile moves between
    /// sections). Handed the **press** that started the gesture, not the drag
    /// that noticed it, so whoever takes over can lift from where the finger
    /// went down; nil for a button that does not travel.
    var onDragOut: ((NSEvent) -> Void)?
    /// The right-click menu, built on demand so it always reflects the
    /// button's current tab rather than the one it was created with.
    var menuBuilder: (() -> NSMenu?)?
    /// §3.3: this button is the **selected** one — the active Essential.
    ///
    /// **Selection is the material, not a ring.** It used to draw a 1 pt accent
    /// border, which is the system-blue highlight Luna does not have anywhere
    /// else. A `.dormant` button carries no glass until it is hovered or
    /// selected; arriving at it *is* the highlight.
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateGlass(animated: true)
            refresh()
        }
    }
    /// §3.1: back dims when `canGoBack` is false.
    var isEnabled = true { didSet { refresh() } }

    /// When the button carries its glass.
    ///
    /// **Glass is Luna's highlight.** Nothing in the chrome turns blue to say
    /// "this one" — it turns to material. A `.dormant` button is a bare glyph
    /// on the plane it sits on until the pointer arrives or it becomes the
    /// selected one, and the material fades in and out on §6's control-hover
    /// curve. §3.3's pinned tiles are the case this was built for.
    enum GlassMode {
        case always
        case dormant
    }

    private let shape: RoundedMetric
    private let pointSize: CGFloat
    private let glassMode: GlassMode
    private let glyph = NSImageView()
    /// The `.control` backing, **built on demand**.
    ///
    /// A dormant button that has never been hovered has no glass view at all.
    /// That matters: a sidebar with eight pinned tiles used to stand up eight
    /// live `NSGlassEffectView`s to hold at alpha 0, and every one of them
    /// re-composites when the app comes back to the foreground — which is a
    /// large part of what the sidebar's activation flash was made of.
    private var glass: NSView?
    private var isHovering = false
    private var isPressed = false
    /// The mouse-down that is still in progress, kept so a drag can be lifted
    /// from where it actually started rather than from where it was noticed.
    private var press: NSEvent?

    init(
        shape: RoundedMetric,
        symbolName: String,
        pointSize: CGFloat,
        label: String,
        glassMode: GlassMode = .always
    ) {
        self.shape = shape
        self.pointSize = pointSize
        self.glassMode = glassMode
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: shape.width, height: shape.height)))
        wantsLayer = true
        // §3.1's three buttons are circles, and a continuous curve at half the
        // side is a squircle — see `RoundedMetric.cornerCurve`. The tiles stay
        // continuous, because they actually are squircles.
        layer?.cornerCurve = shape.cornerCurve
        updateGlass(animated: false)

        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        addSubview(glyph)
        setSymbol(symbolName)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Content

    /// Swaps the glyph — reload → stop while loading (§3.1), speaker → speaker
    /// slash when muted (§3.4).
    func setSymbol(_ name: String) {
        glyph.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        glyph.contentTintColor = nil
        refresh()
    }

    /// A favicon instead of a symbol (§3.3). Template is off: a site's icon is
    /// its own colours, not chrome ink.
    func setImage(_ image: NSImage?) {
        glyph.image = image
        image?.isTemplate = false
        glyph.contentTintColor = nil
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: shape.width, height: shape.height)
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let side = min(pointSize, min(bounds.width, bounds.height))
        glyph.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        ).pixelAligned
    }

    // MARK: - State

    private func refresh() {
        // §21.4 has no "disabled" ink; `tertiary` is the dimmest tier that still
        // clears the floor, and is used in place of §3.1's unreadable 35 %.
        let ink: NSColor
        if !isEnabled {
            ink = Tokens.Text.tertiary
        } else {
            ink = (isHovering || isPressed || isSelected) ? Tokens.Text.primary : Tokens.Text.secondary
        }
        if glyph.image?.isTemplate ?? true { glyph.contentTintColor = ink }
        needsDisplay = true
        setAccessibilityEnabled(isEnabled)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = shape.cornerRadius
        layer.cornerCurve = shape.cornerCurve
        // **No ring.** Selection is `updateGlass`; keyboard focus is AppKit's
        // own focus ring, drawn through `drawFocusRingMask` below. A border
        // here used to be the accent-coloured highlight this app does not have.
        //
        // A `.dormant` button keeps a *plate* instead: the §3.4 wash and the
        // same hairline every other glass surface carries, so a pinned tile is
        // still a tile when it is not the one you are on. Dormant meant
        // "invisible" for one build and the grid read as icons floating on the
        // sidebar with nothing under them — which is not what the reference
        // shows either.
        let plated = glassMode == .dormant
        layer.borderWidth = plated ? Tokens.Metric.hairline : 0
        layer.borderColor = plated ? Tokens.Line.border.cgColor : nil
        // The well stays under the glass rather than swapping out from under
        // it: the material is clear, so a lit tile is the same recess with
        // sheen on it, which is what the reference shows.
        layer.backgroundColor = plated ? Tokens.Surface.well.cgColor : nil
    }

    /// Whether the material is showing right now.
    private var wantsGlass: Bool {
        switch glassMode {
        case .always: true
        case .dormant: isHovering || isPressed || isSelected
        }
    }

    private func updateGlass(animated: Bool) {
        let target: CGFloat = wantsGlass ? 1 : 0
        // The plate under the glass comes and goes with it.
        needsDisplay = true
        // Nothing to fade out of: a dormant button that has never been reached
        // has no backing, and building one to set it to zero is the cost this
        // is avoiding.
        guard let view = glass ?? (target > 0 ? makeGlass() : nil) else { return }
        guard animated else {
            view.alphaValue = target
            return
        }
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = target
        }
    }

    /// Builds the backing the first time it is needed, below everything else.
    private func makeGlass() -> NSView {
        let view = Glass.apply(
            .control,
            to: self,
            cornerRadius: shape.cornerRadius,
            cornerCurve: shape.cornerCurve
        )
        view.alphaValue = 0
        glass = view
        return view
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Hover (§6, 0.10 s)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering, isEnabled else { return }
        isHovering = hovering
        updateGlass(animated: true)
        Tokens.Motion.animate(Tokens.Motion.controlHover) { context in
            context.allowsImplicitAnimation = true
            refresh()
        }
    }

    // MARK: - Activation

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        press = event
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        press = nil
        refresh()
        if isEnabled, inside { onActivate?() }
    }

    /// **The gesture is handed on, not started here.** §6.6's lift is one
    /// tracked drag from the press to the mouse-up — see `SidebarTabDrag.swift`
    /// — so this passes the original press along the moment the pointer has
    /// moved far enough to mean it, and takes no further part.
    override func mouseDragged(with event: NSEvent) {
        guard let onDragOut, let press, isEnabled else { return }
        let from = convert(press.locationInWindow, from: nil)
        let to = convert(event.locationInWindow, from: nil)
        guard abs(to.x - from.x) >= Tokens.Metric.dragThreshold
            || abs(to.y - from.y) >= Tokens.Metric.dragThreshold
        else { return }
        isPressed = false
        self.press = nil
        refresh()
        onDragOut(press)
    }

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

    override func becomeFirstResponder() -> Bool {
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
