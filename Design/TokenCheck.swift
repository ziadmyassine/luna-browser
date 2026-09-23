//
//  TokenCheck.swift
//  Luna
//
//  The design system's regression net. It resolves every colour token in both
//  themes and both contrast modes and re-derives the ratios Tokens.swift quotes
//  instead of trusting them, so nudging an alpha under §21.4's 4.5:1 fails here.
//
//  The Increase Contrast half goes through `Tokens.Ink` rather than an
//  appearance: macOS 26 has no high-contrast `NSAppearance` to resolve against
//  (Tokens.swift's header).
//
//  Two ways to run it:
//
//    · In the app, Debug only. One line in `applicationDidFinishLaunching`:
//          TokenCheck.run()
//
//    · Standalone, no app target and no test host — which is how it was run
//      while these values were chosen:
//          swiftc -swift-version 6 -strict-concurrency=complete \
//                 -target arm64-apple-macos26.0 -DTOKENCHECK_MAIN \
//                 -enable-upcoming-feature ExistentialAny \
//                 Design/Tokens.swift Design/ColourMath.swift \
//                 Design/Accessibility.swift Design/Metrics.swift \
//                 Design/Motion.swift Design/Glass.swift \
//                 Design/DisplayScale.swift Design/TokenCheck*.swift \
//                 -o /tmp/tokencheck
//          /tmp/tokencheck
//      (`GradientBridge.swift` is excluded: it needs BrowserKit. `Glass.swift`
//      is included because `DisplayScale.swift` needs it to compile; nothing
//      below builds a glass view, so the binary still runs headless.)
//
//  Two companion files run in the same pass: `+Numbers` holds §1/§3's metrics
//  and §6's budget, `+Effects` holds §2's wash, §5's shadow and §7's bloom.
//

#if DEBUG || TOKENCHECK_MAIN

import AppKit

enum TokenCheck {

    /// §21.4's floor for text.
    static let textFloor = 4.5
    /// WCAG 1.4.11's floor for a UI component boundary.
    private static let borderFloor = 3.0
    /// §6's budget. The two exempt entries are checked by value instead — see
    /// `TokenCheck+Numbers.swift`.
    static let motionBudget: TimeInterval = 0.35

    /// Computed, not stored: `NSAppearance` is not `Sendable`, so a `static let`
    /// of them is a Swift 6 error. Same reason `TypeScale` uses computed fonts.
    static var appearances: [(String, NSAppearance)] {
        [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
            .compactMap { name, id in NSAppearance(named: id).map { (name, $0) } }
    }

    private static var surfaces: [(String, NSColor)] {
        [("base", Tokens.Surface.base),
         ("raised", Tokens.Surface.raised),
         ("glassFallback", Tokens.Surface.glassFallback)]
    }

    private static var texts: [(String, NSColor)] {
        [("primary", Tokens.Text.primary),
         ("secondary", Tokens.Text.secondary),
         ("tertiary", Tokens.Text.tertiary)]
    }

    /// The translucent fills (§3.1/§3.4 hover, §3.4 selection, §2's pill).
    /// Apart from `surfaces` because they wash over glass rather than replace
    /// it: the opacity rule below runs the other way for these.
    private static var washes: [(String, NSColor)] {
        [("hover", Tokens.Surface.hover),
         ("selected", Tokens.Surface.selected),
         ("readBand", Tokens.Surface.readBand),
         ("chromeFill", Tokens.Surface.chromeFill)]
    }

    /// The same three by alpha, which is the only way to reach their Increase
    /// Contrast variants (there is no appearance to resolve them against).
    private static var washInks: [(String, InkAlphas)] {
        [("hover", Tokens.Ink.hover),
         ("selected", Tokens.Ink.selected),
         ("chromeFill", Tokens.Ink.chromeFill)]
    }

    /// §2's chrome tint and §7's two 1× replacements for it. Plane tints, not
    /// ink, so they are checked apart from `washes`.
    static var glassTints: [(String, NSColor)] {
        [("glassTint", Tokens.Surface.glassTint),
         ("glassTintDense", Tokens.Surface.glassTintDense),
         ("glassTintControl", Tokens.Surface.glassTintControl)]
    }

    /// §2's frost and §2a's two opaque planes — every plane painted behind
    /// glass rather than instead of it. None of them may be opaque.
    static var frosts: [(String, NSColor)] {
        [("frost", Tokens.Surface.frost),
         ("frostOpaque", Tokens.Surface.frostOpaque),
         ("popoverFrostOpaque", Tokens.Surface.popoverFrostOpaque)]
    }

    /// §7's bloom bands, inner edge to outer.
    static var bloom: [(String, NSColor)] {
        [("core", Tokens.Bloom.core), ("amber", Tokens.Bloom.amber),
         ("mint", Tokens.Bloom.mint), ("lavender", Tokens.Bloom.lavender)]
    }

    /// Empty means the design system still holds.
    static func failures() -> [String] {
        guard appearances.count == 2 else {
            return ["only \(appearances.count)/2 appearances resolved — the SDK renamed one"]
        }
        let colours = checkResolution() + checkTextContrast() + checkSurfaceSeparation()
            + checkLines() + checkIncreaseContrast() + checkFills()
        let effects = checkWash() + checkBloom() + checkShadow() + checkGlassOptimisation()
            + checkGlassDensity()
        return colours + effects + checkMetrics() + checkMotion()
    }

    /// Trips a debug assertion listing every failure.
    static func run() {
        let failures = failures()
        assert(failures.isEmpty, "Design tokens regressed:\n  " + failures.joined(separator: "\n  "))
    }
}

// MARK: - Colours

/// An extension rather than more of the enum above so the checks can keep
/// growing: a type body has a length limit, the roster of tokens does not.
extension TokenCheck {

