//
//  Tokens+Tile.swift
//  Luna
//
//  The rounded tile a Settings section's symbol stands on, in the list and
//  at the head of its page. Near-black with a coloured glyph, the same in
//  both appearances, as macOS draws the tiles in its own settings in dark
//  mode: a tile is an object on the pane, not a tint of it. Luna Control's
//  glyph is a violet-to-cyan gradient, the one tile that is not a single
//  colour.
//

import AppKit

extension Tokens {

    enum Tile {
        /// The black, a little lighter at the top than the bottom so the tile
        /// reads as a solid rather than a hole in the pane.
        static var top: NSColor { rgb(0x2C_2C_30) }
        static var bottom: NSColor { rgb(0x0A_0A_0C) }
        /// The hairline round it, which is what separates a black tile from a
        /// dark pane.
        static var rim: NSColor { NSColor.white.withAlphaComponent(0.16) }

        /// The glyph colours, macOS's dark-mode system colours, which are what
        /// its own settings tiles use. One per section, so a section is found by
        /// its colour as much as by its shape; most stay neutral.
        static var neutral: NSColor { rgb(0xD1_D1_D6) }
        static var white: NSColor { .white }
        static var blue: NSColor { rgb(0x0A_84_FF) }
        static var purple: NSColor { rgb(0xBF_5A_F2) }
        static var green: NSColor { rgb(0x30_D1_58) }
        /// Luna Control's gradient: the moon's glow, lavender to ice, at the
        /// saturation of the colours beside it. The glow's own pastels read
        /// as grey on a 22 pt glyph.
        static var controlFrom: NSColor { rgb(0xC7_7D_FF) }
        static var controlTo: NSColor { rgb(0x4F_D8_F5) }

        private static func rgb(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
