//
//  AgentRoverView.swift
//  Luna
//
//  The agent's face: a small moon rover — a hull, a screen with two eyes, an
//  antenna with a lamp, two wheels — that shows what the agent is doing. It
//  blinks while it waits, looks about while it thinks, rolls while it works,
//  smiles when it is done and droops when something went wrong.
//
//  Drawn in layers in a unit square and scaled to the view, so one drawing
//  serves the panel's header and its empty state. In the moon's colours
//  (`Tokens.Moon`), the same in both appearances: it is a character, not a
//  surface. Under Reduce Motion it holds still and only its face changes.
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
    private let body = CAShapeLayer()
    private let screen = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private let mast = CAShapeLayer()
    private let lamp = CAShapeLayer()
    private let wheels = [CAShapeLayer(), CAShapeLayer()]
    private let spokes = [CAShapeLayer(), CAShapeLayer()]
    private var blinkTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(figure)
        for part in [mast, lamp, body, screen, leftEye, rightEye] { figure.addSublayer(part) }
        for (wheel, spoke) in zip(wheels, spokes) {
            figure.addSublayer(wheel)
            wheel.addSublayer(spoke)
        }
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

        mast.path = CGPath(rect: CGRect(x: 63, y: 14, width: 3, height: 16), transform: nil)
        mast.fillColor = Tokens.Moon.surfaceLimb.cgColor
        lamp.path = CGPath(ellipseIn: CGRect(x: 59.5, y: 7, width: 10, height: 10), transform: nil)
        lamp.fillColor = Tokens.Moon.glowInner.cgColor
        lamp.shadowColor = Tokens.Moon.glowInner.cgColor
        lamp.shadowRadius = 4
        lamp.shadowOpacity = 0.9
        lamp.shadowOffset = .zero

        body.path = CGPath(roundedRect: CGRect(x: 14, y: 28, width: 72, height: 50), cornerWidth: 20, cornerHeight: 20, transform: nil)
        body.fillColor = Tokens.Moon.surfaceLit.cgColor
        body.strokeColor = Tokens.Moon.surfaceLimb.cgColor
        body.lineWidth = 2.5

        screen.path = CGPath(roundedRect: CGRect(x: 23, y: 36, width: 54, height: 30), cornerWidth: 13, cornerHeight: 13, transform: nil)
        screen.fillColor = Tokens.Moon.skyTop.cgColor

        for eye in [leftEye, rightEye] {
            eye.fillColor = Tokens.Moon.glowOuter.cgColor
            eye.strokeColor = Tokens.Moon.glowOuter.cgColor
            eye.lineCap = .round
            eye.shadowColor = Tokens.Moon.glowOuter.cgColor
            eye.shadowRadius = 3
            eye.shadowOpacity = 0.8
            eye.shadowOffset = .zero
        }

        for (index, wheel) in wheels.enumerated() {
            let centre = CGPoint(x: index == 0 ? 30 : 70, y: 82)
            wheel.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            wheel.position = centre
            wheel.path = CGPath(ellipseIn: wheel.bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            wheel.fillColor = Tokens.Moon.maria.cgColor
            wheel.strokeColor = Tokens.Moon.limbShade.cgColor
            wheel.lineWidth = 2
            let spoke = spokes[index]
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 9, y: 4))
            path.addLine(to: CGPoint(x: 9, y: 14))
            path.move(to: CGPoint(x: 4, y: 9))
            path.addLine(to: CGPoint(x: 14, y: 9))
            spoke.path = path
            spoke.strokeColor = Tokens.Moon.surfaceMid.cgColor
            spoke.lineWidth = 1.5
            spoke.frame = wheel.bounds
        }
    }

    /// The eyes for a mood: open pills, arcs that smile, or low flat lines.
    private func eyes(for mood: Mood, open: CGFloat = 1) -> (CGPath, CGPath, Bool) {
        func pill(_ x: CGFloat) -> CGPath {
            let height = max(12 * open, 2)
            return CGPath(roundedRect: CGRect(x: x, y: 51 - height / 2, width: 8, height: height),
                          cornerWidth: 4, cornerHeight: min(4, height / 2), transform: nil)
        }
        func arc(_ x: CGFloat, smile: Bool) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: smile ? 53 : 49))
            path.addQuadCurve(to: CGPoint(x: x + 10, y: smile ? 53 : 49), control: CGPoint(x: x + 5, y: smile ? 44 : 56))
            return path
        }
        switch mood {
        case .happy: return (arc(36, smile: true), arc(54, smile: true), true)
        case .sad: return (arc(36, smile: false), arc(54, smile: false), true)
        case .stopped: return (pill(37).copy(using: nil) ?? pill(37), pill(55), false)
        case .idle, .thinking, .working: return (pill(37), pill(55), false)
        }
    }

    private func setEyes(_ mood: Mood, open: CGFloat = 1) {
        let (left, right, stroked) = eyes(for: mood, open: mood == .stopped ? 0.35 : open)
        for (eye, path) in [(leftEye, left), (rightEye, right)] {
            eye.path = path
            eye.fillColor = stroked ? nil : Tokens.Moon.glowOuter.cgColor
            eye.lineWidth = stroked ? 3 : 0
        }
    }

    // MARK: - Moods

    private func applyMood() {
        stopBlinking()
        for layer in [figure, leftEye, rightEye, lamp] + spokes { layer.removeAllAnimations() }
        setEyes(mood)
        lamp.opacity = mood == .stopped || mood == .sad ? 0.35 : 1
        guard !Tokens.Motion.reduceMotion, window != nil else { return }
        switch mood {
        case .idle:
            startBlinking()
        case .thinking:
            glance()
            pulse(lamp, duration: 0.9)
        case .working:
            roll()
            pulse(lamp, duration: 0.5)
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

    /// Wheels turning and the hull riding over the dust.
    private func roll() {
        for spoke in spokes {
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.byValue = Double.pi * 2
            turn.duration = 1.1
            turn.repeatCount = .infinity
            spoke.add(turn, forKey: "roll")
        }
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, -1.6, 0, -0.8, 0]
        bob.duration = 0.9
        bob.repeatCount = .infinity
        figure.add(bob, forKey: "bob")
    }

    private func hop() {
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0, -5, 0, -2, 0]
        jump.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        jump.duration = 0.6
        figure.add(jump, forKey: "hop")
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