    /// Every token must produce a colour in every appearance. A dynamic colour
    /// whose provider returns something unconvertible resolves to nothing and
    /// paints invisibly, without complaining.
    private static func checkResolution() -> [String] {
        var failures: [String] = []
        let all = surfaces + texts + bloom + washes
            + glassTints + frosts
            + [("disabled", Tokens.Text.disabled)]
            + [("hairline", Tokens.Line.hairline), ("border", Tokens.Line.border)]
            + [("tint", Tokens.Accent.tint), ("danger", Tokens.Accent.danger)]
            + [("shadow.popover", Tokens.Shadow.popover.color)]
        for (name, appearance) in appearances {
            for (token, color) in all where color.srgbComponents(for: appearance).alpha <= 0 {
                failures.append("\(token) resolves to nothing in \(name)")
            }
            for (token, color) in surfaces where color.srgbComponents(for: appearance).alpha < 1 {
                failures.append("Surface.\(token) is translucent in \(name) — surfaces must be opaque")
            }
            // The mirror image, and the whole reason these tokens exist: an
            // opaque "wash" over Liquid Glass is a plate, and the surface it
            // covers stops being glass (§2).
            for (token, color) in washes where color.srgbComponents(for: appearance).alpha >= 1 {
                failures.append("Surface.\(token) is opaque in \(name) — it washes over glass, it does not replace it")
            }
            // The glass tints are washes too, but not in `washes`: those are
            // ink (black on light), these are plane tints (white on light), and
            // the contrast matrix below is built for the first kind. The rule
            // they share is the one that matters — an opaque tint stops the
            // chrome sampling the desktop, which is all of §2.
            for (token, colour) in glassTints where colour.srgbComponents(for: appearance).alpha >= 1 {
                failures.append("Surface.\(token) is opaque in \(name) — §2's chrome samples what is behind the window")
            }
            // And the frosts, from the other side: each is a fallback plane
            // held at part strength, and at full strength it is the fallback
            // plane, with no glass left above it.
            for (token, colour) in frosts where colour.srgbComponents(for: appearance).alpha >= 1 {
                failures.append("Surface.\(token) is opaque in \(name) — §2's chrome samples what is behind the window")
            }
        }
        return failures
    }

