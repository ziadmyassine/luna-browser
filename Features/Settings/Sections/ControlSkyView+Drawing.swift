//
//  ControlSkyView+Drawing.swift
//  Luna
//
//  Painting `ControlSkyView`, back to front: the sky, the stars, the far half
//  of each orbit and the lights on it, the moon, the near half and its lights,
//  the beams, and the shade under the title. Flipped, so y runs down.
//

import AppKit

extension ControlSkyView {

    // MARK: - Geometry

    var moonRadius: CGFloat {
        min(max(bounds.height * 0.24, Tokens.Metric.controlMoonRadiusMin), Tokens.Metric.controlMoonRadiusMax)
    }

    var moonCenter: CGPoint {
        let x = bounds.width > Tokens.Metric.controlSkyWide
            ? bounds.width - Tokens.Metric.controlMoonInset
            : bounds.width * 0.68
        let drift = Tokens.Metric.controlParallax
        return CGPoint(x: x + parallax.x * drift, y: bounds.height * 0.40 + parallax.y * drift * 2 / 3)
    }

    private func axes(orbit: Int) -> CGSize {
        let ratio = orbit == 0 ? Tokens.Metric.controlOrbitInner : Tokens.Metric.controlOrbitOuter
        return CGSize(width: ratio.width * moonRadius, height: ratio.height * moonRadius)
    }

    /// A point on an orbit, and how far round the near side it is: positive
    /// in front of the moon, negative behind it.
    func point(orbit: Int, angle: CGFloat) -> (point: CGPoint, depth: CGFloat) {
        let axes = axes(orbit: orbit), tilt = Tokens.Metric.controlOrbitTilt, centre = moonCenter
        let x = axes.width * cos(angle), y = axes.height * sin(angle)
        return (CGPoint(x: centre.x + x * cos(tilt) - y * sin(tilt), y: centre.y + x * sin(tilt) + y * cos(tilt)), sin(angle))
    }

