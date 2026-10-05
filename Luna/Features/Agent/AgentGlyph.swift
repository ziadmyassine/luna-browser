//
//  AgentGlyph.swift
//  Luna
//
//  The rover's face as a glyph, for the buttons that open the agent panel and
//  the rows an agent is working in: a rounded screen with two eyes and the
//  antenna over it. A template image, so it takes the ink of whatever it sits
//  in, as an SF Symbol would.
//

import AppKit

@MainActor
enum AgentGlyph {

    private static var cache: [CGFloat: NSImage] = [:]

    /// The face at `pointSize`, drawn to the same box an SF Symbol of that
    /// size fills.
    static func image(pointSize: CGFloat) -> NSImage {
        if let cached = cache[pointSize] { return cached }
        let side = pointSize.rounded(.up) + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            let unit = rect.width / 20
            let line = max(1.4 * unit, 1.2)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            // The antenna and its lamp.
            let mast = NSBezierPath()
            mast.move(to: NSPoint(x: 13 * unit, y: 5.5 * unit))
            mast.line(to: NSPoint(x: 13 * unit, y: 2.5 * unit))
            mast.lineWidth = line
            mast.lineCapStyle = .round
            mast.stroke()
            NSBezierPath(ovalIn: NSRect(x: 11.6 * unit, y: 0.6 * unit, width: 2.8 * unit, height: 2.8 * unit)).fill()
            // The hull.
            let hull = NSBezierPath(roundedRect: NSRect(x: 2 * unit, y: 5.5 * unit, width: 16 * unit, height: 13 * unit),
                                    xRadius: 5.5 * unit, yRadius: 5.5 * unit)
            hull.lineWidth = line
            hull.stroke()
            // The eyes.
            for x in [7.0, 11.4] {
                NSBezierPath(roundedRect: NSRect(x: x * unit, y: 9.2 * unit, width: 1.9 * unit, height: 4.8 * unit),
                             xRadius: 0.95 * unit, yRadius: 0.95 * unit).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Agent")
        cache[pointSize] = image
        return image
    }
}

extension AgentGlyph {

    /// The face in one colour, for a layer, which cannot tint a template.
    static func tinted(pointSize: CGFloat, color: NSColor) -> NSImage {
        let face = image(pointSize: pointSize)
        return NSImage(size: face.size, flipped: false) { rect in
            face.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
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
