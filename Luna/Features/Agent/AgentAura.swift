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

    /// Whether Astro is working, which sets the light moving.
    var isLively = false {
        didSet { if isLively != oldValue { animate() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
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
        }
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
