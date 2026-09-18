//
//  TokenCheck+Effects.swift
//  Luna
//
//  The three token groups that are neither a plane nor a piece of text: §2's
//  page-derived wash, §5's panel shadow and §7's reload bloom. Split off for
//  `TokenCheck.swift`'s length limit; it runs in the same pass, under the same
//  conditions, and that file's header covers both ways to run it.
//
//  What they have in common is that none of them can be checked by contrast
//  alone. A wash has to stay translucent *and* readable, a shadow has to stay
//  black and grow in the dark, and a bloom has to stay identical in both
//  themes — each is a claim `Tokens.swift` makes in prose, re-derived here.
//

#if DEBUG || TOKENCHECK_MAIN

import AppKit

// MARK: - Effects

extension TokenCheck {

    /// §2: the page-derived wash may never push pill text under 4.5:1. Tested
    /// with the worst tints a site can hand us — a white and a black
    /// `theme-color`, plus a saturated one — over both an opaque fill and the
    /// translucent `chromeFill` the pill actually uses.
    ///
    /// `secondary` is in the `keeping:` list to exercise the clamp itself, not
    /// because the pill draws with it: at 18 % over `chromeFill` in dark mode
    /// secondary measures 3.34:1, so this row can only pass if `wash` really
    /// does step down and, failing that, hand back the un-washed fill. With
    /// `primary` alone the loop never fires and the clamp goes untested.
    static func checkWash() -> [String] {
        var failures: [String] = []
        let tints: [(String, NSColor)] = [("white", .white), ("black", .black), ("yellow", .systemYellow), ("blue", .systemBlue)]
        let fills: [(String, NSColor)] = [("raised", Tokens.Surface.raised), ("chromeFill", Tokens.Surface.chromeFill)]
        let keeping: [(String, NSColor)] = [("primary", Tokens.Text.primary), ("secondary", Tokens.Text.secondary)]
        for (name, appearance) in appearances {
            for (tint, color) in tints {
                for (fill, plane) in fills {
                    for (text, ink) in keeping {
                        let washed = Tokens.wash(color, over: plane, keeping: ink)
                        let seen = washed.flattened(over: Tokens.Surface.raised, in: appearance)
                        let ratio = ink.contrastRatio(over: seen, in: appearance)
                        if ratio < textFloor {
                            failures.append(String(
                                format: "wash(%@) over %@ keeping %@ in %@ leaves text at %.2f:1 — §2 says drop it instead",
                                tint, fill, text, name, ratio
                            ))
                        }
                        // §2: the pill is the one page-tinted surface *and* it
                        // is glass. Washing a translucent fill has to leave it
                        // translucent, or the pill goes back to being a plate.
                        let alpha = washed.srgbComponents(for: appearance).alpha
                        if fill == "chromeFill" && alpha >= 1 {
                            failures.append("wash(\(tint)) over chromeFill in \(name) came back opaque — the pill would stop being glass")
                        }
                    }
                }
            }
        }
        return failures
    }

    /// §7's bloom. It is the one colour group with **no** theme or contrast
    /// variant — emitted light over page content, not chrome — so what is
    /// checked is that it stays that way, plus the band order §7 got wrong
    /// once already.
    static func checkBloom() -> [String] {
        var failures: [String] = []
        guard let light = appearances.first?.1, let dark = appearances.last?.1 else { return failures }
        var previousAlpha = 0.0
        for (band, color) in bloom {
            let inLight = color.srgbComponents(for: light)
            let inDark = color.srgbComponents(for: dark)
            if inLight.red != inDark.red || inLight.green != inDark.green
                || inLight.blue != inDark.blue || inLight.alpha != inDark.alpha {
                failures.append("Bloom.\(band) differs between themes — the arc is emitted light, not chrome")
            }
            if !(0...1).contains(inLight.alpha) || inLight.alpha >= 1 {
                failures.append(String(
                    format: "Bloom.%@ is %.2f alpha — a bloom adds light, it does not cover the page", band, inLight.alpha
                ))
            }
            // Every band is a pale tint of white; a saturated value pasted in
            // here would read as a coloured wipe rather than a bloom.
            if inLight.relativeLuminance < 0.45 {
                failures.append(String(format: "Bloom.%@ has luminance %.2f — too dark to read as bloom", band, inLight.relativeLuminance))
            }
            if inLight.alpha < previousAlpha {
                failures.append("Bloom.\(band) is weaker than the band inside it — §7 runs core → amber → mint → lavender")
            }
            previousAlpha = inLight.alpha
        }
        return failures
    }

    /// §5's panel shadow, which exists because `NSGlassEffectView` has no
    /// heavier style to ask for (`Glass.swift`).
    static func checkShadow() -> [String] {
        var failures: [String] = []
        let shadow = Tokens.Shadow.popover
        if shadow.radius <= 0 { failures.append("Shadow.popover has no radius — the popover would have no weight at all") }
        if shadow.offset.height > 0 { failures.append("Shadow.popover falls upward — CALayer is not flipped") }
        var alphas: [String: Double] = [:]
        for (name, appearance) in appearances {
            let value = shadow.color.srgbComponents(for: appearance)
            alphas[name] = value.alpha
            if value.red + value.green + value.blue > 0 {
                failures.append("Shadow.popover is not black in \(name) — a light shadow is a glow")
            }
            if !(0...1).contains(value.alpha) || value.alpha <= 0 {
                failures.append(String(format: "Shadow.popover is %.2f alpha in %@ — invisible", value.alpha, name))
            }
        }
        if let light = alphas["light"], let dark = alphas["dark"], dark < light {
            failures.append("Shadow.popover is weaker in dark mode, where a soft edge needs more, not less")
        }
        return failures
    }

