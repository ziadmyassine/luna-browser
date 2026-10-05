//
//  AgentAura.swift
//  Luna
//
//  The light behind the agent panel: Astro's lavender pooling under the
//  header and ice under the field, on the window's glass, so the column reads
//  as Astro's without a surface of its own. While Astro works the two drift
//  and breathe; at rest they hold still. Under Reduce Motion they never move.
//

import AppKit

@MainActor
final class AgentAura: NSView {

    private let top = CAGradientLayer()
    private let bottom = CAGradientLayer()
    private let shape = CAShapeLayer()

    /// The strip on the page's side that the light reaches under the page,
    /// and which side it is on. Only its two ends are lit — the notches the
    /// page's rounded corners leave. Lit the whole way down, the light showed
    /// through the page's hairline edge and the edge shimmered as it moved.
    var notches: (width: CGFloat, onLeading: Bool)? {
        didSet { needsLayout = true }
    }

    /// Whether Astro is working, which sets the light moving.
    var isLively = false {
        didSet { if isLively != oldValue { animate() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // The glows are wider than the column so their edges never show;
        // the column is where they stop, not the page beside it.
        layer?.masksToBounds = true
        layer?.mask = shape
        for glow in [top, bottom] {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(glow)
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha = Tokens.Astro.auraAlpha(dark: dark)
        top.colors = [Tokens.Astro.from.withAlphaComponent(alpha).cgColor, Tokens.Astro.from.withAlphaComponent(0).cgColor]
        bottom.colors = [Tokens.Astro.to.withAlphaComponent(alpha * 0.8).cgColor, Tokens.Astro.to.withAlphaComponent(0).cgColor]
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let width = bounds.width * 1.6
            // Layer space is y up: the lavender over the header, the ice under the field.
            top.frame = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - width * 0.42, width: width, height: width * 0.8)
            bottom.frame = CGRect(x: bounds.midX - width / 2, y: -width * 0.42, width: width, height: width * 0.7)
            shape.frame = bounds
            shape.path = Self.outline(of: bounds, notches: notches)
        }
    }

    /// The panel's own column, and a corner's square at each end of the strip.
    static func outline(of bounds: CGRect, notches: (width: CGFloat, onLeading: Bool)?) -> CGPath {
        guard let notches, notches.width > 0, notches.width < bounds.width else { return CGPath(rect: bounds, transform: nil) }
        let side = notches.width
        let path = CGMutablePath()
        let stripX = notches.onLeading ? bounds.minX : bounds.maxX - side
        let columnX = notches.onLeading ? bounds.minX + side : bounds.minX
        path.addRect(CGRect(x: columnX, y: bounds.minY, width: bounds.width - side, height: bounds.height))
        path.addRect(CGRect(x: stripX, y: bounds.minY, width: side, height: side))
        path.addRect(CGRect(x: stripX, y: bounds.maxY - side, width: side, height: side))
        return path
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animate()
    }

    private func animate() {
        for glow in [top, bottom] { glow.removeAllAnimations() }
        guard isLively, window != nil, !Tokens.Motion.reduceMotion else { return }
        for (glow, offset) in [(top, CGFloat(22)), (bottom, -18)] {
            let drift = CAKeyframeAnimation(keyPath: "transform.translation.x")
            drift.values = [0, offset, 0, -offset, 0]
            drift.duration = 7
            drift.repeatCount = .infinity
            drift.calculationMode = .cubic
            glow.add(drift, forKey: "drift")
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.6
            breathe.duration = 2.4
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            glow.add(breathe, forKey: "breathe")
        }
    }
}
