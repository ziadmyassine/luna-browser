//
//  SpaceCornerFillView.swift
//  Luna
//
//  The two corners `SpaceWashView` cannot reach.
//
//  **Why this is a second view and not a wider first one.** `ContentCardView`
//  rounds only its leading corners (§3.6 — the trailing pair is the window's
//  own), so in `.sidebar` the card leaves a `contentCardRadius` quarter-disc
//  notch at its top-leading and bottom-leading corners. What shows through the
//  notch is `WindowRootView`'s plain `Glass.sidebar` — the sidebar's own wash
//  never gets there, because the wash is a subview of the sidebar and
//  `ChromeHostView` sets `masksToBounds = true` on the way in (§7.2 needs that
//  clip: the sidebar slides in and out of it). So the sidebar's colour stopped
//  dead at its trailing edge and the two corners read as lighter notches
//  against it — "the colour does not go all the way", which is exactly what it
//  looked like.
//
//  This view is that patch and nothing else: it sits on the root plane
//  **below** the card, and its mask is the two notches. Everything else it
//  could paint is either covered by the opaque card or already painted by the
//  sidebar's own wash, and painting there as well would lay 16 % over 16 %.
//
//  It exists only in `.sidebar`. The other three states have no rounded card
//  corner to fill — `cardIsInset` is false for all of them — which is also why
//  fullscreen keeps the flat `Surface.fullScreenChrome` plane it was given
//  rather than picking up a Space's colour.
//

import AppKit
import BrowserKit

@MainActor
final class SpaceCornerFillView: NSView {

    /// The column the notches sit beside. The notch corners are at its
    /// trailing edge, and the ramp is computed as if this view were that wide,
    /// so the colour in a notch is the colour the sidebar ends on.
    var columnWidth: CGFloat = 0 {
        didSet {
            guard columnWidth != oldValue else { return }
            needsLayout = true
        }
    }

    private let fill = CAGradientLayer()
    private let shape = CAShapeLayer()
    private var gradient: GradientPair?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.startPoint = CGPoint(x: 0, y: 1)
        fill.mask = shape
        layer?.addSublayer(fill)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Never hit-tests: it is two 25 pt corners of decoration on the plane the
    /// page sits on.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The same pair the sidebar's wash is showing. Neutral paints nothing,
    /// by the same rule and through the same function — a Space with no colour
    /// must leave the corners exactly as they were.
    func show(_ gradient: GradientPair) {
        guard gradient != self.gradient else { return }
        self.gradient = gradient
        apply()
    }

    override func layout() {
        super.layout()
        // Bounds-derived, so it may never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            fill.frame = bounds
            // The ramp finishes at the column's trailing edge and holds its
            // last colour across the notches, so a notch is the colour the
            // sidebar ends on rather than a step further along the gradient.
            fill.endPoint = CGPoint(x: bounds.width > 0 ? columnWidth / bounds.width : 1, y: 0)
            shape.frame = bounds
            shape.path = Self.notches(in: bounds, besideColumnOf: columnWidth)
        }
        apply()
    }

    /// The card's two rounded leading corners, as the holes they leave.
    ///
    /// A notch is the corner square minus the quarter disc the radius takes out
    /// of it: bounded by the card's own top (or bottom) edge, by the sidebar's
    /// trailing edge, and by the arc between them.
    /// `static`, and taking its geometry rather than reading `bounds`, so the
    /// shape can be asserted in a test instead of eyeballed in a running window
    /// — the same reason `TrafficLightLayout` and `cardInsets` are pure.
    static func notches(in bounds: NSRect, besideColumnOf columnWidth: CGFloat) -> CGPath {
        let radius = Tokens.Metric.contentCardRadius
        let path = CGMutablePath()
        let x = columnWidth
        guard radius > 0, bounds.height > 2 * radius else { return path }

        // Top-leading.
        path.move(to: CGPoint(x: x, y: bounds.maxY))
        path.addLine(to: CGPoint(x: x + radius, y: bounds.maxY))
        path.addArc(
            center: CGPoint(x: x + radius, y: bounds.maxY - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: false
        )
        path.closeSubpath()

        // Bottom-leading.
        path.move(to: CGPoint(x: x, y: bounds.minY))
        path.addLine(to: CGPoint(x: x + radius, y: bounds.minY))
        path.addArc(
            center: CGPoint(x: x + radius, y: bounds.minY + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.closeSubpath()

        return path
    }

    private func apply() {
        guard let gradient else { return }
        let colors = SpaceWashView.washColors(for: gradient, in: effectiveAppearance).map(\.cgColor)
        Tokens.Motion.immediately { fill.colors = colors }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply()
    }
}
