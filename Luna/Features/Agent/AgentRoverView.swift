//
//  AgentRoverView.swift
//  Luna
//
//  The agent's face: Astro, a small moon-white helmet with a dark glass
//  visor, two eyes behind it and a light on each ear. It blinks while it
//  waits, looks about while it thinks, bobs with its ears lit while it works,
//  hops and smiles when it is done and droops when something went wrong.
//
//  Drawn in layers in a 100 × 100 square and scaled to the view, so one
//  drawing serves the panel's header and its empty state. In the moon's
//  colours (`Tokens.Moon`), the same in both appearances: it is a character,
//  not a surface. Under Reduce Motion it holds still and only its face changes.
//

import AppKit

@MainActor
final class AgentRoverView: NSView {

    enum Mood: Equatable {
        case idle, thinking, working, happy, sad, stopped
    }

    var mood: Mood = .idle {
        didSet { if mood != oldValue { applyMood() } }
    }

    private let figure = CALayer()
    private let ground = CAShapeLayer()
    private let ears = [CAShapeLayer(), CAShapeLayer()]
    private let earLights = [CAShapeLayer(), CAShapeLayer()]
    private let helmet = CAShapeLayer()
    private let visor = CAGradientLayer()
    private let visorShape = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private var blinkTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(figure)
        figure.addSublayer(ground)
        for part in ears + earLights + [helmet, visor, shine, leftEye, rightEye] as [CALayer] { figure.addSublayer(part) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Luna's agent"))
        draw()
        applyMood()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            let side = min(bounds.width, bounds.height)
            figure.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: 100, height: 100)
            figure.setAffineTransform(CGAffineTransform(scaleX: side / 100, y: side / 100))
            figure.frame.origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopBlinking() } else { applyMood() }
    }

    // MARK: - The drawing, in a 100 × 100 square, y down

    private func draw() {
        figure.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        figure.anchorPoint = .zero

        ground.path = CGPath(ellipseIn: CGRect(x: 32, y: 86, width: 36, height: 5), transform: nil)
        ground.fillColor = Tokens.Moon.limbShade.withAlphaComponent(0.25).cgColor

        for (index, ear) in ears.enumerated() {
            let box = CGRect(x: index == 0 ? 13 : 80, y: 40, width: 7, height: 16)
            ear.path = CGPath(roundedRect: box, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            ear.fillColor = Tokens.Moon.surfaceLimb.cgColor
            let light = earLights[index]
            light.path = ear.path
            light.fillColor = Tokens.Moon.glowInner.cgColor
            light.shadowColor = Tokens.Moon.glowInner.cgColor
            light.shadowRadius = 4
            light.shadowOpacity = 0.9
            light.shadowOffset = .zero
            light.opacity = 0
        }

        helmet.path = CGPath(ellipseIn: CGRect(x: 19, y: 17, width: 62, height: 62), transform: nil)
        helmet.fillColor = Tokens.Moon.surfaceLit.cgColor

        // Dark glass, lit from the top left: shade to sky to the maria's blue.
        let visorBox = CGRect(x: 26, y: 34, width: 48, height: 28)
        visor.frame = visorBox
        visor.colors = [Tokens.Moon.limbShade.cgColor, Tokens.Moon.skyTop.cgColor, Tokens.Moon.maria.cgColor]
        visor.locations = [0, 0.6, 1]
        visor.startPoint = CGPoint(x: 0, y: 0)
        visor.endPoint = CGPoint(x: 1, y: 1)
        visorShape.path = CGPath(roundedRect: CGRect(origin: .zero, size: visorBox.size), cornerWidth: 14, cornerHeight: 14, transform: nil)
        visor.mask = visorShape

        let gleam = CGMutablePath()
        gleam.move(to: CGPoint(x: 33, y: 40))
        gleam.addQuadCurve(to: CGPoint(x: 43, y: 37), control: CGPoint(x: 37, y: 37))
        shine.path = gleam
        shine.fillColor = nil
        shine.strokeColor = NSColor.white.withAlphaComponent(0.7).cgColor
        shine.lineWidth = 2.5
        shine.lineCap = .round

        for eye in [leftEye, rightEye] {
            eye.strokeColor = NSColor.white.cgColor
            eye.lineCap = .round
            eye.shadowColor = Tokens.Moon.glowOuter.cgColor
            eye.shadowRadius = 3
            eye.shadowOpacity = 0.9
            eye.shadowOffset = .zero
        }
    }

    /// The eyes for a mood: round lights, arcs that smile or droop, or low
    /// slits when stopped. `open` closes the round ones for a blink.
    private func eyes(for mood: Mood, open: CGFloat = 1) -> (CGPath, CGPath, Bool) {
        func light(_ x: CGFloat) -> CGPath {
            let height = max(7.2 * open, 1.4)
            return CGPath(ellipseIn: CGRect(x: x - 3.6, y: 49 - height / 2, width: 7.2, height: height), transform: nil)
        }
        func arc(_ x: CGFloat, smile: Bool) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 4, y: smile ? 51 : 47))
            path.addQuadCurve(to: CGPoint(x: x + 4, y: smile ? 51 : 47), control: CGPoint(x: x, y: smile ? 44 : 54))
            return path
        }
        switch mood {
        case .happy: return (arc(42, smile: true), arc(58, smile: true), true)
        case .sad: return (arc(42, smile: false), arc(58, smile: false), true)
        case .idle, .thinking, .working, .stopped: return (light(42), light(58), false)
        }
    }

    private func setEyes(_ mood: Mood, open: CGFloat = 1) {
        let (left, right, stroked) = eyes(for: mood, open: mood == .stopped ? 0.35 : open)
        for (eye, path) in [(leftEye, left), (rightEye, right)] {
            eye.path = path
            eye.fillColor = stroked ? nil : NSColor.white.cgColor
            eye.lineWidth = stroked ? 2.6 : 0
        }
    }

    // MARK: - Moods

    private func applyMood() {
        stopBlinking()
        for layer in floating + [ground] { layer.removeAllAnimations() }
        setEyes(mood)
        visor.opacity = mood == .stopped || mood == .sad ? 0.8 : 1
        for light in earLights { light.opacity = mood == .thinking || mood == .working ? 1 : 0 }
        guard !Tokens.Motion.reduceMotion, window != nil else { return }
        switch mood {
        case .idle:
            startBlinking()
        case .thinking:
            glance()
            for light in earLights { pulse(light, duration: 0.9) }
        case .working:
            bob()
            for light in earLights { pulse(light, duration: 0.5) }
        case .happy:
            hop()
        case .sad, .stopped:
            break
        }
    }

    private func startBlinking() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.blink() }
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    private func blink() {
        guard mood == .idle else { return }
        let closed = eyes(for: .idle, open: 0.1)
        for (eye, path) in [(leftEye, closed.0), (rightEye, closed.1)] {
            let animation = CABasicAnimation(keyPath: "path")
            animation.toValue = path
            animation.duration = 0.09
            animation.autoreverses = true
            eye.add(animation, forKey: "blink")
        }
    }

    /// Eyes sliding to one side and the other, as if reading.
    private func glance() {
        for eye in [leftEye, rightEye] {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, -4, -4, 4, 4, 0]
            animation.keyTimes = [0, 0.15, 0.4, 0.55, 0.85, 1]
            animation.duration = 2.4
            animation.repeatCount = .infinity
            eye.add(animation, forKey: "glance")
        }
    }

    /// Floating over the dust, its shadow tightening as it rises.
    private func bob() {
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, -2.4, 0, -1.2, 0]
        rise.duration = 1.1
        rise.repeatCount = .infinity
        for part in floating { part.add(rise, forKey: "bob") }
        let squeeze = CAKeyframeAnimation(keyPath: "opacity")
        squeeze.values = [1, 0.6, 1, 0.8, 1]
        squeeze.duration = rise.duration
        squeeze.repeatCount = .infinity
        ground.add(squeeze, forKey: "bob")
    }

    /// Everything but the shadow, which stays on the ground.
    private var floating: [CALayer] { [helmet, visor, shine, leftEye, rightEye] + ears + earLights }

    private func hop() {
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0, -6, 0, -2, 0]
        jump.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        jump.duration = 0.6
        for part in floating { part.add(jump, forKey: "hop") }
    }

    private func pulse(_ layer: CALayer, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.3
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "pulse")
    }
}
