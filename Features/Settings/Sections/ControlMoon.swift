//
//  ControlMoon.swift
//  Luna
//
//  The moon Luna Control's pane draws, large in the sky and small in each
//  permission card: a surface image made once per size, the outline of its lit
//  part for a phase, and the one routine that puts the two together.
//
//  Every caller draws into a flipped view, so the geometry here is y-down.
//

import AppKit

@MainActor
enum ControlMoon {

    /// The outline of the lit part. `phase` 0 is a new moon and 1 a full one,
    /// lit from the trailing side as a waxing moon is.
    ///
    /// The trailing half-disc, closed by a half-ellipse whose width runs from
    /// `radius` bulging trailing (nothing lit) through a straight line (half)
    /// to `radius` bulging leading (all of it).
    static func litPath(center: CGPoint, radius: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        let squash = max(abs(1 - 2 * min(max(phase, 0), 1)), 0.0001)
        let ellipse = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: squash, y: 1)
        if phase >= 0.5 {
            path.addArc(center: .zero, radius: radius, startAngle: .pi / 2, endAngle: .pi * 1.5,
                        clockwise: false, transform: ellipse)
        } else {
            path.addArc(center: .zero, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2,
                        clockwise: true, transform: ellipse)
        }
        path.closeSubpath()
        return path
    }

    /// How the moon is lit: its phase, how strongly it glows, and how much of
    /// the dark side shows by earthshine.
    struct Light {
        var phase: CGFloat
        var glow: CGFloat
        var earthshine: CGFloat
    }

    /// The whole moon: its glow, the unlit disc at `earthshine`, and the lit
    /// part over it.
    static func draw(in context: CGContext, center: CGPoint, radius: CGFloat, light: Light, scale: CGFloat) {
        let phase = light.phase
        if light.glow > 0.001 { drawGlow(in: context, center: center, radius: radius, strength: light.glow) }
        guard let surface = surface(radius: radius, scale: scale) else { return }
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        context.saveGState()
        context.setAlpha(light.earthshine)
        drawUpright(surface, in: disc, context: context)
        context.restoreGState()
        guard phase > 0.002 else { return }
        context.saveGState()
        context.addPath(litPath(center: center, radius: radius, phase: phase))
        context.clip()
        drawUpright(surface, in: disc, context: context)
        context.restoreGState()
    }

    private static func drawGlow(in context: CGContext, center: CGPoint, radius: CGFloat, strength: CGFloat) {
        let colours = [
            Tokens.Moon.glowInner.withAlphaComponent(0.42 * strength).cgColor,
            Tokens.Moon.glowOuter.withAlphaComponent(0.13 * strength).cgColor,
            Tokens.Moon.glowOuter.withAlphaComponent(0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: srgb, colors: colours, locations: [0, 0.38, 1]) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: radius * 0.8,
            endCenter: center, endRadius: radius * 3.2,
            options: []
        )
    }

    /// A `CGImage` drawn into a flipped context lands upside down, so it is
    /// turned back the right way for the length of the one draw.
    static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: - The surface

    private static var surfaces: [String: CGImage] = [:]
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// The same moon every time: its marks come from a fixed seed, so the
    /// face does not change between two openings of Settings.
    static func surface(radius: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(radius)@\(scale)"
        if let made = surfaces[key] { return made }
        let side = Int((2 * radius * scale).rounded(.up))
        guard side > 0, let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Drawn y-down, like everything that shows it.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: CGFloat(side) / (2 * radius), y: -CGFloat(side) / (2 * radius))
        paint(context, radius: radius)
        let image = context.makeImage()
        surfaces[key] = image
        return image
    }

    private static func paint(_ context: CGContext, radius r: CGFloat) {
        let whole = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        context.addEllipse(in: whole)
        context.clip()
        radial(context, CGPoint(x: r * 1.3, y: r * 0.72), r * 0.05, CGPoint(x: r, y: r), r * 1.08,
               [Tokens.Moon.surfaceLit, Tokens.Moon.surfaceMid, Tokens.Moon.surfaceLimb], [0, 0.5, 1], fills: true)

        // The seas: soft darker patches, placed by hand so the face reads as
        // a moon's and not as noise.
        let seas: [(CGFloat, CGFloat, CGFloat)] = [
            (0.36, 0.32, 0.24), (0.56, 0.40, 0.17), (0.30, 0.58, 0.19), (0.60, 0.66, 0.13),
            (0.46, 0.52, 0.11), (0.72, 0.30, 0.09), (0.40, 0.74, 0.08)
        ]
        for (x, y, size) in seas {
            let point = CGPoint(x: x * 2 * r, y: y * 2 * r)
            let maria = Tokens.Moon.maria
            radial(context, point, 0, point, size * 2 * r,
                   [maria.withAlphaComponent(0.34), maria.withAlphaComponent(0.18), maria.withAlphaComponent(0)],
                   [0, 0.7, 1], fills: false)
        }

        var random = SeededRandom(seed: 11)
        for _ in 0..<34 { crater(context, radius: r, random: &random) }

        let ray = CGPoint(x: r * 0.84, y: r * 1.62)
        radial(context, ray, 0, ray, r * 0.22,
               [NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0)], [0, 1], fills: false)
        let centre = CGPoint(x: r, y: r)
        radial(context, centre, r * 0.62, centre, r,
               [Tokens.Moon.limbShade.withAlphaComponent(0), Tokens.Moon.limbShade.withAlphaComponent(0.38)],
               [0, 1], fills: true)
    }

    private static func crater(_ context: CGContext, radius r: CGFloat, random: inout SeededRandom) {
        let angle = random.next() * .pi * 2
        let distance = sqrt(random.next()) * r * 0.92
        let x = r + cos(angle) * distance, y = r + sin(angle) * distance
        let size = r * (0.018 + pow(random.next(), 2.2) * 0.075)
        context.setFillColor(Tokens.Moon.crater.withAlphaComponent(0.24).cgColor)
        context.fillEllipse(in: CGRect(x: x - size, y: y - size, width: 2 * size, height: 2 * size))
        // The rim catches the light on the side away from it.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.38).cgColor)
        context.setLineWidth(max(0.4, size * 0.28))
        context.addArc(center: CGPoint(x: x - size * 0.12, y: y + size * 0.08), radius: size * 0.86,
                       startAngle: 1.9, endAngle: 4.2, clockwise: false)
        context.strokePath()
    }

    // swiftlint:disable:next function_parameter_count
    private static func radial(
        _ context: CGContext, _ from: CGPoint, _ fromRadius: CGFloat, _ to: CGPoint, _ toRadius: CGFloat,
        _ colours: [NSColor], _ locations: [CGFloat], fills: Bool
    ) {
        guard let gradient = CGGradient(
            colorsSpace: srgb, colors: colours.map(\.cgColor) as CFArray, locations: locations
        ) else { return }
        context.drawRadialGradient(
            gradient, startCenter: from, startRadius: fromRadius, endCenter: to, endRadius: toRadius,
            options: fills ? [.drawsBeforeStartLocation, .drawsAfterEndLocation] : []
        )
    }
}

/// The same small generator on every run, so the moon's craters and the
/// sky's stars land in the same places each time Settings opens.
struct SeededRandom {

    private var state: UInt32

    init(seed: UInt32) { state = seed }

    /// 0 up to but not including 1.
    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B_79F5
        var value = (state ^ (state >> 15)) &* (1 | state)
        value = (value &+ ((value ^ (value >> 7)) &* (61 | value))) ^ value
        return CGFloat((value ^ (value >> 14))) / 4_294_967_296
    }
}
