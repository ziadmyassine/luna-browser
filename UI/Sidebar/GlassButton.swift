//
//  GlassButton.swift
//  Luna
//
//  Every round or squircular glass control in the sidebar: the §3.1 toggle /
//  back / reload cluster, the §3.3 Essentials tiles, the §3.5 Space pill and
//  archive circles. One class, because they differ only in shape and glyph —
//  a second implementation would be a second set of hover, focus-ring and
//  VoiceOver bugs.
//
//  Hover lifts the fill, not the border (§3.1). It was the glyph alone
//  (`Text.secondary` → `Text.primary`) for a long time, because Luna had no
//  translucent hover colour to lift a surface with — `Surface.raised` and
//  `glassFallback` are opaque planes and the `Line.*` tokens are line colours.
//  `Surface.hover` and `Surface.selected` are this button's whole answer to a
//  pointer: 6 % over the material on hover, 12 % under a press.
//
//  A press swells it (`Motion.controlPress`): the material grows a twentieth
//  under the finger and springs back, which is what a Liquid Glass control does
//  on macOS 26. A button whose material belongs to the surface around it
//  (`GlassMode.none`) does not swell on its own — half a capsule growing inside
//  the other half is not a press — and hands the gesture to whoever owns that
//  capsule (`onPressChange`).
//

import AppKit

@MainActor
final class GlassButton: NSView {

