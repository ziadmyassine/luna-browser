//
//  ColourMath.swift
//  Luna
//
//  The arithmetic behind `Tokens.swift`, and **no colour values**: WCAG
//  contrast, compositing, the ink constructors, and §2's page-derived wash.
//  Split out for the same reason `Metrics.swift` was — to keep `Tokens.swift`
//  under SwiftLint's file length limit — and for one more: `Tokens.swift`'s
//  header claims to be the only file in Luna containing a colour *value*, and
//  that claim is worth keeping literally true. Nothing here spells a colour;
//  every function takes one and hands one back.
//
//  The hex entry point deliberately did **not** move: `NSColor(srgb:alpha:)`
//  and `dynamicColor` stay private inside `Tokens.swift`, so §8.1's "no literal
//  hex outside this file" is enforced by visibility and not only by review.
//  `inkColor` is here because it takes alphas rather than hex.
//

import AppKit

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
    ///
    /// `background` must be a *plane* — something opaque. A translucent fill
    /// such as `Surface.hover` is not one; flatten it with
    /// `flattened(over:in:)` onto the surface underneath it first.
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

    /// This colour composited over `backdrop`, opaque — what the eye actually
    /// receives when a translucent fill sits on a plane.
    ///
    /// Opaque receivers are handed straight back, so this is free on the
    /// planes and only does work where there is translucency to resolve.
    func flattened(over backdrop: NSColor, in appearance: NSAppearance) -> NSColor {
        let front = srgbComponents(for: appearance)
        guard front.alpha < 1 else { return self }
        let back = backdrop.srgbComponents(for: appearance)
        let mix = { (fore: Double, rear: Double) in fore * front.alpha + rear * (1 - front.alpha) }
        return NSColor(
            srgbRed: mix(front.red, back.red),
            green: mix(front.green, back.green),
            blue: mix(front.blue, back.blue),
            alpha: 1
        )
    }

    /// `fraction` of the way from this colour toward `other`, resolved for
    /// `appearance` — in sRGB, which is where §2's 12–18 % was eyeballed.
    ///
    /// **Alpha-correct, and it has to be.** A straight per-channel mix is only
    /// right when the receiver is opaque. Luna blends a *translucent* fill too
    /// — §2's URL pill is `Surface.chromeFill` over glass — and there "18 % of
    /// the way toward the tint" has to mean 18 % of what lands on screen,
    /// whatever the glass happens to be showing. Compositing both the old and
    /// the wanted result over an unknown backdrop and solving for the single
    /// layer that replaces them gives
    ///
    ///     alpha' = a + f·(1 − a)
    ///     colour' = (f·other + (1 − f)·a·self) / alpha'
    ///
    /// in which the backdrop cancels out entirely. At `a = 1` it reduces to
    /// the plain mix this used to be, so every opaque caller is unchanged.
    func blended(toward other: NSColor, fraction: Double, in appearance: NSAppearance) -> NSColor {
        let from = srgbComponents(for: appearance)
        let to = other.srgbComponents(for: appearance)
        // A translucent target contributes proportionally less; a page's
        // `theme-color` is opaque, but nothing guarantees the next caller's is.
        let amount = fraction * to.alpha
        let alpha = from.alpha + amount * (1 - from.alpha)
        guard alpha > 0 else { return self }
        let mix = { (lhs: Double, rhs: Double) in
            (amount * rhs + (1 - amount) * from.alpha * lhs) / alpha
        }
        return NSColor(
            srgbRed: mix(from.red, to.red),
            green: mix(from.green, to.green),
            blue: mix(from.blue, to.blue),
            alpha: alpha
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
    func alpha(contrast: Bool, dark isDark: Bool) -> Double {
        switch (isDark, contrast) {
        case (true, true): contrastDark
        case (true, false): dark
        case (false, true): contrastLight
        case (false, false): light
        }
    }

    /// That variant as ink — black on light, white on dark.
    func color(contrast: Bool, dark isDark: Bool) -> NSColor {
        NSColor(white: isDark ? 1 : 0, alpha: alpha(contrast: contrast, dark: isDark))
    }
}

/// Translucent ink — black on light, white on dark. Translucent rather than a
/// fixed grey so the token keeps its ratio on whichever surface it lands on.
///
/// The Increase Contrast branch is taken *here*, not inside the provider,
/// because the provider cannot see the setting (`Tokens.swift`'s header). The
/// two variants get different colour names because an `NSColor` name is its
/// identity.
func inkColor(_ name: String, _ alphas: InkAlphas) -> NSColor {
    let contrast = Tokens.A11y.increaseContrast
    let pair = alphas.inForce
    return NSColor(name: NSColor.Name(contrast ? name + ".contrast" : name)) { appearance in
        let isDark = appearance.isDark
        return NSColor(white: isDark ? 1 : 0, alpha: isDark ? pair.dark : pair.light)
    }
}

/// A translucent *plane* tint — the mirror of `inkColor`: **white on light,
/// black on dark**.
///
/// `inkColor` exists to put marks on a surface, so it flips to white in dark
/// mode to stay legible. A tint that thickens a surface has to go the other
/// way: over a dark desktop the chrome reads as deeper, over a light one as
/// milkier. Using ink here would brighten the sidebar in dark mode, which is
/// the opposite of "less transparent".
func surfaceTintColor(_ name: String, _ alphas: InkAlphas) -> NSColor {
    let contrast = Tokens.A11y.increaseContrast
    let pair = alphas.inForce
    return NSColor(name: NSColor.Name(contrast ? name + ".contrast" : name)) { appearance in
        let isDark = appearance.isDark
        return NSColor(white: isDark ? 0 : 1, alpha: isDark ? pair.dark : pair.light)
    }
}

/// A drop shadow's colour: **black in both themes**, with a per-theme alpha.
///
/// Not `inkColor`, which flips to white on dark — a white shadow is a glow, and
/// §5 asks for weight, not for the popover to light up.
func shadowInkColor(_ name: String, _ alphas: InkAlphas) -> NSColor {
    let contrast = Tokens.A11y.increaseContrast
    let pair = alphas.inForce
    return NSColor(name: NSColor.Name(contrast ? name + ".contrast" : name)) { appearance in
        NSColor(white: 0, alpha: appearance.isDark ? pair.dark : pair.light)
    }
}

// MARK: - Page-derived wash (§2)

extension Tokens {

    /// The §2 URL-pill wash: blends a page's `themeColor` into a chrome fill,
    /// backing the fraction off until `text` still clears §21.4's 4.5:1, and
    /// dropping the wash entirely rather than shipping unreadable chrome.
    ///
    /// This is the blend *helper* only. Deciding when to apply it, animating it
    /// over `Motion.themeWash`, and skipping it under Reduce Transparency
    /// (§2) are the consuming view's job.
    ///
    /// Hand it `Surface.chromeFill` as the fill and the result stays
    /// translucent, so the pill keeps its glass; hand it an opaque plane and
    /// you get an opaque fill, exactly as before.
    ///
    /// - Parameters:
    ///   - tint: the page colour, already bridged from `RGBA`.
    ///   - fill: the un-washed pill fill.
    ///   - fraction: §2's upper bound, 12–18 %. Stepped down in 2 % increments.
    ///   - text: the colour that must stay readable on the result.
    ///   - backdrop: the plane the washed fill will be seen against. Only
    ///     consulted when `fill` is translucent — a §21.4 ratio has to be
    ///     measured against what the eye receives, and a translucent wash on
    ///     its own is not that. Defaults to `Surface.raised`, which is what
    ///     `.control` glass falls back to under Reduce Transparency and
    ///     therefore the system's own stand-in for "behind the pill".
    /// - Returns: a dynamic colour that re-clamps per appearance. Equal to
    ///   `fill` wherever even 12 % fails.
    static func wash(
        _ tint: NSColor,
        over fill: NSColor,
        upTo fraction: Double = 0.18,
        keeping text: NSColor,
        against backdrop: NSColor = Tokens.Surface.raised
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            var amount = fraction
            while amount >= 0.12 {
                let candidate = fill.blended(toward: tint, fraction: amount, in: appearance)
                let seen = candidate.flattened(over: backdrop, in: appearance)
                if text.contrastRatio(over: seen, in: appearance) >= 4.5 {
                    return candidate
                }
                amount -= 0.02
            }
            return fill
        }
    }
}