    /// §7's 1× pair, **re-derived rather than restated**. Both are functions of
    /// `Ink.glassTint`, so nudging that one alpha has to move both or the
    /// adaptation silently stops being the thing the comments describe:
    ///
    ///   · `glassTintControl` is half of `glassTint`, exactly.
    ///   · `glassTintDense` is `glassTint` + 0.16 — the measured step, see
    ///     `DisplayScale.swift` for the sweep it comes from.
    ///
    /// Plus the two invariants that make §7 honest at all: the order is
    /// control < plain < dense in every variant, and none of the three may
    /// reach opacity, because a chrome tint that hides the desktop is not
    /// glass being optimised, it is glass being replaced.
    static func checkGlassOptimisation() -> [String] {
        var failures: [String] = []
        let tolerance = 0.006
        /// Past this the chrome transmits less than a third of the desktop.
        let ceiling = 0.70
        /// The measured step: ≈ +4 luminance units on `.regular` glass.
        let denseStep = 0.16
        for contrast in [false, true] {
            for isDark in [false, true] {
                let variant = "\(isDark ? "dark" : "light")\(contrast ? "+contrast" : "")"
                let plain = Tokens.Ink.glassTint.alpha(contrast: contrast, dark: isDark)
                let dense = Tokens.Ink.glassTintDense.alpha(contrast: contrast, dark: isDark)
                let control = Tokens.Ink.glassTintControl.alpha(contrast: contrast, dark: isDark)
                failures += glassTintOrder(plain: plain, dense: dense, control: control, variant: variant)
                if abs(control - plain / 2) > tolerance {
                    failures.append(String(
                        format: "Ink.glassTintControl is %.3f in %@ — §7 derives it as half of glassTint (%.3f)",
                        control, variant, plain / 2
                    ))
                }
                if abs(dense - (plain + denseStep)) > tolerance {
                    failures.append(String(
                        format: "Ink.glassTintDense is %.3f in %@ — the measured step puts it at %.3f",
                        dense, variant, plain + denseStep
                    ))
                }
                if dense > ceiling {
                    failures.append(String(
                        format: "Ink.glassTintDense is %.3f in %@ — past %.2f the chrome stops sampling the desktop (§2)",
                        dense, variant, ceiling
                    ))
                }
            }
        }
        return failures
    }

    /// §2a's pair, and the two things that make the setting mean anything.
    ///
    ///   · **Opaque is denser than clear**, in every variant. It is the whole
    ///     name of the thing, and the two alphas are hand-set from separate
    ///     measurements rather than derived from each other, so nothing but
    ///     this stops one drifting past the other.
    ///   · **Neither reaches 1.0.** At full strength the frost *is*
    ///     `Surface.glassFallback`, the Reduce Transparency plane — there is no
    ///     glass left above it, and "more opaque" would have quietly become
    ///     "off". `checkResolution` asserts the same rule from the colour side;
    ///     this one catches it in the alpha table, where it is set.
    ///
    /// The ceiling is higher than §7's 0.70 on purpose: that one protects §2's
    /// "the chrome samples the desktop", which is exactly the claim this setting
    /// exists to let the user give up.
    static func checkGlassDensity() -> [String] {
        var failures: [String] = []
        /// Short of the plane by a visible margin, not by a rounding error.
        let ceiling = 0.95
        for contrast in [false, true] {
            for isDark in [false, true] {
                let variant = "\(isDark ? "dark" : "light")\(contrast ? "+contrast" : "")"
                let clear = Tokens.Ink.frost.alpha(contrast: contrast, dark: isDark)
                let opaque = Tokens.Ink.frostOpaque.alpha(contrast: contrast, dark: isDark)
                if opaque <= clear {
                    failures.append(String(
                        format: "Ink.frostOpaque (%.3f) is not above frost (%.3f) in %@ — §2a's two densities are one",
                        opaque, clear, variant
                    ))
                }
                if opaque > ceiling {
                    failures.append(String(
                        format: "Ink.frostOpaque is %.3f in %@ — past %.2f there is no glass left above the plane",
                        opaque, variant, ceiling
                    ))
                }
            }
        }
        return failures
    }

    /// §7's ordering, split out of `checkGlassOptimisation` for the complexity
    /// limit. The control must stay lighter than the bar it sits on, and the
    /// optimised bar must actually be denser than the plain one — "increased
    /// alpha" is the claim §7 makes and this is where it stops being prose.
    private static func glassTintOrder(plain: Double, dense: Double, control: Double, variant: String) -> [String] {
        var failures: [String] = []
        if dense <= plain {
            failures.append(String(
                format: "Ink.glassTintDense (%.3f) is not above glassTint (%.3f) in %@ — §7 says the 1× bar thickens",
                dense, plain, variant
            ))
        }
        if control >= plain {
            failures.append(String(
                format: "Ink.glassTintControl (%.3f) is not below glassTint (%.3f) in %@ — the control would read as a slab",
                control, plain, variant
            ))
        }
        for (token, alpha) in [("glassTintDense", dense), ("glassTintControl", control)] where !(0...1).contains(alpha) || alpha >= 1 {
            failures.append(String(format: "Ink.%@ is %.3f in %@ — a tint is not a plane", token, alpha, variant))
        }
        return failures
    }
}

#endif
