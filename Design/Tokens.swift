//
//  Tokens.swift
//  Luna
//
//  THE ONLY FILE IN LUNA PERMITTED TO CONTAIN A COLOUR VALUE (§0.3, §8.1).
//  Everything visual references a semantic token from here. No hex, no
//  `NSColor.white`, no `.systemBlue` anywhere else. If a view needs a colour
//  that isn't here yet, add a named token here first.
//
//  Two rules for anything added below:
//    1. Semantic names only. `Surface.base`, never `gray900`.
//    2. Every colour resolves for light *and* dark (§8.1), live. Prefer a
//       semantic system colour — it already handles Increase Contrast and
//       Reduce Transparency (§21.2), which a hex value silently does not.
//       Only go custom where the system has no right answer, and say why.
//       Never sample `NSApp.effectiveAppearance` once at startup; a browser
//       window changes appearance while running and a stale colour is a bug.
//
//  Concurrency: `NSColor` is `NS_SWIFT_SENDABLE`, its semantic class
//  properties are nonisolated, and every token here is a *computed* static
//  with no storage — so there is no shared mutable state and no isolation is
//  required. Do not "fix" this file with `@MainActor` or `nonisolated(unsafe)`.
//
//  System-backed vs custom, at a glance:
//    system  Surface.base, Text.primary, Accent.tint, Accent.danger
//    custom  Surface.raised, Surface.glassFallback, Text.secondary,
//            Text.tertiary, Line.border
//    hybrid  Line.hairline (`.separatorColor` normally, promoted by hand
//            under Increase Contrast — see the comment there)
//
//  MEASURED, and it changes how every one of these is written: on macOS 26.5
//  **Increase Contrast is not an appearance.** `NSAppearance(named:)` maps
//  `.accessibilityHighContrastAqua` onto the *identical object* as `.aqua`
//  (verified: `===`), and the same for the dark and vibrant pairs. So a
//  dynamic provider cannot see the setting, and `NSColor` gets no appearance
//  change to invalidate against. The live signal is
//  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, which is why the
//  tokens below are computed statics that branch on `A11y` *before* building
//  their dynamic colour.
//
//  **UI agents: that means a view must redraw itself when the setting flips.**
//  Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on
//  `NSWorkspace.shared.notificationCenter` and invalidate — `Glass` does.
//
//  Ratios below are measured, not estimated: every one is re-derived by
//  `TokenCheck` against the live SDK, in both themes and both contrast modes.
//

import AppKit

enum Tokens {

    // MARK: - Surfaces

    /// Background planes (§8.1 `surface/0..3`), listed in the order they stack
    /// on screen rather than by brightness — light mode recedes by getting
    /// darker, dark mode by getting *lighter*, which is how AppKit's own
    /// sidebars behave.
    enum Surface {
        /// The opaque content plane: the §3.6 content card, and the deepest
        /// plane behind everything else. System-backed.
        /// #FFFFFF light / #1E1E1E dark.
        static var base: NSColor { .windowBackgroundColor }

        /// One visible step above `base`: control fills, Essentials tiles and
        /// the §5 downloads popover. Also the Reduce Transparency fallback for
        /// `Glass.Style.control` and `.popover`.
        ///
        /// Custom, because on macOS 26 every candidate system colour
        /// (`controlBackgroundColor`, `textBackgroundColor`) resolves to
        /// *exactly* `windowBackgroundColor` — #FFFFFF light / #1E1E1E dark —
        /// so a system-backed `raised` would be indistinguishable from `base`.
        /// These give a 1.14:1 (light) / 1.18:1 (dark) step: visible, not loud.
        static var raised: NSColor {
            dynamicColor(light: 0xF0_F0_F0, dark: 0x2B_2B_2B)
        }

        /// What sidebar / top-bar glass becomes under Reduce Transparency
        /// (§2, §21.2). Custom, and deliberately *not* `base`: §2 says glass
        /// falls back to `base`, but the §3.6 content card is `base` too, so
        /// obeying that literally makes the card vanish into the chrome and
        /// kills the whole floating read. This is the chrome plane instead —
        /// 1.25:1 from `base` in light, 1.09:1 in dark, and on the far side of
        /// `raised` in both, so controls still sit above the bar.
        static var glassFallback: NSColor {
            dynamicColor(light: 0xE4_E4_E4, dark: 0x23_23_23)
        }
    }

    // MARK: - Text