    // MARK: - Painting

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        drawSky(context)
        drawStars(context)
        let placed = bodies.values.map { ($0, point(orbit: $0.satellite.orbit, angle: $0.angle)) }
        drawOrbits(context, nearHalfOnly: false)
        for (body, spot) in placed where spot.depth <= 0 { drawSatellite(context, body, spot) }
        let since = CACurrentMediaTime() - caughtAt
        let catchSpan = Tokens.Motion.controlPress.duration * 2
        let bump = since < catchSpan && !Tokens.Motion.reduceMotion ? sin(.pi * CGFloat(since / catchSpan)) : 0
        ControlMoon.draw(
            in: context, center: moonCenter, radius: moonRadius * (1 + (Tokens.Motion.pressSwell - 1) * bump),
            light: ControlMoon.Light(phase: phase, glow: phase + 0.35 * bump, earthshine: 0.12), scale: scale
        )
        drawOrbits(context, nearHalfOnly: true)
        for (body, spot) in placed where spot.depth > 0 { drawSatellite(context, body, spot) }
        drawBeams(context)
        drawShade(context)
    }

    private func drawSky(_ context: CGContext) {
        linear(context, [Tokens.Moon.skyTop, Tokens.Moon.skyBottom], from: .zero, to: CGPoint(x: 0, y: bounds.height))
        let haze = Tokens.Moon.haze, corner = CGPoint(x: bounds.width * 0.15, y: bounds.height * 1.05)
        radial(context, [haze.withAlphaComponent(0.12 + 0.08 * phase), haze.withAlphaComponent(0)],
               at: corner, radius: bounds.width * 0.6)
    }

    private func drawStars(_ context: CGContext) {
        let lift = 0.5 + 0.5 * phase
        let reach = Tokens.Metric.controlParallaxStars
        for star in stars {
            let twinkle = Tokens.Motion.reduceMotion ? 0.8 : 0.6 + 0.4 * sin(CGFloat(clock) * star.speed + star.offset)
            context.setFillColor(Tokens.Moon.star.withAlphaComponent(star.alpha * twinkle * lift).cgColor)
            let x = star.x * bounds.width + parallax.x * reach * star.depth
            let y = star.y * bounds.height + parallax.y * reach * star.depth
            context.fillEllipse(in: CGRect(x: x - star.radius, y: y - star.radius, width: 2 * star.radius, height: 2 * star.radius))
        }
    }

    /// The whole of each orbit behind the moon, then the near half again over
    /// it: the moon hides the far side, and the near side reads a little
    /// brighter, which is what gives the rings their depth.
    private func drawOrbits(_ context: CGContext, nearHalfOnly: Bool) {
        guard orbitAlpha > 0.01 else { return }
        for orbit in 0...1 {
            let axes = axes(orbit: orbit), centre = moonCenter
            context.saveGState()
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: Tokens.Metric.controlOrbitTilt)
            context.scaleBy(x: 1, y: axes.height / axes.width)
            context.addArc(center: .zero, radius: axes.width, startAngle: 0,
                           endAngle: nearHalfOnly ? .pi : .pi * 2, clockwise: false)
            context.restoreGState()
            let strength: CGFloat = (orbit == 0 ? 0.16 : 0.20) + (nearHalfOnly ? 0.06 : 0)
            context.setStrokeColor(Tokens.Moon.orbit.withAlphaComponent(strength * orbitAlpha).cgColor)
            context.setLineWidth(Tokens.Metric.hairline)
            context.setLineDash(phase: 0, lengths: orbit == 0 ? [] : [2, 5])
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawSatellite(_ context: CGContext, _ body: Body, _ spot: (point: CGPoint, depth: CGFloat)) {
        let alpha = body.alpha * orbitAlpha
        guard alpha > 0.01 else { return }
        let colour = body.satellite.colour, at = spot.point
        if body.satellite.isLive, !Tokens.Motion.reduceMotion { drawTrail(context, body, alpha: alpha) }
        radial(context, [colour.withAlphaComponent(0.55 * alpha), colour.withAlphaComponent(0)],
               at: at, radius: Tokens.Metric.controlSatelliteGlow)
        if let icon = body.satellite.icon {
            let side = Tokens.Metric.controlSatelliteIcon
            icon.draw(in: NSRect(x: at.x - side / 2, y: at.y - side / 2, width: side, height: side),
                      from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        } else {
            let core = Tokens.Metric.controlSatellite
            context.setFillColor(colour.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: at.x - core, y: at.y - core, width: 2 * core, height: 2 * core))
            let spark = core * 0.36
            context.setFillColor(NSColor.white.withAlphaComponent(0.9 * alpha).cgColor)
            context.fillEllipse(in: CGRect(
                x: at.x - 0.8 - spark, y: at.y - 0.8 - spark, width: 2 * spark, height: 2 * spark
            ))
        }

        // The name fades as the light goes round behind the moon.
        let named = alpha * 0.8 * min(max((spot.depth + 0.25) / 0.6, 0), 1)
        guard named > 0.02 else { return }
        // Shadowed, because on the trailing side the name can land on the moon.
        let shadow = NSShadow()
        shadow.shadowColor = Tokens.Moon.scrim.withAlphaComponent(0.8 * named)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        let label = NSAttributedString(string: body.satellite.name, attributes: [
            .font: Tokens.TypeScale.settingsCaption,
            .foregroundColor: Tokens.Moon.ink.withAlphaComponent(named),
            .shadow: shadow
        ])
        // Beside the light, on whichever side has room for it: near the
        // trailing edge a name on the right runs out of the sky.
        let size = label.size()
        let gap = body.satellite.icon == nil
            ? Tokens.Metric.controlSatelliteGlow * 0.8
            : Tokens.Metric.controlSatelliteIcon / 2 + Tokens.Metric.chromeGap / 2
        let fits = at.x + gap + size.width <= bounds.maxX - Tokens.Metric.chromeGap
        label.draw(at: CGPoint(x: fits ? at.x + gap : at.x - gap - size.width, y: at.y - size.height / 2))
    }

    /// The live app: a fading tail behind it and a ring that widens off it.
    private func drawTrail(_ context: CGContext, _ body: Body, alpha: CGFloat) {
        let colour = body.satellite.colour, steps = 12
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let behind = point(orbit: body.satellite.orbit, angle: body.angle - CGFloat(step) * 0.045).point
            let size = 1.6 * (1 - fraction * 0.75)
            context.setFillColor(colour.withAlphaComponent(alpha * (1 - fraction) * 0.5).cgColor)
            context.fillEllipse(in: CGRect(x: behind.x - size, y: behind.y - size, width: 2 * size, height: 2 * size))
        }
        let pass = CGFloat(clock.truncatingRemainder(dividingBy: Tokens.Motion.livePulse.duration) / Tokens.Motion.livePulse.duration)
        let at = point(orbit: body.satellite.orbit, angle: body.angle).point, ring = 4 + pass * 10
        context.setStrokeColor(colour.withAlphaComponent((1 - pass) * 0.65 * alpha).cgColor)
        context.setLineWidth(1.2)
        context.strokeEllipse(in: CGRect(x: at.x - ring, y: at.y - ring, width: 2 * ring, height: 2 * ring))
    }

    /// Each beam is a short bright stroke running from the app's light to the
    /// moon's edge, drawn as a few segments getting brighter toward the head.
    private func drawBeams(_ context: CGContext) {
        let now = CACurrentMediaTime(), centre = moonCenter
        for beam in beams {
            guard let body = bodies[beam.id] else { continue }
            let progress = Tokens.Motion.moonBeam.progress(at: now - beam.start)
            let start = point(orbit: body.satellite.orbit, angle: body.angle).point
            let dx = centre.x - start.x, dy = centre.y - start.y, length = max(hypot(dx, dy), 1)
            let end = CGPoint(x: centre.x - dx / length * moonRadius, y: centre.y - dy / length * moonRadius)
            let head = progress, tail = max(0, head - 0.4), segments = 8
            context.saveGState()
            context.setShadow(offset: .zero, blur: 10, color: body.satellite.colour.cgColor)
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            for index in 0..<segments {
                let from = tail + (head - tail) * CGFloat(index) / CGFloat(segments)
                let to = tail + (head - tail) * CGFloat(index + 1) / CGFloat(segments)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.95 * CGFloat(index + 1) / CGFloat(segments)).cgColor)
                context.move(to: CGPoint(x: start.x + (end.x - start.x) * from, y: start.y + (end.y - start.y) * from))
                context.addLine(to: CGPoint(x: start.x + (end.x - start.x) * to, y: start.y + (end.y - start.y) * to))
                context.strokePath()
            }
            context.restoreGState()
        }
    }

    /// Darker behind the title and the switch, so white type reads over
    /// whatever star or orbit passes under it.
    private func drawShade(_ context: CGContext) {
        let shade = Tokens.Moon.scrim
        linear(context, [shade.withAlphaComponent(0.7), shade.withAlphaComponent(0)],
               from: .zero, to: CGPoint(x: bounds.width * 0.58, y: 0))
        linear(context, [shade.withAlphaComponent(0.55), shade.withAlphaComponent(0)],
               from: CGPoint(x: 0, y: bounds.height), to: CGPoint(x: 0, y: bounds.height * 0.45))
    }

    // MARK: - Gradients

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private func linear(_ context: CGContext, _ colours: [NSColor], from: CGPoint, to: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: Self.srgb, colors: colours.map(\.cgColor) as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private func radial(_ context: CGContext, _ colours: [NSColor], at centre: CGPoint, radius: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: Self.srgb, colors: colours.map(\.cgColor) as CFArray, locations: nil) else { return }
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
    }
}
