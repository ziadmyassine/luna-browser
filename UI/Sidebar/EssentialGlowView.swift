//
//  EssentialGlowView.swift
//  Luna
//
//  §3.3: the light on the pinned tile you are on, in the colour of that
//  site's own favicon — `FaviconTint` picks the colour, this draws it.
//
//  Three layers, each doing a different job. `ring` is a lit line just outside
//  the tile's hairline; the shadow on that ring is the bloom carrying past it,
//  derived from the border rather than a `shadowPath` so it follows the ring
//  instead of the box; and `bleed` is the little of the colour that gets inside
//  the glass, which is the difference between a ring round a tile and a tile
//  that has been lit.
//
//  Layers with a continuous corner, not a `CGPath`. There is no public API for
//  a squircle's outline — `CGPath(roundedRect:)` and `NSBezierPath` both give
//  circular arcs — so a stroked path round a §3.3 tile pinches at the corners
//  where the tile does not. A `CALayer` draws the real curve for nothing: set
//  `cornerCurve`, give it a border, and the shape is the tile's.
//
//  It sits over the tile, not under it. Under was the first build and the bleed
//  vanished: a selected tile carries `NSGlassEffectView`, which composites what
//  is behind the window (`Glass.swift`), so everything in the window behind it
//  is gone. The view answers no hit test — this is light.
//
//  One of these for the whole grid rather than one per tile: only one tile can
//  be the tab you are on.
//

import AppKit

@MainActor
final class EssentialGlowView: NSView {

    /// 1.06 → 1: the light flares out and settles, it does not grow in.
    ///
    /// Every other appear in Luna comes up from under 1 — §5's popover from
    /// 0.94, the Command Bar from 0.96 — and this one cannot, because it is a
    /// ring round a tile rather than a panel. Rendered at 0.88, 0.94, 1.00 and
    /// 1.06 over a real tile: anything under 1 puts the lit ring inside the
    /// tile's own hairline, with the grey line still showing outside it, and
    /// what that reads as is a second smaller box drawn on the tile. Starting
    /// wide, the ring is clear of the tile for the whole movement and the pop
    /// is light flaring rather than a shape changing size.
    private static let flare = 1.06

    /// Whether the glow is on. `alphaValue` is the animated answer and is
    /// somewhere between the two for a quarter of a second either way; this is
    /// what lit means to anything that is not a screen.
    private(set) var isLit = false

    /// The colour last lit. Kept after the glow goes out so the fade happens in
    /// the colour the user was looking at rather than in the next tile's.
    private var tint: NSColor?

    private let bleed = CALayer()
    private let ring = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Everything this view draws is outside its own bounds, or bleeds out
        // of them. Clipping would leave the ring and take the glow.
        clipsToBounds = false
        alphaValue = 0
        layer?.masksToBounds = false
        for sublayer in [bleed, ring] {
            sublayer.cornerCurve = .continuous
            sublayer.masksToBounds = false
            layer?.addSublayer(sublayer)
        }
        ring.borderWidth = Tokens.Metric.essentialsGlowRim
        ring.shadowRadius = Tokens.Metric.essentialsGlowReach
        ring.shadowOffset = .zero
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Light is not a control. The glow lies over the tile it belongs to,
    /// so without this every click on the selected pinned tab would land here
    /// and the tile underneath would never hear it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// §30.1: and it does not move the window either.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - State

    /// Lights the glow in `tint`, or puts it out when that is nil.
    ///
    /// - Parameter blooming: play the appear — the light coming up under the
    ///   tile — rather than simply being on. The grid passes true for a click
    ///   and false for the pass that builds the sidebar, where nothing was
    ///   clicked and a bloom on launch would announce a tab you did not pick.
    ///
    /// A click that moves the glow from one tile to another blooms from
    /// nothing rather than from where it was: the frame has already jumped to
    /// the new tile, and fading the remainder of the old light up to full there
    /// reads as the glow having always been on.
    ///
    /// - Parameter animated: false puts the light where it belongs in this
    ///   frame. §6's Space switch is the one caller that asks: the grid has
    ///   been replaced wholesale, and `essentialGlow` outlasts
    ///   `spaceSwitchCrossfade` by a third, so a light fading out of the Space
    ///   you left is still burning over the Space you arrived in, on a tile
    ///   that is no longer there. It is not the same light moving.
    func show(_ tint: NSColor?, blooming: Bool, animated: Bool = true) {
        if let tint { self.tint = tint }
        paint()
        isLit = tint != nil
        let target: CGFloat = isLit ? 1 : 0
        guard animated else {
            // Both of them: the alpha this is overriding and the flare that
            // may still be springing beside it are the only two animations
            // this view ever carries.
            return Tokens.Motion.immediately {
                layer?.removeAllAnimations()
                alphaValue = target
            }
        }
        guard blooming || target != alphaValue else { return }
        if blooming { alphaValue = 0 }
        Tokens.Motion.animate(Tokens.Motion.essentialGlow) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = target
        }
        guard blooming,
              let scale = Tokens.Motion.essentialGlow.springAnimation(keyPath: "transform.scale")
        else { return }
        scale.fromValue = Self.flare
        scale.toValue = 1.0
        layer?.add(scale, forKey: "essentialGlow")
    }

    // MARK: - Drawing

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { place() }
    }

    private func place() {
        let radius = Tokens.Metric.essentialsTile.cornerRadius
        let rim = Tokens.Metric.essentialsGlowRim
        bleed.frame = bounds
        bleed.cornerRadius = radius
        // The ring's border is drawn inside its own edge, so a frame one rim
        // proud of the tile puts the line in the rim of space immediately
        // outside it — clear of the tile's own hairline, touching it.
        ring.frame = bounds.insetBy(dx: -rim, dy: -rim)
        ring.cornerRadius = radius + rim
    }

    /// The three alphas, over whatever colour the tile is lit in.
    ///
    /// Resolved against this view's appearance, not the current one. The
    /// neutral tint is chrome ink (`FaviconTint.neutral`), which is a dynamic
    /// colour: asking it for a `cgColor` outside a drawing appearance gets
    /// whichever theme happened to be current, which in a layout pass is not
    /// reliably the window's. Multiplied rather than replaced for the same
    /// reason — the ink carries an alpha of its own and these are gauges of it.
    private func paint() {
        guard let tint else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let lit = tint.usingColorSpace(.sRGB) ?? tint
            let alpha = lit.alphaComponent
            Tokens.Motion.immediately {
                bleed.backgroundColor = lit
                    .withAlphaComponent(alpha * Tokens.Metric.essentialsGlowBleed).cgColor
                ring.borderColor = lit
                    .withAlphaComponent(alpha * Tokens.Metric.essentialsGlowRimAlpha).cgColor
                ring.shadowColor = lit.withAlphaComponent(1).cgColor
                ring.shadowOpacity = Float(alpha) * Tokens.Metric.essentialsGlowBloom
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }
}
