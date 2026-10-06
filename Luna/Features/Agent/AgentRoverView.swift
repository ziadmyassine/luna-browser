//
//  AgentRoverView.swift
//  Luna
//
//  The agent's face: Astro, a small moon-white helmet with a dark glass
//  visor, two eyes behind it and a light on each ear. The moods themselves —
//  what Astro does while it waits, thinks, works, writes, waves for the user,
//  finishes or fails — are in `AgentRoverView+Moods.swift`; this is the drawing.
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
        case idle, thinking, working, writing, waving, happy, sad, stopped
    }

    var mood: Mood = .idle {
        didSet { if mood != oldValue { applyMood() } }
    }

    let figure = CALayer()
    /// Everything that moves as one: helmet, visor, eyes and ears. Tilts,
    /// nods and hops turn this, so the parts never drift apart.
    let head = CALayer()
    let ground = CAShapeLayer()
    let ears = [CAShapeLayer(), CAShapeLayer()]
    let earLights = [CAShapeLayer(), CAShapeLayer()]
    let helmet = CAShapeLayer()
    let visor = CAGradientLayer()
    private let visorShape = CAShapeLayer()
    /// A band of light that sweeps the visor while Astro works.
    let scan = CAGradientLayer()
    let shine = CAShapeLayer()
    let eyes = CALayer()
    let leftEye = CAShapeLayer()
    let rightEye = CAShapeLayer()
    /// The thought bubble's three dots, over Astro's shoulder.
    let thoughts = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    /// Two small stars that pop when a task is done.
    let sparkles = [CAShapeLayer(), CAShapeLayer()]
    var timers: [Timer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(figure)
        figure.addSublayer(ground)
        figure.addSublayer(head)
        for part in ears + earLights + [helmet, visor, shine, eyes] as [CALayer] { head.addSublayer(part) }
        visor.addSublayer(scan)
        eyes.addSublayer(leftEye)
        eyes.addSublayer(rightEye)
        for part in thoughts + sparkles { figure.addSublayer(part) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Astro"))
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
            figure.setAffineTransform(CGAffineTransform(scaleX: side / 100, y: side / 100))
            figure.frame.origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTimers() } else { applyMood() }
    }

    // MARK: - The drawing, in a 100 × 100 square, y down

    private func draw() {
        figure.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        figure.anchorPoint = .zero
        // Turned about the middle of the helmet, which is where a head turns.
        head.bounds = figure.bounds
        head.position = CGPoint(x: 50, y: 48)
        head.anchorPoint = CGPoint(x: 0.5, y: 0.48)
        eyes.frame = figure.bounds

        ground.path = CGPath(ellipseIn: CGRect(x: 32, y: 86, width: 36, height: 5), transform: nil)
        ground.fillColor = Tokens.Moon.limbShade.withAlphaComponent(0.25).cgColor

        for (index, ear) in ears.enumerated() {
            let box = CGRect(x: index == 0 ? 13 : 80, y: 40, width: 7, height: 16)
            ear.path = CGPath(roundedRect: box, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            ear.fillColor = Tokens.Moon.surfaceLimb.cgColor
            let light = earLights[index]
            light.path = ear.path
            light.fillColor = Tokens.Moon.glowInner.cgColor
            glow(light, Tokens.Moon.glowInner, radius: 4)
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

        scan.frame = CGRect(x: -18, y: 0, width: 18, height: visorBox.height)
        scan.colors = [NSColor(white: 1, alpha: 0).cgColor, Tokens.Moon.glowOuter.withAlphaComponent(0.45).cgColor,
                       NSColor(white: 1, alpha: 0).cgColor]
        scan.startPoint = CGPoint(x: 0, y: 0.5)
        scan.endPoint = CGPoint(x: 1, y: 0.5)
        scan.opacity = 0

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
            glow(eye, Tokens.Moon.glowOuter, radius: 3)
        }
        drawThoughts()
        drawSparkles()
    }

    private func drawThoughts() {
        let dots: [(CGFloat, CGFloat, CGFloat)] = [(74, 14, 2.4), (82, 8, 3.2), (91, 1, 4.2)]
        for (dot, (x, y, radius)) in zip(thoughts, dots) {
            dot.path = CGPath(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), transform: nil)
            dot.fillColor = Tokens.Moon.surfaceMid.cgColor
            dot.strokeColor = Tokens.Moon.surfaceLimb.cgColor
            dot.lineWidth = 1
            dot.opacity = 0
        }
    }

    /// Four-pointed stars, the shape of a glint.
    private func drawSparkles() {
        for (star, (x, y, size)) in zip(sparkles, [(CGFloat(14), CGFloat(18), CGFloat(7)), (88, 26, 5.5)]) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: y - size))
            path.addQuadCurve(to: CGPoint(x: x + size, y: y), control: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x, y: y + size), control: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x - size, y: y), control: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x, y: y - size), control: CGPoint(x: x, y: y))
            star.path = path
            star.fillColor = Tokens.Moon.glowOuter.cgColor
            glow(star, Tokens.Moon.glowOuter, radius: 3)
            star.bounds = CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2)
            star.position = CGPoint(x: x, y: y)
            star.opacity = 0
        }
    }

    private func glow(_ layer: CALayer, _ colour: NSColor, radius: CGFloat) {
        layer.shadowColor = colour.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = 0.9
        layer.shadowOffset = .zero
    }

    // MARK: - Eyes

    /// The eyes for a mood: round lights, arcs that smile or droop, or low
    /// slits when stopped. `open` closes the round ones for a blink; `wide`
    /// makes them a little taller, for surprise and for asking.
    func eyePaths(for mood: Mood, open: CGFloat = 1) -> (CGPath, CGPath, Bool) {
        func light(_ x: CGFloat) -> CGPath {
            let tall: CGFloat = mood == .waving ? 9 : [.working, .writing].contains(mood) ? 6 : 7.2
            let height = max(tall * open, 1.4)
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
        case .idle, .thinking, .working, .writing, .waving, .stopped: return (light(42), light(58), false)
        }
    }

    func setEyes(_ mood: Mood, open: CGFloat = 1) {
        let (left, right, stroked) = eyePaths(for: mood, open: mood == .stopped ? 0.35 : open)
        for (eye, path) in [(leftEye, left), (rightEye, right)] {
            eye.path = path
            eye.fillColor = stroked ? nil : NSColor.white.cgColor
            eye.lineWidth = stroked ? 2.6 : 0
        }
    }
}