    /// The washes become surfaces the moment text lands on them, so §21.4
    /// applies to what the eye sees: ink over wash over plane. `Text.tertiary`
    /// is excluded by name — at 4.63:1 worst on the bare planes it has no
    /// headroom left to spend on a fill.
    private static func checkFills() -> [String] {
        var failures: [String] = []
        for (name, appearance) in appearances {
            let isDark = appearance.isDark
            for contrast in [false, true] {
                // `primary` is system-backed and cannot be resolved under
                // Increase Contrast at all; it only gets stronger, so its rest
                // value is the conservative one to test.
                let readable: [(String, NSColor)] = [
                    ("primary", Tokens.Text.primary),
                    ("secondary", Tokens.Ink.secondary.color(contrast: contrast, dark: isDark))
                ]
                for (wash, alphas) in washInks {
                    let fill = alphas.color(contrast: contrast, dark: isDark)
                    for (plane, surface) in surfaces {
                        let seen = fill.flattened(over: surface, in: appearance)
                        for (text, ink) in readable {
                            let ratio = ink.contrastRatio(over: seen, in: appearance)
                            guard ratio < textFloor else { continue }
                            failures.append(String(
                                format: "Text.%@ on Surface.%@ over %@ (%@%@) is %.2f:1 — §21.4 needs 4.5:1",
                                text, wash, plane, name, contrast ? "+contrast" : "", ratio
                            ))
                        }
                    }
                }
                failures += checkReadBand(contrast: contrast, in: (name, appearance))
                // §3.4 needs a selected row to still read as selected under the
                // pointer, so the two washes may never converge.
                let hover = Tokens.Ink.hover.alpha(contrast: contrast, dark: isDark)
                let selected = Tokens.Ink.selected.alpha(contrast: contrast, dark: isDark)
                if selected <= hover {
                    failures.append("Ink.selected (\(selected)) is not above Ink.hover (\(hover)) — hovering a selected row would erase it")
                }
            }
        }
        return failures
    }

    /// The part of a selected row its page has been read through wears
    /// `readBand` on top of `selected`. A selected row draws its title and its
    /// trailing control in `primary`, which needs 4.5:1 there; `secondary` is
    /// only a fallback glyph's tint on that row, so it needs the 3:1 a
    /// non-text mark does.
    private static func checkReadBand(contrast: Bool, in variant: (String, NSAppearance)) -> [String] {
        let (name, appearance) = variant
        let isDark = appearance.isDark
        let band = Tokens.Ink.readBand.color(contrast: contrast, dark: isDark)
        let under = Tokens.Ink.selected.color(contrast: contrast, dark: isDark)
        let marks: [(String, NSColor, Double)] = [
            ("primary", Tokens.Text.primary, textFloor),
            ("secondary", Tokens.Ink.secondary.color(contrast: contrast, dark: isDark), borderFloor)
        ]
        var failures: [String] = []
        for (plane, surface) in surfaces {
            let seen = band.flattened(over: under.flattened(over: surface, in: appearance), in: appearance)
            for (text, ink, floor) in marks where ink.contrastRatio(over: seen, in: appearance) < floor {
                failures.append("Text.\(text) on a selected row's read band over \(plane) (\(name)) is under \(floor):1")
            }
        }
        return failures
    }

    /// §21.4: every text token clears 4.5:1 on every surface, in both themes.
    private static func checkTextContrast() -> [String] {
        var failures: [String] = []
        for (name, appearance) in appearances {
            for (text, ink) in texts {
                for (surface, plane) in surfaces {
                    let ratio = ink.contrastRatio(over: plane, in: appearance)
                    if ratio < textFloor {
                        failures.append(
                            String(format: "Text.%@ on Surface.%@ (%@) is %.2f:1 — §21.4 needs 4.5:1", text, surface, name, ratio)
                        )
                    }
                }
            }
        }
        return failures
    }

    /// The M0 trap: on macOS 26 several system background colours resolve to
    /// exactly `windowBackgroundColor`, so a surface that looks distinct in the
    /// source can be invisible on screen.
    private static func checkSurfaceSeparation() -> [String] {
        var failures: [String] = []
        for (name, appearance) in appearances {
            let base = Tokens.Surface.base
            for (token, plane) in [("raised", Tokens.Surface.raised), ("glassFallback", Tokens.Surface.glassFallback)] {
                let ratio = plane.contrastRatio(over: base, in: appearance)
                if ratio < 1.05 {
                    failures.append(String(format: "Surface.%@ is %.3f:1 from base (%@) — invisible", token, ratio, name))
                }
            }
        }
        return failures
    }

    /// The hairline must stay visible at rest. `.separatorColor` is 9.8 % on
    /// macOS 26.5; if a future SDK drops it to nothing, §1's hairline silently
    /// disappears from every divider in the app.
    private static func checkLines() -> [String] {
        var failures: [String] = []
        for (name, appearance) in appearances {
            let alpha = Tokens.Line.hairline.srgbComponents(for: appearance).alpha
            if !(0.05...0.30).contains(alpha) {
                failures.append(String(format: "Line.hairline is %.3f alpha in %@ — expected ~0.10 at rest", alpha, name))
            }
        }
        return failures
    }

