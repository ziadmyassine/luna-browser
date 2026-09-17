//
//  TokenCheck.swift
//  Luna
//
//  The design system's regression net. It resolves every colour token in both
//  themes and both contrast modes, and re-derives the contrast ratios quoted in
//  `Tokens.swift` instead of trusting them. If someone nudges an alpha and
//  drops a text token under §21.4's 4.5:1, this fails.
//
//  The Increase Contrast half is checked through `Tokens.Ink` rather than an
//  appearance, because macOS 26 has no high-contrast `NSAppearance` to resolve
//  against — `NSAppearance(named: .accessibilityHighContrastAqua)` hands back
//  the identical object as `.aqua`. See the `Tokens.swift` header.
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
//                 Design/Tokens.swift Design/Metrics.swift \
//                 Design/Motion.swift Design/TokenCheck.swift -o /tmp/tokencheck
//          /tmp/tokencheck
//      (`Glass.swift` and `GradientBridge.swift` are excluded: one needs a
//      window server to show anything, the other needs BrowserKit.)
//

#if DEBUG || TOKENCHECK_MAIN

import AppKit

enum TokenCheck {

    /// §21.4's floor for text.
    private static let textFloor = 4.5
    /// WCAG 1.4.11's floor for a UI component boundary.
    private static let borderFloor = 3.0
    /// §6's budget. The two entries tied to real work are exempt by name.
    private static let motionBudget: TimeInterval = 0.35

