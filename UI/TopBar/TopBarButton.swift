//
//  TopBarButton.swift
//  Luna
//
//  Every icon control on the top bar: the sidebar toggle, back, a tab tile, a
//  capsule item (UI-SPEC §4). One class, because the four differ only in their
//  `RoundedMetric` and whether they carry glass.
//
//  It is an `NSButton` on purpose. §20.2 wants a visible focus ring, the key
//  view loop and space/return activation on every chrome control, and §21.1
//  wants an `AXButton` with a label — `NSButton` ships all four, and a bare
//  `NSView` would mean re-implementing them badly.
//
//  The one structural consequence: `Glass` hands back a *subview*, and a
//  subview draws over the cell, so the cell is left drawing nothing at all.
//  The stack is glass → hover fill → glyph, bottom to top, and `hitTest`
//  collapses it back onto the button so the decoration never eats a click.
//
//  Increase Contrast is not an appearance on macOS 26.5 (see the `Tokens`
//  header), so nothing here invalidates on its own: `TopBarView` owns the one
//  `NSWorkspace` observer for the whole bar and calls `applyTokens()` down the
//  tree.
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

    private let metric: RoundedMetric
    private let hoverFill = NSView()
    private let glyph = NSImageView()
    private var tracking: NSTrackingArea?
    private var isHovered = false

    /// - Parameters:
    ///   - metric: the drawn size and corner radius. Also the intrinsic size,
    ///     so an Auto Layout caller needs no size constraints.
    ///   - glass: §2's "Liquid Glass, clear" for controls and capsule items.
    ///     Tab tiles pass `false`: the reference draws them as a bare icon on
    ///     the bar, with no fill of their own until hover.
    init(metric: RoundedMetric, glass: Bool) {
        self.metric = metric
        super.init(frame: NSRect(origin: .zero, size: metric.size))

        isBordered = false
        title = ""
        wantsLayer = true

        if glass { Glass.apply(.control, to: self, cornerRadius: metric.cornerRadius) }

        hoverFill.wantsLayer = true
        hoverFill.layer?.cornerCurve = .continuous
        hoverFill.layer?.cornerRadius = metric.cornerRadius
        hoverFill.alphaValue = 0
        addSubview(hoverFill)

        glyph.imageScaling = .scaleProportionallyUpOrDown
        addSubview(glyph)

        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    /// An SF Symbol sized to the bar's glyph size. Nil only for a name the
    /// installed SF Symbols set does not have.
    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: TopBarMetrics.glyph, weight: .regular))
    }

    // MARK: - Geometry

    override var intrinsicContentSize: NSSize { metric.size }

    override func layout() {
        super.layout()
        hoverFill.frame = bounds
        let size = TopBarMetrics.glyph
        glyph.frame = NSRect(
            x: ((bounds.width - size) / 2).rounded(),
            y: ((bounds.height - size) / 2).rounded(),
            width: size,
            height: size
        )
    }

    /// The glass backing and the glyph are decoration. Without this they would
    /// win the hit test and swallow the click before the button saw it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Hover (§3.1: hover lifts the fill, not the border)

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
        Tokens.Motion.animate(Tokens.Motion.controlHover) { _ in
            self.hoverFill.animator().alphaValue = hovered ? 1 : 0
        }
    }

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
            if !isEnabled { setHovered(false) }
            applyTokens()
        }
    }

    /// Re-resolves every token this view holds by value. Called on creation, on
    /// an appearance change, and by `TopBarView` when the accessibility display
    /// options flip.
    func applyTokens() {
        // §3.1 dims a disabled control. There is no `disabledAlpha` token, and
        // the cell's own dimming is unavailable here (the glyph is a subview),
        // so the dimmest ink tier stands in — it is a real token and it is the
        // right *direction*. See the report: `Tokens.Text.disabled` is missing.
        glyph.contentTintColor = isEnabled ? Tokens.Text.primary : Tokens.Text.tertiary
        // ponytail: `Line.border` stands in for the missing `Surface.hoverFill`
        // (§3.4 asks for 6 %); swap the token in when it exists, nothing else
        // changes.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.hoverFill.layer?.backgroundColor = Tokens.Line.border.cgColor
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
