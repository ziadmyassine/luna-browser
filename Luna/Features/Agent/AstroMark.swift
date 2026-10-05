//
//  AstroMark.swift
//  Luna
//
//  Astro, small and alive, at the end of a sidebar row it is working in: the
//  icon (`AgentGlyph`) with its eyes as layers of their own, so it can blink,
//  glance about and float a little while the row sits there. All of it is
//  Core Animation, repeating on the render server, so a column of them costs
//  nothing between frames. Each starts at its own point in the loop, so a
//  folder of them does not blink in step. Still under Reduce Motion.
//

import AppKit

@MainActor
final class AstroMark: CALayer {

    static let name = "luna.astroMark"

    private let body = CALayer()
    private let eyes = CALayer()
    private let pupils = [CALayer(), CALayer()]

    init(side: CGFloat) {
        super.init()
        name = Self.name
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        body.frame = bounds
        body.contents = AgentGlyph.image(pointSize: side - 2, eyes: false)
        body.contentsGravity = .resizeAspect
        eyes.frame = bounds
        let unit = side / 20
        for (pupil, box) in zip(pupils, AgentGlyph.eyeBoxes) {
            // The drawing is y down; a layer's own space is y up.
            pupil.frame = CGRect(x: box.minX * unit, y: side - box.maxY * unit, width: box.width * unit, height: box.height * unit)
            pupil.cornerRadius = pupil.frame.width / 2
            pupil.backgroundColor = NSColor.white.cgColor
            eyes.addSublayer(pupil)
        }
        body.addSublayer(eyes)
        addSublayer(body)
        live()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func live() {
        guard !Tokens.Motion.reduceMotion else { return }
        let start = Double.random(in: 0 ... 4)
        let float = CAKeyframeAnimation(keyPath: "transform.translation.y")
        float.values = [0, 0.9, 0, 0.4, 0]
        float.duration = 2.6
        float.repeatCount = .infinity
        float.calculationMode = .cubic
        float.timeOffset = start
        body.add(float, forKey: "float")
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 1, 0.1, 1, 1]
        blink.keyTimes = [0, 0.9, 0.93, 0.96, 1]
        blink.duration = 4.2
        blink.repeatCount = .infinity
        blink.timeOffset = start
        for pupil in pupils { pupil.add(blink, forKey: "blink") }
        let glance = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let shift = bounds.width * 0.04
        glance.values = [0, 0, -shift, -shift, shift, shift, 0]
        glance.keyTimes = [0, 0.4, 0.45, 0.62, 0.67, 0.85, 0.9]
        glance.duration = 7.5
        glance.repeatCount = .infinity
        glance.timeOffset = start * 1.7
        eyes.add(glance, forKey: "glance")
    }
}

extension RowGlyphView {

    /// Astro, alive, in place of the glyph; nil takes it off.
    func showAstro(side: CGFloat?) {
        let existing = layer?.sublayers?.first { $0.name == AstroMark.name }
        guard let side else {
            existing?.removeFromSuperlayer()
            return
        }
        image = nil
        let mark = existing as? AstroMark ?? {
            let made = AstroMark(side: side)
            layer?.addSublayer(made)
            return made
        }()
        Tokens.Motion.immediately {
            mark.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        needsLayout = true
    }
}
