//
//  Tokens+Accent.swift
//  Luna
//
//  §8.1's two accent colours, and the one place in Luna that draws on top of
//  one.
//
//  Split out of `Tokens.swift` when that file crossed SwiftLint's 400-line
//  limit; nothing changed on the way across except the arrival of `onTint`,
//  which is what pushed it over.
//
//  **Read the note on `onTint` before adding anything here.** §2's rule is
//  that Luna's chrome has no system blue in it — no accent-coloured selection,
//  no accent focus ring, no blue default button anywhere — and `tint` exists
//  for the handful of places macOS itself owns the answer. §3.1's quit sheet
//  is the one deliberate exception, and it is documented as one rather than
//  treated as permission for the next.
//

import AppKit

extension Tokens {

    // MARK: - Accent

    /// **Fills, rings and glyphs only — never text.** Both are system-backed
    /// and both measure *under* 4.5:1 as text on Luna's surfaces: the user's
    /// accent at 4.02:1 on `base` light / 3.52:1 on `raised`, `systemRed` at
    /// 3.57:1 on `base` light. A view that needs coloured *text* must ask for
    /// a token here rather than tinting `Text.primary` itself.
    enum Accent {
        /// The user's System Settings accent. System-backed on purpose: a
        /// browser that ignores the accent choice looks foreign on macOS.
        static var tint: NSColor { .controlAccentColor }

        /// Destructive affordances — close, delete, stop. System-backed.
        static var danger: NSColor { .systemRed }

        /// Ink drawn **on** `tint`, for the one control in Luna that is filled
        /// with the accent rather than washed with §3.4's ink: §3.1's quit
        /// sheet. System-backed, because "what is legible on the accent the
        /// user picked" is a question only AppKit can answer — the accent is a
        /// System Settings choice and it is not always blue.
        ///
        /// **§2's "no system blue anywhere" still holds everywhere else**, and
        /// this is the exception rather than the end of the rule. A selected
        /// tab, a focus ring, a hovered row and a recommended button on one of
        /// Luna's own pages are all still ink and material. What is different
        /// about the quit sheet is that it is the only surface in the app where
        /// one of the answers destroys the session: it is the last thing
        /// between ⌘Q and every window closing, and Martin asked for the
        /// default answer to be unmistakable at a glance rather than one
        /// wash-step louder than the one beside it.
        static var onTint: NSColor { .alternateSelectedControlTextColor }
    }
}
