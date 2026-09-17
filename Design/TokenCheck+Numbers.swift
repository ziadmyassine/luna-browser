//
//  TokenCheck+Numbers.swift
//  Luna
//
//  The half of `TokenCheck` that checks numbers rather than colours: §1/§3's
//  metrics and §6's motion budget. Split off for `TokenCheck.swift`'s length
//  limit, and it compiles and runs under exactly the same conditions — see
//  that file's header for both ways to run it.
//
//  Same rule as the colour half: **re-derive, do not restate.** §3.4's row
//  insets are checked by rebuilding the geometry the reference measures, not
//  by comparing against the numbers `Metrics.swift` already holds.
//

#if DEBUG || TOKENCHECK_MAIN

import AppKit

extension TokenCheck {

    // MARK: - Numbers

    static func checkMetrics() -> [String] {
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
            ("topBarHeight", Tokens.Metric.topBarHeight), ("hairline", Tokens.Metric.hairline),
            ("rowGap", Tokens.Metric.rowGap), ("rowFaviconInset", Tokens.Metric.rowFaviconInset),
            ("rowTitleInset", Tokens.Metric.rowTitleInset), ("pillTextInset", Tokens.Metric.pillTextInset),
            ("pillGlyphInset", Tokens.Metric.pillGlyphInset), ("glyphSize", Tokens.Metric.glyphSize),
            ("chromeGap", Tokens.Metric.chromeGap), ("chromeGapWide", Tokens.Metric.chromeGapWide),
            ("controlRowGap", Tokens.Metric.controlRowGap), ("capsuleHeight", Tokens.Metric.capsuleHeight),
            ("downloadsPopoverTail", Tokens.Metric.downloadsPopoverTail),
            ("reloadBlurRadius", Tokens.Metric.reloadBlurRadius), ("reloadProgressLine", Tokens.Metric.reloadProgressLine)
        ]
        failures += scalars.filter { $0.1 <= 0 }.map { "Metric.\($0.0) is not positive" }
        return failures + checkRowInsets()
    }

    /// §3.4's row geometry, re-derived rather than trusted.
    ///
    /// The insets are the one place M1 overrode the spec from the reference
    /// (§3.4 says 12 / 40 pt, `inspiration/main-tab-bar-and-ui.png` measures
    /// ~15 / ~41), so what is checked is the *rule* the reference follows —
    /// the favicon centred in the row's leading `rowHeight` zone — and that it
    /// still lands on the measured numbers.
    private static func checkRowInsets() -> [String] {
        var failures: [String] = []
        let metric = Tokens.Metric.self
        let leading = metric.rowFaviconInset - metric.rowInset
        let trailing = metric.rowHeight - metric.rowFaviconInset - metric.faviconSize
        if abs(leading - trailing) > 0.01 {
            failures.append(String(
                format: "Metric.rowFaviconInset leaves %.1f before the favicon and %.1f after — §3.4 centres it in the leading zone",
                leading, trailing
            ))
        }
        if abs(metric.rowFaviconInset - 15) > 0.5 || abs(metric.rowTitleInset - 41) > 0.5 {
            failures.append(String(
                format: "row insets are %.1f / %.1f — the reference measures ~15 / ~41",
                metric.rowFaviconInset, metric.rowTitleInset
            ))
        }
        if metric.rowTitleInset <= metric.rowFaviconInset + metric.faviconSize {
            failures.append("Metric.rowTitleInset overlaps the favicon")
        }
        if metric.rowGap >= metric.rowHeight {
            failures.append("Metric.rowGap eats the whole row")
        }
        // §4's measured finding: the action capsule is taller than the pill it
        // sits beside. Equal heights mean someone "tidied" one into the other.
        if metric.capsuleHeight <= metric.urlPill.height {
            failures.append("Metric.capsuleHeight is not above urlPill.height — §4's capsule measures taller")
        }
        if metric.downloadsPopoverTail > metric.downloadsPopover.height / 2 {
            failures.append("Metric.downloadsPopoverTail is longer than half the popover — the tail would swallow the body")
        }
        return failures
    }

    /// §6: nothing over 0.35 s except the two entries tied to real work.
    static func checkMotion() -> [String] {
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
        // The two entries §6 exempts: one tied to real work (§5.1), one a
        // repeating indicator whose duration is a rate rather than a delay
        // (§3.4's shimmer). Neither belongs in `timed` above.
        failures += exemption("downloadsParticleSweep", Tokens.Motion.downloadsParticleSweep, 0.40)
        failures += exemption("rowShimmer", Tokens.Motion.rowShimmer, 1.10)
        if timed.contains(where: { $0.0 == "rowShimmer" }) {
            failures.append("Motion.rowShimmer is in the budget list — it loops, so 0.35 s would make it a strobe")
        }
        return failures
    }

    /// One §6 budget exemption, checked **by value** so the exemption cannot be
    /// used to smuggle an arbitrary duration past the 0.35 s cap. Neither of
    /// the two is a spring: a spring settles, and one of these is tied to real
    /// work (§5.1) while the other repeats forever (§3.4's shimmer).
    private static func exemption(_ name: String, _ spec: MotionSpec, _ expected: TimeInterval) -> [String] {
        var failures: [String] = []
        if abs(spec.duration - expected) > 0.001 {
            failures.append(String(format: "Motion.%@ is %.2f s — its §6 exemption is for %.2f s", name, spec.duration, expected))
        }
        if spec.isSpring {
            failures.append("Motion.\(name) is a spring — a spring settles, and neither exemption is allowed to")
        }
        return failures
    }
}

#endif
