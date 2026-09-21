//
//  SiteMenuGlyph.swift
//  Luna
//
//  §3.2's sliders glyph — the one drawn mark in Luna's chrome.
//
//  There is no SF Symbol for it. The reference is two horizontal sliders,
//  and the family ships `slider.horizontal.3` (three, no box) and
//  `slider.horizontal.2.square` (two, in a box); the bare pair does not exist
//  under any name — checked against `CoreGlyphs.bundle`'s own availability
//  list, all 9,524 of them. Three looked crowded at 16 pt beside a domain, and
//  the box put a second rounded rectangle inside a rounded pill.
//
//  So it is drawn, once, as a template image: black ink with real holes in
//  it, which is what lets `contentTintColor` carry §21.2's Increase Contrast and
//  both appearances without this file ever naming a colour (contract rule 3).
//  The knobs are rings rather than discs for the same reason the reference draws
//  them that way — a filled dot at this size reads as a bullet, not a control.
//

import AppKit

@MainActor
enum SiteMenuGlyph {

    /// The glyph at `size` points wide. Cached: `NSImage` compares by identity,
    /// and §3.4's rows are rebuilt often enough that a fresh image per pass
    /// would make every pill look changed.
    static func image(size: CGFloat = Tokens.Metric.glyphSize) -> NSImage {
        if let cached = cache[size] { return cached }
        let image = draw(size: size)
        cache[size] = image
        return image
    }

    private static var cache: [CGFloat: NSImage] = [:]

    /// Proportions, as fractions of the width. Measured off the reference:
    /// the bars run the full width, the top knob sits right of centre and the
    /// bottom one left of it, and the ring is a little over a third of the
    /// glyph's height across.
    private static let barThickness: CGFloat = 1 / 8
    private static let ringDiameter: CGFloat = 5 / 12
    private static let ringWall: CGFloat = 1 / 10
    private static let topKnob: CGFloat = 0.62
    private static let bottomKnob: CGFloat = 0.36

    private static func draw(size: CGFloat) -> NSImage {
        // Four units tall for two bars and the gap between them; the ring is
        // what sets the height, not the bar.
        let height = (size * ringDiameter * 2).rounded() + 2
        let image = NSImage(size: NSSize(width: size, height: height), flipped: false) { rect in
            let bar = max(size * barThickness, 1)
            let ring = size * ringDiameter
            let rows = [rect.midY + ring / 2, rect.midY - ring / 2]
            let knobs = [topKnob, bottomKnob]

            NSColor.black.setFill()
            for centre in rows {
                NSBezierPath(
                    roundedRect: NSRect(x: rect.minX, y: centre - bar / 2, width: rect.width, height: bar),
                    xRadius: bar / 2,
                    yRadius: bar / 2
                ).fill()
            }
            for (centre, fraction) in zip(rows, knobs) {
                let x = rect.minX + rect.width * fraction
                NSBezierPath(ovalIn: NSRect(x: x - ring / 2, y: centre - ring / 2, width: ring, height: ring)).fill()
            }
            // The holes are punched, not painted. A background-coloured disc
            // would be a colour value in a file that is not `Tokens.swift`, and
            // it would be the wrong colour the moment the glyph sits on glass
            // rather than on the pill's well.
            NSGraphicsContext.current?.compositingOperation = .clear
            let inner = ring - 2 * max(size * ringWall, 1)
            for (centre, fraction) in zip(rows, knobs) {
                let x = rect.minX + rect.width * fraction
                NSBezierPath(
                    ovalIn: NSRect(x: x - inner / 2, y: centre - inner / 2, width: inner, height: inner)
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
