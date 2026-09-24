//
//  Tokens+Accent.swift
//  Luna
//
//  §8.1's two accent colours. Split out of Tokens.swift when that file crossed
//  the 400-line limit.
//
//  §2's rule: no system blue in Luna's chrome. No accent selection, no accent
//  focus ring, no blue default button. `tint` covers the few places macOS owns
//  the answer, and §3.1's quit sheet is the one documented exception.
//

import AppKit

extension Tokens {

    // MARK: - Accent

    /// Fills, rings and glyphs only, never text. Both measure under 4.5:1 as
    /// text on Luna's surfaces: the user's accent at 4.02:1 on `base` light and
    /// 3.52:1 on `raised`, `systemRed` at 3.57:1 on `base` light. A view that
    /// needs coloured text asks for a token here instead of tinting
    /// `Text.primary` itself.
    enum Accent {
        /// The user's System Settings accent. System-backed: a browser that
        /// ignores the accent choice looks foreign on macOS.
        static var tint: NSColor { .controlAccentColor }

        /// Destructive affordances — close, delete, stop.
        static var danger: NSColor { .systemRed }

        /// §3.2's "Connection is Secure": the padlock in the site settings
        /// pop-out. `systemGreen`, the Mac's own colour for "this is fine".
        static var secure: NSColor { .systemGreen }

        /// The same words in the same green where green can carry text.
        /// `systemGreen` on a dark glass grey (40, 40, 45) is 7.3:1, over the
        /// 4.5 text needs; on a light one (235, 235, 240) it is 1.9:1, so in
        /// light the words keep `Text.primary` and the padlock alone is green.
        static var secureText: NSColor {
            NSColor(name: "luna.accent.secureText") { appearance in
                appearance.isDark ? .systemGreen : .labelColor
            }
        }

        /// Ink drawn on `tint`, for §3.1's quit sheet: the one control in Luna
        /// filled with the accent rather than washed with §3.4's ink.
        /// System-backed because the accent is a System Settings choice and is
        /// not always blue, so only AppKit knows what stays legible on it.
        ///
        /// The exception is the quit sheet alone. It is the only surface where
        /// one of the answers destroys the session, and the default answer has
        /// to be unmistakable rather than one wash-step louder than its
        /// neighbour. Selected tabs, focus rings and hovered rows are
        /// still ink and material.
        static var onTint: NSColor { .alternateSelectedControlTextColor }
    }
}
