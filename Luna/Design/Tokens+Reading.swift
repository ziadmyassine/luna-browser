//
//  Tokens+Reading.swift
//  Luna
//
//  The page colours a reading page can be set to, and the syntax colours its
//  code is drawn in. A page colour is one colour whatever the system theme —
//  that is what choosing one means — so none of these are dynamic.
//
//  Paper and Night are the content plane pinned to one theme: `Surface.base`
//  and the text tokens resolved light or dark. Only Sepia is a colour of its
//  own. Ratios are WCAG, measured on the page's background and re-derived by
//  `TokenCheck`.
//

import AppKit

extension Tokens {

    enum Reading {

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

// An extension rather than nested in the enum above, for SwiftLint's nesting limit.
extension Tokens.Reading {

    enum Page: String, CaseIterable {
        case paper, sepia, night

        var isDark: Bool { self == .night }

        /// The theme this page's system-backed colours resolve in.
        var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }

        /// Paper #FFFFFF, Night #1E1E1E, via `Surface.base`.
        var background: NSColor { self == .sepia ? Tokens.Reading.rgb(0xF6_EF_E2) : Tokens.Surface.base }

        /// Paper 15.1:1, Sepia 10.5:1, Night 12.3:1.
        var text: NSColor { self == .sepia ? Tokens.Reading.rgb(0x43_34_22) : Tokens.Text.primary }

        /// Paper 5.7:1, Sepia 5.6:1, Night 6.8:1. Sepia's is opaque: brown
        /// ink at `Ink.secondary`'s 60 % comes out at 3.4:1.
        func secondary(contrast: Bool) -> NSColor {
            self == .sepia ? Tokens.Reading.rgb(0x6A_5D_4C) : Tokens.Ink.secondary.color(contrast: contrast, dark: isDark)
        }

        /// Paper 4.9:1, Sepia 5.0:1, Night 5.1:1.
        func tertiary(contrast: Bool) -> NSColor {
            self == .sepia ? Tokens.Reading.rgb(0x72_65_54) : Tokens.Ink.tertiary.color(contrast: contrast, dark: isDark)
        }

        /// Lines and the code-block wash are Luna's ink at its own alphas.
        /// Black ink reads on Sepia as it does on Paper, so it needs no
        /// brown of its own.
        func hairline(contrast: Bool) -> NSColor {
            contrast ? NSColor(white: isDark ? 1 : 0, alpha: Tokens.Ink.hairlineContrast) : .separatorColor
        }

        func border(contrast: Bool) -> NSColor { Tokens.Ink.border.color(contrast: contrast, dark: isDark) }

        func wash(contrast: Bool) -> NSColor { Tokens.Ink.hover.color(contrast: contrast, dark: isDark) }

        var syntax: Syntax { isDark ? .dark : .light }
    }

    /// Xcode's default theme's colours, which clear 4.5:1 on every page as
    /// they stand.
    struct Syntax {
        let keyword, string, comment, function, number: NSColor

        /// On Paper / Sepia: keyword 6.9 / 6.0, string 6.0 / 5.2,
        /// comment 5.4 / 4.7, function 5.9 / 5.1, number 10.8 / 9.4.
        static var light: Syntax {
            Syntax(
                keyword: Tokens.Reading.rgb(0x9B_23_93), string: Tokens.Reading.rgb(0xC4_1A_16), comment: Tokens.Reading.rgb(0x5D_6C_79),
                function: Tokens.Reading.rgb(0x32_6D_74), number: Tokens.Reading.rgb(0x1C_00_CF)
            )
        }

        /// On Night: keyword 5.8, string 5.8, comment 4.9, function 7.1,
        /// number 9.0.
        static var dark: Syntax {
            Syntax(
                keyword: Tokens.Reading.rgb(0xFC_5F_A3), string: Tokens.Reading.rgb(0xFC_6A_5D), comment: Tokens.Reading.rgb(0x7F_8C_98),
                function: Tokens.Reading.rgb(0x67_B7_A4), number: Tokens.Reading.rgb(0xD0_BF_69)
            )
        }

        var all: [(String, NSColor)] {
            [("kw", keyword), ("str", string), ("com", comment), ("fn", function), ("num", number)]
        }
    }
}