    /// Fired on click, Space or Return.
    var onActivate: (() -> Void)?
    /// Makes the button draggable (§6.6 — an Essentials tile moves between
    /// sections). Handed the press that started the gesture, not the drag
    /// that noticed it, so whoever takes over can lift from where the finger
    /// went down; nil for a button that does not travel.
    var onDragOut: ((NSEvent) -> Void)?
    /// The right-click menu, built on demand so it always reflects the
    /// button's current tab rather than the one it was created with.
    var menuBuilder: (() -> NSMenu?)?
    /// Told when the button goes down and comes back up, for the one case a
    /// button cannot answer a press itself: `GlassMode.none`, where the
    /// material is the surface around it. `NavCluster` uses it to swell the
    /// capsule its two chevrons are halves of.
    var onPressChange: ((Bool) -> Void)?
    /// §3.3: this button is the selected one — the active Essential.
    ///
    /// Selection is the material, not a ring. It used to draw a 1 pt accent
    /// border, which is the system-blue highlight Luna does not have anywhere
    /// else. A `.dormant` button carries no glass until it is hovered or
    /// selected; arriving at it is the highlight.
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateGlass(animated: true)
            refresh()
        }
    }
    /// Whether a `.dormant` button keeps §3.3's well and hairline at rest.
    /// False on §4's plate, where the plate is the shelf and a resting tab is
    /// its icon on it; the box comes out, glass and all, under the pointer
    /// or the selection.
    var showsWell = true {
        didSet { needsDisplay = true }
    }
    /// §3.1: back dims when `canGoBack` is false.
    var isEnabled = true {
        didSet {
            refresh()
            // A button that goes dim under the pointer takes its wash with it:
            // `washColour` is nil while disabled, and nothing else would ask.
            Tokens.Motion.wash(wash.layer, to: washColour)
        }
    }

    /// When the button carries its glass.
    ///
    /// Glass is Luna's highlight. Nothing in the chrome turns blue to say
    /// "this one" — it turns to material. A `.dormant` button is a bare glyph
    /// on the plane it sits on until the pointer arrives or it becomes the
    /// selected one, and the material fades in and out on §6's control-hover
    /// curve. §3.3's pinned tiles are the case this was built for.
    enum GlassMode {
        case always
        case dormant
        /// Never. The button is a bare glyph because something around it is
        /// already the material — §3.5's Downloads/History pair sit inside one
        /// cylinder, and a second backing per button is what made the top bar's
        /// capsule read as three separate bright circles before it was built
        /// the same way (`TopBarActionCapsule`).
        case none
    }

    /// `internal` rather than `private` for `GlassButton+Keyboard.swift`, which
    /// draws the focus ring in this shape. That is the whole cost of the split.
    let shape: RoundedMetric
    private let pointSize: CGFloat
    private let glassMode: GlassMode
    private let glyph = NSImageView()
    /// The `.control` backing, built on demand.
    ///
    /// A dormant button that has never been hovered has no glass view at all.
    /// That matters: a sidebar with eight pinned tiles used to stand up eight
    /// live `NSGlassEffectView`s to hold at alpha 0, and every one of them
    /// re-composites when the app comes back to the foreground — which is a
    /// large part of what the sidebar's activation flash was made of.
    private var glass: NSView?
    /// §3.1's hover fill: a wash above the material and below the glyph, so
    /// it lifts the glass rather than replacing it. Its own view rather than
    /// this button's `backgroundColor`, which is already spoken for — a dormant
    /// tile's well is painted there, and a wash on top of a well is the well.
    private let wash = NSView()
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

        wash.wantsLayer = true
        wash.layer?.cornerCurve = shape.cornerCurve
        addSubview(wash)

        glyph.imageScaling = .scaleProportionallyUpOrDown
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
    ///
    /// The weight is set here and not at init, because it belongs to the
    /// mark rather than to the button: the same circle holds `arrow.clockwise`
    /// and then `xmark`, and §3.1's back chevron needs a lighter setting than
    /// either to draw their line. See `TypeScale.glyphWeight(for:)`.
    func setSymbol(_ name: String) {
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: Tokens.TypeScale.glyphWeight(for: name)
        )
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
        wash.frame = bounds
        wash.layer?.cornerRadius = min(shape.cornerRadius, min(bounds.width, bounds.height) / 2)
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

    /// §3.4's two washes: the pointer's, and the press's at twice it.
    ///
    /// A selected button is not washed. Selection is already the material
    /// (see `isSelected`), and a permanent 6 % on top of it would make the
    /// selected tile the one tile that cannot show a hover.
    private var washColour: NSColor? {
        guard isEnabled else { return nil }
        if isPressed { return Tokens.Surface.selected }
        return isHovering ? Tokens.Surface.hover : nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = shape.cornerRadius
        layer.cornerCurve = shape.cornerCurve
        // No ring. Selection is `updateGlass`; keyboard focus is AppKit's
        // own focus ring, drawn through `drawFocusRingMask` below. A border
        // here used to be the accent-coloured highlight this app does not have.
        //
        // A `.dormant` button keeps a plate instead: the §3.4 wash and the
        // same hairline every other glass surface carries, so a pinned tile is
        // still a tile when it is not the one you are on. Dormant meant
        // "invisible" for one build and the grid read as icons floating on the
        // sidebar with nothing under them — which is not what the reference
        // shows either.
        let plated = glassMode == .dormant && showsWell
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
        case .none: false
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
        // `cgColor` resolved against the appearance it was set in, so the wash
        // has to be re-resolved rather than merely re-drawn.
        Tokens.Motion.wash(wash.layer, to: washColour, animated: false)
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
        Tokens.Motion.wash(wash.layer, to: washColour)
    }

    /// The press, in the two places it shows: the fill under the pointer and
    /// the swell of the material itself.
    ///
    /// A `.none` button has no material of its own to swell — it is a bare
    /// glyph in somebody else's capsule — so it passes the press on instead of
    /// growing a fifth of a point inside a shape that is not moving.
    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refresh()
        Tokens.Motion.wash(wash.layer, to: washColour)
        onPressChange?(pressed)
        guard glassMode != .none else { return }
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    // MARK: - Activation

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        press = event
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        press = nil
        setPressed(false)
        if isEnabled, inside { onActivate?() }
    }

    /// The gesture is handed on, not started here. §6.6's lift is one
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
        self.press = nil
        setPressed(false)
        onDragOut(press)
    }
}