    /// Foreground text (§8.1 `textPrimary/Secondary/Tertiary`).
    ///
    /// §21.4 floor is 4.5:1 on *every* surface in *both* themes. Worst case for
    /// each token, measured over `base`/`raised`/`glassFallback`:
    ///   primary    12.2:1   secondary  5.3:1   tertiary  4.6:1
    ///
    /// That floor is what compresses the ramp: `tertiary` can only drop to
    /// ~0.56 alpha before it fails, which is barely a step below `secondary`.
    /// **Do not lean on alpha alone to separate the two** — use size and weight
    /// (`TypeScale`) for hierarchy and treat these as "meets contrast" tiers.
    enum Text {
        /// System-backed. Increase Contrast drives it to full opacity for free.
        static var primary: NSColor { .labelColor }

        /// Custom, because `.secondaryLabelColor` **fails §21.4**: it is
        /// black at 50 %, which measures 3.95:1 on a white window — under the
        /// 4.5:1 floor. 60 % is the smallest round alpha that clears it.
        /// 5.74 / 5.52 / 5.32 light, 6.77 / 6.11 / 6.53 dark.
        static var secondary: NSColor { inkColor("luna.text.secondary", Ink.secondary) }

        /// Custom for the same reason, worse: `.tertiaryLabelColor` is black at
        /// 26 % — **1.88:1**, less than half the floor. These are the lowest
        /// alphas that still clear 4.5:1 on the worst surface:
        /// 4.94 / 4.77 / 4.63 light, 5.12 / 4.73 / 4.99 dark.
        static var tertiary: NSColor { inkColor("luna.text.tertiary", Ink.tertiary) }
    }

    // MARK: - Lines

    /// Rules, dividers and control outlines (§8.1 `separator`, §1 `hairline`).
    enum Line {
        /// `.separatorColor` is the right *value* — it resolves to 9.8 % black /
        /// 9.8 % white, which is §1's "10 % white / 8 % black" hairline, and
        /// nothing hand-rolled beats it.
        ///
        /// **Qualified from M0:** whether it tracks Increase Contrast could
        /// not be verified — see the file header, the high-contrast
        /// appearances do not exist as separate objects on macOS 26.5, so
        /// there is no way to resolve the colour "under Increase Contrast"
        /// without toggling the real system setting. §2's "promote every
        /// hairline to 20 %" is therefore done here by hand. If AppKit already
        /// promotes it, this is redundant rather than wrong.
        static var hairline: NSColor {
            guard Tokens.A11y.increaseContrast else { return .separatorColor }
            return NSColor(name: "luna.line.hairline.contrast") { appearance in
                NSColor(white: appearance.isDark ? 1 : 0, alpha: Ink.hairlineContrast)
            }
        }

        /// The visible edge on a control or a selected row (§3.1, §3.4) — one
        /// step stronger than `hairline` so a glass button reads as a button.
        /// Custom: no system colour sits between `separatorColor` and
        /// `labelColor`.
        ///
        /// Under Increase Contrast this is §2's "adds a visible border to each
        /// control", so it jumps to 50 % — the lowest alpha that clears WCAG
        /// 1.4.11's 3:1 for a UI boundary on every surface (3.78:1 worst).
        static var border: NSColor { inkColor("luna.line.border", Ink.border) }
    }

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
    }

    // MARK: - Accessibility

    /// The three display settings the chrome has to obey (§21.2). Read **live**
    /// on every access — the user can flip any of them while Luna is running,
    /// and a value cached at launch is a bug that only shows up in a bug report.
    ///
    /// To react rather than merely re-read, observe
    /// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on
    /// `NSWorkspace.shared.notificationCenter` — `Glass` does exactly that.
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
    }

    // MARK: - Page-derived wash (§2)

    /// The §2 URL-pill wash: blends a page's `themeColor` into a chrome fill,
    /// backing the fraction off until `text` still clears §21.4's 4.5:1, and
    /// dropping the wash entirely rather than shipping unreadable chrome.
    ///
    /// This is the blend *helper* only. Deciding when to apply it, animating it
    /// over `Motion.themeWash`, and skipping it under Reduce Transparency
    /// (§2) are the consuming view's job.
    ///
    /// - Parameters:
    ///   - tint: the page colour, already bridged from `RGBA`.
    ///   - fill: the un-washed pill fill.
    ///   - fraction: §2's upper bound, 12–18 %. Stepped down in 2 % increments.
    ///   - text: the colour that must stay readable on the result.
    /// - Returns: a dynamic colour that re-clamps per appearance. Equal to
    ///   `fill` wherever even 12 % fails.
    static func wash(
        _ tint: NSColor,
        over fill: NSColor,
        upTo fraction: Double = 0.18,
        keeping text: NSColor
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            var amount = fraction
            while amount >= 0.12 {
                let candidate = fill.blended(toward: tint, fraction: amount, in: appearance)
                if text.contrastRatio(over: candidate, in: appearance) >= 4.5 {
                    return candidate
                }
                amount -= 0.02
            }
            return fill
        }
    }
}

