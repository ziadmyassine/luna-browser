//
//  AgentGlyph.swift
//  Luna
//
//  Astro's face as a glyph, for the buttons that open the agent panel and the
//  rows an agent is working in: the helmet's outline, a nub for each ear and
//  the visor filled in, its two eyes cut out of it. A template image, so it takes the ink of whatever it sits
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
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let helmet = NSBezierPath(ovalIn: NSRect(x: 3.4 * unit, y: 3.6 * unit, width: 13.2 * unit, height: 13.2 * unit))
            helmet.lineWidth = max(1.5 * unit, 1.2)
            helmet.stroke()
            for x in [0.8, 17.4] {
                NSBezierPath(roundedRect: NSRect(x: x * unit, y: 8.2 * unit, width: 1.8 * unit, height: 4 * unit),
                             xRadius: 0.9 * unit, yRadius: 0.9 * unit).fill()
            }
            let visor = NSBezierPath(roundedRect: NSRect(x: 5.4 * unit, y: 7.4 * unit, width: 9.2 * unit, height: 5.6 * unit),
                                     xRadius: 2.8 * unit, yRadius: 2.8 * unit)
            for x in [7.6, 11.0] {
                visor.append(NSBezierPath(ovalIn: NSRect(x: x * unit, y: 9.1 * unit, width: 1.4 * unit, height: 2.2 * unit)))
            }
            visor.windingRule = .evenOdd
            visor.fill()
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