    /// Computed, not stored: `NSAppearance` is not `Sendable`, so a `static let`
    /// of them is a Swift 6 error. Same reason `TypeScale` uses computed fonts.
    private static var appearances: [(String, NSAppearance)] {
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

    /// Empty means the design system still holds.
    static func failures() -> [String] {
        guard appearances.count == 2 else {
            return ["only \(appearances.count)/2 appearances resolved — the SDK renamed one"]
        }
        return checkResolution() + checkTextContrast() + checkSurfaceSeparation()
            + checkLines() + checkIncreaseContrast() + checkWash() + checkMetrics() + checkMotion()
    }

    /// Trips a debug assertion listing every failure.
    static func run() {
        let failures = failures()
        assert(failures.isEmpty, "Design tokens regressed:\n  " + failures.joined(separator: "\n  "))
    }

    // MARK: Colours

    /// Every token must actually produce a colour in every appearance. A
    /// dynamic colour whose provider returns something unconvertible resolves
    /// to nothing and paints invisibly — silently, which is the bad part.
    private static func checkResolution() -> [String] {
        var failures: [String] = []
        let all = surfaces + texts
            + [("hairline", Tokens.Line.hairline), ("border", Tokens.Line.border)]
            + [("tint", Tokens.Accent.tint), ("danger", Tokens.Accent.danger)]
        for (name, appearance) in appearances {
            for (token, color) in all where color.srgbComponents(for: appearance).alpha <= 0 {
                failures.append("\(token) resolves to nothing in \(name)")
            }
            for (token, color) in surfaces where color.srgbComponents(for: appearance).alpha < 1 {
                failures.append("Surface.\(token) is translucent in \(name) — surfaces must be opaque")
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
    /// *exactly* `windowBackgroundColor`, so a surface that looks distinct in
    /// the source can be invisible on screen.
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
            ("secondary", Tokens.Ink.secondary), ("tertiary", Tokens.Ink.tertiary), ("border", Tokens.Ink.border)
        ]
        for (token, alphas) in inks {
            if alphas.contrastLight < alphas.light || alphas.contrastDark < alphas.dark {
                failures.append("Ink.\(token) gets *weaker* under Increase Contrast")
            }
        }
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

    /// §2: the page-derived wash may never push pill text under 4.5:1. Tested
    /// with the worst tints a site can hand us — a white and a black
    /// `theme-color`, plus a saturated one.
    private static func checkWash() -> [String] {
        var failures: [String] = []
        let tints: [(String, NSColor)] = [("white", .white), ("black", .black), ("yellow", .systemYellow), ("blue", .systemBlue)]
        for (name, appearance) in appearances {
            for (tint, color) in tints {
                let washed = Tokens.wash(color, over: Tokens.Surface.raised, keeping: Tokens.Text.primary)
                let ratio = Tokens.Text.primary.contrastRatio(over: washed, in: appearance)
                if ratio < textFloor {
                    failures.append(String(format: "wash(%@) in %@ leaves text at %.2f:1 — §2 says drop it instead", tint, name, ratio))
                }
            }
        }
        return failures
    }

    // MARK: Numbers

    private static func checkMetrics() -> [String] {
        var failures: [String] = []
        let width = Tokens.Metric.sidebarWidth
        if !(width.min < width.default && width.default < width.max) {
            failures.append("Metric.sidebarWidth is not min < default < max")
        }
        if width.clamp(width.min - 100) != width.min || width.clamp(width.max + 100) != width.max {
            failures.append("SpanMetric.clamp does not clamp")
        }
        let rounded: [(String, RoundedMetric)] = [
            ("urlPill", Tokens.Metric.urlPill), ("essentialsTile", Tokens.Metric.essentialsTile),
            ("controlCircle", Tokens.Metric.controlCircle), ("controlSquircle", Tokens.Metric.controlSquircle),
            ("bottomCircle", Tokens.Metric.bottomCircle), ("spaceDotsPill", Tokens.Metric.spaceDotsPill),
            ("downloadsPopover", Tokens.Metric.downloadsPopover), ("resizeHandle", Tokens.Metric.resizeHandle)
        ]
        for (name, metric) in rounded {
            if metric.width <= 0 || metric.height <= 0 {
                failures.append("Metric.\(name) has a non-positive dimension")
            }
            if metric.cornerRadius * 2 > Swift.min(metric.width, metric.height) {
                failures.append("Metric.\(name) radius exceeds half its shorter side")
            }
        }
        let scalars: [(String, CGFloat)] = [
            ("rowHeight", Tokens.Metric.rowHeight), ("rowInset", Tokens.Metric.rowInset),
            ("faviconSize", Tokens.Metric.faviconSize), ("rowCornerRadius", Tokens.Metric.rowCornerRadius),
            ("essentialsTileGap", Tokens.Metric.essentialsTileGap), ("essentialsIcon", Tokens.Metric.essentialsIcon),
            ("spaceDot", Tokens.Metric.spaceDot), ("windowCornerRadius", Tokens.Metric.windowCornerRadius),
            ("contentCardRadius", Tokens.Metric.contentCardRadius), ("contentCardGap", Tokens.Metric.contentCardGap),
            ("topBarHeight", Tokens.Metric.topBarHeight), ("hairline", Tokens.Metric.hairline)
        ]
        failures += scalars.filter { $0.1 <= 0 }.map { "Metric.\($0.0) is not positive" }
        return failures
    }

    /// §6: nothing over 0.35 s except the two entries tied to real work.
    private static func checkMotion() -> [String] {
        let timed: [(String, MotionSpec)] = [
            ("rowHover", Tokens.Motion.rowHover), ("controlHover", Tokens.Motion.controlHover),
            ("selectedRowMove", Tokens.Motion.selectedRowMove), ("tabInsert", Tokens.Motion.tabInsert),
            ("spaceSwitch", Tokens.Motion.spaceSwitch), ("spaceSwitchCrossfade", Tokens.Motion.spaceSwitchCrossfade),
            ("sidebarCollapse", Tokens.Motion.sidebarCollapse), ("sidebarCollapseOpacity", Tokens.Motion.sidebarCollapseOpacity),
            ("layoutSwitch", Tokens.Motion.layoutSwitch), ("splitDividerSnap", Tokens.Motion.splitDividerSnap),
            ("cardFullscreen", Tokens.Motion.cardFullscreen), ("commandBarIn", Tokens.Motion.commandBarIn),
            ("popoverIn", Tokens.Motion.popoverIn), ("hoverPeek", Tokens.Motion.hoverPeek),
            ("themeWash", Tokens.Motion.themeWash), ("reloadArcIn", Tokens.Motion.reloadArcIn),
            ("reloadArcOut", Tokens.Motion.reloadArcOut), ("particleDissolve", Tokens.Motion.particleDissolve),
            ("particleSettle", Tokens.Motion.particleSettle)
        ]
        var failures = timed.filter { $0.1.duration > motionBudget }
            .map { String(format: "Motion.%@ is %.2f s — §6 caps at 0.35 s", $0.0, $0.1.duration) }
        failures += timed.filter { $0.1.duration <= 0 }.map { "Motion.\($0.0) has no duration" }

        // A spring must produce a usable animation, or a view falls back to an
        // instant change and the spec is a lie.
        for (name, spec) in timed where spec.isSpring {
            if !Tokens.Motion.reduceMotion && spec.springAnimation(keyPath: "position") == nil {
                failures.append("Motion.\(name) claims to be a spring but builds no animation")
            }
        }
        if Tokens.Motion.downloadsParticleSweep.duration != 0.40 {
            failures.append("Motion.downloadsParticleSweep must stay at §5.1's 0.40 s")
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