// MARK: - Colour maths

extension NSColor {

    /// sRGB components resolved for `appearance`. Straight-alpha, 0...1.
    ///
    /// A dynamic colour only knows its value while an appearance is current,
    /// which is why this takes one rather than reading a global.
    func srgbComponents(for appearance: NSAppearance) -> SRGB {
        var out = SRGB(red: 0, green: 0, blue: 0, alpha: 0)
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = self.usingColorSpace(.sRGB) else { return }
            out = SRGB(
                red: Double(srgb.redComponent),
                green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent),
                alpha: Double(srgb.alphaComponent)
            )
        }
        return out
    }

    /// WCAG 2.1 contrast ratio of this colour **composited over** `background`.
    ///
    /// Compositing first is the point: Luna's text tokens are translucent ink,
    /// so comparing their raw values against a surface would report a ratio
    /// that never appears on screen.
    func contrastRatio(over background: NSColor, in appearance: NSAppearance) -> Double {
        let back = background.srgbComponents(for: appearance)
        let front = srgbComponents(for: appearance)
        let composited = SRGB(
            red: front.red * front.alpha + back.red * (1 - front.alpha),
            green: front.green * front.alpha + back.green * (1 - front.alpha),
            blue: front.blue * front.alpha + back.blue * (1 - front.alpha),
            alpha: 1
        )
        let lhs = composited.relativeLuminance, rhs = back.relativeLuminance
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    /// Linear sRGB blend toward `other`, resolved for `appearance`.
    func blended(toward other: NSColor, fraction: Double, in appearance: NSAppearance) -> NSColor {
        let from = srgbComponents(for: appearance)
        let to = other.srgbComponents(for: appearance)
        let mix = { (lhs: Double, rhs: Double) in lhs + (rhs - lhs) * fraction }
        return NSColor(
            srgbRed: mix(from.red, to.red),
            green: mix(from.green, to.green),
            blue: mix(from.blue, to.blue),
            alpha: from.alpha
        )
    }
}

/// Straight-alpha sRGB, 0...1. A named type rather than a tuple because four
/// unlabelled `Double`s in a row is how a red ends up in the blue channel.
struct SRGB: Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// WCAG 2.1 relative luminance. Alpha is ignored — composite first.
    var relativeLuminance: Double {
        let linear = { (channel: Double) in
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

// MARK: - Appearance helpers

extension NSAppearance {

    /// True for `darkAqua` and its vibrant / high-contrast variants.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Token constructors

/// A translucent token's alpha in each theme, plus the pair Increase Contrast
/// switches to.
struct InkAlphas: Sendable {
    var light: Double
    var dark: Double
    var contrastLight: Double
    var contrastDark: Double

    /// The pair in force right now.
    var inForce: (light: Double, dark: Double) {
        Tokens.A11y.increaseContrast ? (contrastLight, contrastDark) : (light, dark)
    }

    /// One specific variant, for `TokenCheck` — which has to reach the
    /// contrast branch without being able to turn the system setting on.
    func color(contrast: Bool, dark isDark: Bool) -> NSColor {
        let alpha = switch (isDark, contrast) {
        case (true, true): contrastDark
        case (true, false): dark
        case (false, true): contrastLight
        case (false, false): light
        }
        return NSColor(white: isDark ? 1 : 0, alpha: alpha)
    }
}

/// An opaque surface that re-resolves every time the appearance changes.
private func dynamicColor(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgb: dark) : NSColor(srgb: light)
    }
}

/// Translucent ink — black on light, white on dark. Translucent rather than a
/// fixed grey so the token keeps its ratio on whichever surface it lands on.
///
/// The Increase Contrast branch is taken *here*, not inside the provider,
/// because the provider cannot see the setting (file header). The two variants
/// get different colour names because an `NSColor` name is its identity.
private func inkColor(_ name: String, _ alphas: InkAlphas) -> NSColor {
    let contrast = Tokens.A11y.increaseContrast
    let pair = alphas.inForce
    return NSColor(name: NSColor.Name(contrast ? name + ".contrast" : name)) { appearance in
        let isDark = appearance.isDark
        return NSColor(white: isDark ? 1 : 0, alpha: isDark ? pair.dark : pair.light)
    }
}

private extension NSColor {
    /// 0xRRGGBB, sRGB, opaque. The only hex entry point in the codebase.
    convenience init(srgb hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
