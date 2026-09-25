//
//  Tokens+Tile.swift
//  Luna
//
//  The rounded tile a Settings section's symbol stands on, in the list and
//  at the head of its page. Grey glass with a white glyph, the same in both
//  appearances, as macOS draws the tiles in its own settings: a tile is an
//  object on the pane, not a tint of it. Luna Control's is the night sky
//  from `Tokens.Moon` instead, and About's is the app's own icon.
//

import AppKit

extension Tokens {

    enum Tile {
        /// The grey, lighter at the top-left than the bottom-right.
        static var top: NSColor { grey(0x9D_9D_A4) }
        static var bottom: NSColor { grey(0x5E_5E_64) }
        /// The sheen across the upper half, and the hairline and top edge that
        /// catch the light.
        static var sheen: NSColor { NSColor.white.withAlphaComponent(0.30) }
        static var rim: NSColor { NSColor.white.withAlphaComponent(0.35) }
        static var glyph: NSColor { .white }
        /// Luna Control's tile: the sky's two ends, a lighter night at the
        /// top-left, and the moon's own mid tone for its glyph.
        static var nightTop: NSColor { grey(0x2A_31_58) }
        static var nightGlyph: NSColor { Tokens.Moon.surfaceMid }

        private static func grey(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
