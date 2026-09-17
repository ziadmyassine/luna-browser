//
//  Tokens+Ink.swift
//  Luna
//
//  The alpha table behind every translucent token, split out of `Tokens.swift`
//  when it crossed SwiftLint's 400-line file limit.
//
//  **This file carries no colour and no hex**, which is why it is the one that
//  moved: §8.1's "no literal hex outside `Tokens.swift`" is enforced by the
//  `private` hex initialiser's visibility, so any group holding a colour has to
//  stay in that file to keep the rule a matter of visibility rather than of
//  review. Alphas are numbers; they travel.
//

import Foundation

extension Tokens {

    // MARK: - Ink alphas

    /// The alpha table behind the translucent tokens, in one place so it has
    /// one source of truth — the tokens build their colours from it, and
    /// `TokenCheck` re-measures the Increase Contrast variants from it. That
    /// second reader is the reason this is not private: the contrast branch is
    /// unreachable through an `NSAppearance` on macOS 26 (file header), so a
    /// check that could not read these alphas could not verify §2 at all.
    enum Ink {
        /// 5.74 / 5.52 / 5.32 light, 6.77 / 6.11 / 6.53 dark over
        /// base / raised / glassFallback.
        static let secondary = InkAlphas(light: 0.60, dark: 0.60, contrastLight: 0.78, contrastDark: 0.78)
        /// The floor: 4.94 / 4.77 / 4.63 light, 5.12 / 4.73 / 4.99 dark.
        static let tertiary = InkAlphas(light: 0.56, dark: 0.50, contrastLight: 0.70, contrastDark: 0.70)
        /// Decorative at rest; 3.78:1 worst case once Increase Contrast lifts it.
        static let border = InkAlphas(light: 0.14, dark: 0.16, contrastLight: 0.50, contrastDark: 0.50)
        /// §2's hairline promotion. There is no rest value: below Increase
        /// Contrast the hairline *is* `.separatorColor`.
        static let hairlineContrast = 0.20

        /// §3.4's 6 %. Doubled under Increase Contrast: a 6 % wash is the first
        /// thing to vanish for the users who turn that setting on.
        static let hover = InkAlphas(light: 0.06, dark: 0.06, contrastLight: 0.12, contrastDark: 0.12)
        /// §3.4's selected pill, twice `hover` so the two stay separable.
        /// Capped by §21.4, not by taste — `TokenCheck.checkFills` re-derives
        /// what the row's text measures once this wash is under it.
        static let selected = InkAlphas(light: 0.12, dark: 0.12, contrastLight: 0.22, contrastDark: 0.22)
        /// §2's URL-pill fill. Low enough that the glass behind it still reads
        /// as glass, high enough to give the page wash something to blend into.
        static let chromeFill = InkAlphas(light: 0.08, dark: 0.10, contrastLight: 0.14, contrastDark: 0.16)
        /// §2's chrome tint — see `Surface.glassTint`. Well short of opaque:
        /// the whole point of §2 is that the chrome samples the desktop, and a
        /// tint heavy enough to hide that would be a coloured rectangle.
        /// Increase Contrast thickens it, because a surface that is barely
        /// there is exactly what that setting exists to firm up.
        static let glassTint = InkAlphas(light: 0.32, dark: 0.34, contrastLight: 0.48, contrastDark: 0.50)
        /// §2's frost — see `Surface.frost`. Half-strength, so the desktop is
        /// still legibly *there* behind the chrome; Increase Contrast thickens
        /// it toward the opaque plane, for the same reason the tint thickens.
        static let frost = InkAlphas(light: 0.46, dark: 0.50, contrastLight: 0.68, contrastDark: 0.72)
        /// `Surface.well` — a dormant control's recess. Deep enough in dark
        /// mode to read as cut into the plane rather than drawn on it; light
        /// mode needs far less, because a light surface shows a darkening at a
        /// much lower alpha.
        static let well = InkAlphas(light: 0.06, dark: 0.22, contrastLight: 0.12, contrastDark: 0.32)
        /// §3.1's 35 % dim. Exempt from §21.4 — see `Text.disabled`. It still
        /// gains under Increase Contrast, because "disabled" has to remain
        /// *legible as a control* even when it is not readable as text.
        static let disabled = InkAlphas(light: 0.35, dark: 0.35, contrastLight: 0.50, contrastDark: 0.50)
        /// §5's panel shadow — black in both themes, see `Shadow.popover`.
        static let popoverShadow = InkAlphas(light: 0.24, dark: 0.46, contrastLight: 0.40, contrastDark: 0.62)
    }
}
