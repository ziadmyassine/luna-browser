//
//  Accessibility.swift
//  Luna
//
//  The display settings the chrome has to obey, read live. Split out of
//  Tokens.swift: nothing here is a colour, and half the app asks these
//  questions without asking for a token.
//
//  Measured on macOS 26.5: Increase Contrast is not an `NSAppearance`.
//  `NSAppearance(named: .accessibilityHighContrastAqua)` returns the identical
//  object as `.aqua` (`===`), so no dynamic-colour provider can observe the
//  setting. `increaseContrast` below is the only live signal, which is why the
//  tokens branch on it at resolve time and why a view that draws text or
//  hairlines must redraw on
//  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` rather than
//  on an appearance change, as `Glass` does.
//

import AppKit

extension Tokens {

    // MARK: - Accessibility (§21.2)

    /// The display settings the chrome has to obey (§21.2). Read live on every
    /// access: the user can flip any of them while Luna is running, and a value
    /// cached at launch is a bug that only shows up in a bug report.
    ///
    /// To react rather than merely re-read, observe
    /// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on
    /// `NSWorkspace.shared.notificationCenter`, as `Glass` does.
    enum A11y {
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        static var reduceTransparency: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }

        static var increaseContrast: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }

        /// §21.2 / §8: Spaces must be separable by icon and label, not gradient.
        static var differentiateWithoutColour: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        }
    }
}
