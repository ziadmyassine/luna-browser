//
//  TopBarButton.swift
//  Luna
//
//  Every icon control on the top bar: an item in §4's action capsule. The
//  bar's tabs are not this: they are the sidebar's own tile and row
//  (`TopBarTabStrip`).
//
//  An `NSButton` on purpose: §20.2's focus ring, key view loop and space/return
//  activation and §21.1's labelled `AXButton` all come with it, and a bare
//  `NSView` would re-implement them badly. The fill and the glyph are subviews,
//  which draw over the cell, so the cell draws nothing and `hitTest` collapses
//  the stack back onto the button.
//
//  It answers a hover and a press, as `GlassButton` does in the sidebar; inside
//  §4's action capsule it hands the press up (`ownsItsMaterial`). Increase
//  Contrast is not an appearance (see the `Tokens` header), so `TopBarView`
//  owns the one observer and calls `applyTokens()` down the tree.
//

import AppKit

@MainActor
final class TopBarButton: NSButton {

    /// The glyph, favicon or nothing at all. Favicons are not template images,
    /// so `contentTintColor` leaves their own colours alone.
    var icon: NSImage? {
        get { glyph.image }
        set { glyph.image = newValue }
    }

    /// Told when the button goes down and comes back up. For the one case a
    /// button cannot answer a press itself — see `ownsItsMaterial`.
    var onPressChange: ((Bool) -> Void)?

    /// Whether the swell is this button's to perform. False for an item inside
    /// §4's action capsule, whose material belongs to the capsule.
    var ownsItsMaterial = true

    private let metric: RoundedMetric
    private let hoverFill = NSView()
    private let glyph = NSImageView()
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// - Parameter metric: the drawn size and corner radius. Also the intrinsic
    ///   size, so an Auto Layout caller needs no size constraints. No glass of
    ///   its own: the capsule it stands in is the material.
    init(metric: RoundedMetric) {
        self.metric = metric
        super.init(frame: NSRect(origin: .zero, size: metric.size))

        isBordered = false
        title = ""
        wantsLayer = true

        hoverFill.wantsLayer = true
        hoverFill.layer?.cornerCurve = .continuous
        hoverFill.layer?.cornerRadius = metric.cornerRadius
        addSubview(hoverFill)

        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// An SF Symbol sized to the bar's glyph size, and weighted so it draws the
    /// same line as the rest of them — see `TypeScale.glyphWeight(for:)`, for
    /// why one nominal weight is not one apparent weight. Nil only for a name
    /// the installed SF Symbols set does not have.
    static func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: TopBarMetrics.glyph,
            weight: Tokens.TypeScale.glyphWeight(for: name)
        )
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    // MARK: - Geometry

    override var intrinsicContentSize: NSSize { metric.size }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        hoverFill.frame = bounds
        let size = TopBarMetrics.glyph
        glyph.frame = NSRect(
            x: ((bounds.width - size) / 2).rounded(),
            y: ((bounds.height - size) / 2).rounded(),
            width: size,
            height: size
        )
    }

    /// The fill and the glyph are decoration. Without this they would
    /// win the hit test and swallow the click before the button saw it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Hover (§3.1: hover lifts the fill, not the border)

    /// §3.4a's right-click, built when it is asked for.
    ///
    /// Not `NSView.menu`, which is one menu assigned once: every item in a
    /// tab's menu states that tab's current answer — whether it is pinned,
    /// whether it is muted — and a menu held over from the last press would be
    /// checkmarks for another moment.
    var menuBuilder: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard isEnabled, hovered != isHovered else { return }
        isHovered = hovered
        refreshFill()
    }

    // MARK: - Press (§3.4's second wash, §6's `controlPress`)

    /// The press is taken around `NSControl`'s tracking, not instead of it.
    /// `super.mouseDown` does not return until the mouse comes back up — it
    /// runs the cell's own tracking loop, which is where `sendAction` happens —
    /// so the state is set on either side of that call. Re-implementing the
    /// tracking to get a notification in the middle of it would cost the key
    /// loop, the focus ring and `AXPress`, which are the four reasons this is
    /// an `NSButton` at all (see the file header).
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }

    /// AppKit's own way of saying "this button is down", which a key equivalent
    /// takes rather than the tracking loop above. `setPressed` is idempotent,
    /// so the two routes cannot double up.
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        setPressed(flag && isEnabled)
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refreshFill()
        onPressChange?(pressed)
        guard ownsItsMaterial else { return }
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    /// §3.4's two washes: the pointer's, and the press's at twice it. A
    /// disabled button is in neither — it does not answer a pointer at all.
    private var fillColour: NSColor? {
        guard isEnabled else { return nil }
        if isPressed { return Tokens.Surface.selected }
        return isHovered ? Tokens.Surface.hover : nil
    }

    private func refreshFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.hoverFill.layer, to: self.fillColour)
        }
    }

    /// §4: a control is not bar, so a press on it never moves the window.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Focus ring (§20.2)

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: metric.cornerRadius,
            yRadius: metric.cornerRadius
        ).fill()
    }

    // MARK: - Tokens

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                setHovered(false)
                setPressed(false)
            }
            applyTokens()
        }
    }

    /// Re-resolves every token this view holds by value. Called on creation, on
    /// an appearance change, and by `TopBarView` when the accessibility display
    /// options flip.
    func applyTokens() {
        // §3.1 dims a disabled control. There is no `Tokens.Text.disabled`,
        // and the cell's own dimming is unavailable here (the glyph is a
        // subview), so the dimmest ink tier stands in.
        glyph.contentTintColor = isEnabled ? Tokens.Text.primary : Tokens.Text.tertiary
        // §3.4's 6 % lift, and 12 % under a press.
        refreshFill()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