    /// §2's Increase Contrast clauses: hairlines promote to 20 %, and every
    /// control gains a border that is actually visible. Checked through
    /// `Tokens.Ink` — there is no appearance to resolve the branch against.
    private static func checkIncreaseContrast() -> [String] {
        var failures: [String] = []
        if Tokens.Ink.hairlineContrast < 0.20 {
            failures.append("Ink.hairlineContrast is below §2's 0.20")
        }
        let inks: [(String, InkAlphas)] = [
            ("secondary", Tokens.Ink.secondary), ("tertiary", Tokens.Ink.tertiary), ("border", Tokens.Ink.border),
            ("hover", Tokens.Ink.hover), ("selected", Tokens.Ink.selected), ("chromeFill", Tokens.Ink.chromeFill),
            // Including `disabled`: a dimmed control still has to be findable
            // for the users who turn Increase Contrast on, even though §21.4
            // does not apply to its label (`Text.disabled`).
            ("disabled", Tokens.Ink.disabled), ("popoverShadow", Tokens.Ink.popoverShadow),
            // §7's pair: a 1× display is not a reason for Increase Contrast to
            // buy less than it does at 2×.
            ("glassTint", Tokens.Ink.glassTint),
            ("glassTintDense", Tokens.Ink.glassTintDense),
            ("glassTintControl", Tokens.Ink.glassTintControl),
            // §2a's opaque frost: the setting that gives up transparency must
            // not give the users who asked for less of it a thinner surface.
            ("frost", Tokens.Ink.frost),
            ("frostOpaque", Tokens.Ink.frostOpaque)
        ]
        for (token, alphas) in inks {
            if alphas.contrastLight < alphas.light || alphas.contrastDark < alphas.dark {
                failures.append("Ink.\(token) gets *weaker* under Increase Contrast")
            }
        }
        failures += checkDisabledExemption()
        for (name, appearance) in appearances {
            let isDark = appearance.isDark
            for (surface, plane) in surfaces {
                let border = Tokens.Ink.border.color(contrast: true, dark: isDark)
                let ratio = border.contrastRatio(over: plane, in: appearance)
                if ratio < borderFloor {
                    failures.append(
                        String(format: "Line.border on Surface.%@ (%@+contrast) is %.2f:1 — §2 wants it visible", surface, name, ratio)
                    )
                }
                for (token, alphas) in [("secondary", Tokens.Ink.secondary), ("tertiary", Tokens.Ink.tertiary)] {
                    let ink = alphas.color(contrast: true, dark: isDark)
                    let text = ink.contrastRatio(over: plane, in: appearance)
                    if text < textFloor {
                        failures.append(
                            String(format: "Text.%@ on Surface.%@ (%@+contrast) is %.2f:1 — §21.4 needs 4.5:1", token, surface, name, text)
                        )
                    }
                }
            }
        }
        return failures
    }

    /// §3.1's disabled dim is exempt from §21.4 because it is dimmer than the
    /// quietest tier anyone is meant to read. Checked rather than asserted:
    /// past `tertiary` it is unreadable body text with a note attached, and the
    /// exemption stops being honest.
    private static func checkDisabledExemption() -> [String] {
        var failures: [String] = []
        for contrast in [false, true] {
            for isDark in [false, true] {
                let dim = Tokens.Ink.disabled.alpha(contrast: contrast, dark: isDark)
                let quietest = Tokens.Ink.tertiary.alpha(contrast: contrast, dark: isDark)
                if dim >= quietest {
                    failures.append("Ink.disabled (\(dim)) is not dimmer than Ink.tertiary (\(quietest)) — §21.4's exemption assumes it is")
                }
            }
        }
        return failures
    }
}

#endif

#if TOKENCHECK_MAIN

@main
enum TokenCheckMain {
    static func main() {
        let failures = TokenCheck.failures()
        for failure in failures { print("FAIL  \(failure)") }
        print(failures.isEmpty ? "TokenCheck: all tokens pass." : "TokenCheck: \(failures.count) failure(s).")
        exit(failures.isEmpty ? 0 : 1)
    }
}

#endif
