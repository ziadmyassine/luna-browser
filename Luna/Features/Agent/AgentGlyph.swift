//
//  AgentGlyph.swift
//  Luna
//
//  Astro as an icon, in its own colours, for the buttons that open the agent
//  panel, the rows an agent is working in, its pointer and Settings: the
//  white helmet with a hairline round it (so it holds its edge on a white
//  pane), the dark glass visor, two eyes and the lit ears. Never a template:
//  Astro is a character, and the same Astro on a dark bar and a light one.
//

import AppKit

@MainActor
enum AgentGlyph {

    private static var cache: [CGFloat: NSImage] = [:]

    /// Astro at `pointSize`, drawn to the same box an SF Symbol of that
    /// size fills.
    static func image(pointSize: CGFloat, eyes: Bool = true) -> NSImage {
        let key = eyes ? pointSize : -pointSize
        if let cached = cache[key] { return cached }
        let side = pointSize.rounded(.up) + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(in: rect, eyes: eyes)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = String(localized: "Astro")
        cache[key] = image
        return image
    }

    /// Where the eyes are in the 20-unit square, y down — for `AstroMark`,
    /// which draws them as layers of their own so they can blink.
    static let eyeBoxes = [NSRect(x: 7.3, y: 9.0, width: 1.6, height: 2.2), NSRect(x: 11.1, y: 9.0, width: 1.6, height: 2.2)]

    /// Astro in a 20-unit square, y down: `AgentRoverView`'s drawing, with
    /// the ears and eyes a little larger so they survive 14 points.
    static func draw(in rect: NSRect, eyes: Bool = true) {
        let unit = rect.width / 20
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: rect.minX + x * unit, y: rect.minY + y * unit, width: width * unit, height: height * unit)
        }
        Tokens.Moon.surfaceLimb.setFill()
        for x in [0.7, 17.5] {
            NSBezierPath(roundedRect: box(x, 8, 1.8, 4.6), xRadius: 0.9 * unit, yRadius: 0.9 * unit).fill()
        }
        let helmet = NSBezierPath(ovalIn: box(2.2, 2.4, 15.6, 15.6))
        Tokens.Moon.surfaceLit.setFill()
        helmet.fill()
        Tokens.Moon.surfaceLimb.setStroke()
        helmet.lineWidth = max(0.7 * unit, 0.8)
        helmet.stroke()
        let visor = NSBezierPath(roundedRect: box(4.6, 6.9, 10.8, 6.6), xRadius: 3.3 * unit, yRadius: 3.3 * unit)
        NSGradient(colors: [Tokens.Moon.limbShade, Tokens.Moon.skyTop, Tokens.Moon.maria], atLocations: [0, 0.6, 1],
                   colorSpace: .sRGB)?.draw(in: visor, angle: -60)
        NSColor.white.setFill()
        for eye in eyeBoxes where eyes {
            NSBezierPath(ovalIn: box(eye.minX, eye.minY, eye.width, eye.height)).fill()
        }
        if rect.width >= 22 {
            let gleam = NSBezierPath()
            gleam.move(to: NSPoint(x: rect.minX + 6.2 * unit, y: rect.minY + 8.4 * unit))
            gleam.curve(to: NSPoint(x: rect.minX + 8.6 * unit, y: rect.minY + 7.7 * unit),
                        controlPoint1: NSPoint(x: rect.minX + 6.8 * unit, y: rect.minY + 7.8 * unit),
                        controlPoint2: NSPoint(x: rect.minX + 7.8 * unit, y: rect.minY + 7.7 * unit))
            gleam.lineWidth = 0.6 * unit
            gleam.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.6).setStroke()
            gleam.stroke()
        }
    }
}

/// What every button that opens the agent panel does: the same as `⌘E`, sent
/// up the responder chain to whichever window is in front.
@MainActor
enum AgentPanelButton {
    static func toggle() {
        NSApp.sendAction(#selector(AppDelegate.toggleAgentPanel(_:)), to: nil, from: nil)
    }
}
