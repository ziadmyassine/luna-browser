//
//  TabTile.swift
//  Luna
//
//  The icon an agent gives one of its tabs (`label_tab`): an SF Symbol in
//  white on a rounded tile of one colour, drawn at a favicon's size so it
//  takes the favicon's place in the row. The tile's corner is the settings
//  tiles' proportion (`SettingsSymbolTile.cornerRatio`), so the two kinds of
//  tile in Luna are one shape.
//

import AppKit

@MainActor
enum TabTile {

    private static var cache: [String: NSImage] = [:]

    /// The tile, or nil for a colour Luna does not know or a symbol macOS
    /// does not have.
    static func image(symbol: String, colour name: String, side: CGFloat = Tokens.Metric.faviconSize) -> NSImage? {
        let key = "\(symbol)|\(name)|\(side)"
        if let cached = cache[key] { return cached }
        guard let colour = colour(named: name),
              let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                  .withSymbolConfiguration(.init(pointSize: side * 0.56, weight: .semibold)) else { return nil }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let radius = side * SettingsSymbolTile.cornerRatio
            colour.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            let tinted = NSImage(size: glyph.size, flipped: false) { box in
                glyph.draw(in: box)
                NSColor.white.set()
                box.fill(using: .sourceAtop)
                return true
            }
            let fit = min(rect.width * 0.64 / max(glyph.size.width, glyph.size.height), 1)
            let size = NSSize(width: glyph.size.width * fit, height: glyph.size.height * fit)
            tinted.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }

    /// `ControlCall.tabColours`, as macOS's own system colours, a little
    /// deeper than the label colours so white reads on every one.
    static func colour(named name: String) -> NSColor? {
        palette[name]
    }

    private static let palette: [String: NSColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen,
        "mint": .systemMint, "teal": .systemTeal, "cyan": .systemCyan, "blue": .systemBlue,
        "indigo": .systemIndigo, "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown,
        "gray": .systemGray
    ]
}
