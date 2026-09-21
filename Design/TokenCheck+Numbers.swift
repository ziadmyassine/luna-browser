//
//  TokenCheck+Numbers.swift
//  Luna
//
//  The half of `TokenCheck` that checks numbers rather than colours: §1/§3's
//  metrics and §6's motion budget. Split off for `TokenCheck.swift`'s length
//  limit, and it compiles and runs under exactly the same conditions — see
//  that file's header for both ways to run it.
//
//  Same rule as the colour half: re-derive, do not restate. §3.4's row
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
            ("rowTrailingChip", Tokens.Metric.rowTrailingChip),
            ("resizeHandle", Tokens.Metric.resizeHandle),
            ("glassPreviewTile", Tokens.Metric.glassPreviewTile)
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
            ("contentCardRadius", Tokens.Metric.contentCardRadius), ("panelInset", Tokens.Metric.panelInset),
            ("topBarHeight", Tokens.Metric.topBarHeight), ("hairline", Tokens.Metric.hairline),
            ("rowGap", Tokens.Metric.rowGap), ("rowFaviconInset", Tokens.Metric.rowFaviconInset),
            ("rowTitleInset", Tokens.Metric.rowTitleInset), ("rowIconGap", Tokens.Metric.rowIconGap),
            ("rowTitleGap", Tokens.Metric.rowTitleGap),
            ("rowTitleFade", Tokens.Metric.rowTitleFade), ("separatorRowHeight", Tokens.Metric.separatorRowHeight),
            ("rowTrailingGlyph", Tokens.Metric.rowTrailingGlyph),
            ("essentialsInset", Tokens.Metric.essentialsInset), ("controlPairGap", Tokens.Metric.controlPairGap),
            ("trafficLightInset", Tokens.Metric.trafficLightInset), ("pillTextInset", Tokens.Metric.pillTextInset),
            ("pillGlyphInset", Tokens.Metric.pillGlyphInset), ("glyphSize", Tokens.Metric.glyphSize),
            ("pillGlyphSize", Tokens.Metric.pillGlyphSize),
            ("chromeGap", Tokens.Metric.chromeGap), ("chromeGapWide", Tokens.Metric.chromeGapWide),
            ("controlRowGap", Tokens.Metric.controlRowGap), ("capsuleHeight", Tokens.Metric.capsuleHeight),
            ("reloadBlurRadius", Tokens.Metric.reloadBlurRadius), ("reloadProgressLine", Tokens.Metric.reloadProgressLine),
            ("settingsDefaultWidth", Tokens.Metric.settingsDefaultWidth),
            ("settingsDefaultHeight", Tokens.Metric.settingsDefaultHeight),
            ("settingsMinWidth", Tokens.Metric.settingsMinWidth),
            ("settingsMinHeight", Tokens.Metric.settingsMinHeight),
            ("settingsListWidth", Tokens.Metric.settingsListWidth),
            ("spaceCreateReach", Tokens.Metric.spaceCreateReach),
            ("spaceCreateGive", Tokens.Metric.spaceCreateGive),
            ("spaceCreateEntrance", Tokens.Metric.spaceCreateEntrance),
            ("spaceFlickSpeed", Tokens.Metric.spaceFlickSpeed),
            ("spaceFlickReach", Tokens.Metric.spaceFlickReach),
            ("spaceCreateRing", Tokens.Metric.spaceCreateRing),
            ("spaceCreateRingLine", Tokens.Metric.spaceCreateRingLine),
            ("spaceSwatchRing", Tokens.Metric.spaceSwatchRing),
            ("spaceSwipeSpeed", Tokens.Metric.spaceSwipeSpeed),
            ("sidebarProfileRow", Tokens.Metric.sidebarProfileRow),
            ("sidebarProfileGap", Tokens.Metric.sidebarProfileGap),
            ("spaceDotPitch", Tokens.Metric.spaceDotPitch)
        ]
        failures += scalars.filter { $0.1 <= 0 }.map { "Metric.\($0.0) is not positive" }
        return failures + checkSpaceSwipe() + checkRowInsets()
    }

    /// §30.9's gesture, re-derived rather than restated.
    ///
    /// The page is the ruler, and these are the two claims that keeps
    /// honest. Everything the gesture measures is a fraction of the column's
    /// own width, so the only numbers left to check are the ones that have to
    /// hold at every width the §3.7 handle reaches — and both of the bugs
    /// this area has shipped were a number that was fine at one width and
    /// wrong at another.
    private static func checkSpaceSwipe() -> [String] {
        var failures: [String] = []
        let metric = Tokens.Metric.self
        // Making a Space costs at least twice what reaching one does, and
        // this is no longer a comfortable margin — it is the only guard.
        // `SpaceSwipe.resolve` commits a switch at half a page (the 0.5 below
        // is that literal, and there is no token for it because the page is the
        // ruler), and a flick past the last Space used to be excluded by how it
        // ended. It is not any more: the ring is the threshold, and a rule that
        // made a closed circle mean nothing in some releases was the same lie
        // as a circle that closed early. So distance carries the whole weight
        // of telling a reflex from a decision, and it has to be a distance no
        // reflex covers.
        let commit: CGFloat = 0.5
        if metric.spaceCreateReach < commit * 2 {
            failures.append(String(
                format: "Metric.spaceCreateReach is %.2f pages against a %.2f page switch — a reflex would make Spaces",
                metric.spaceCreateReach, commit
            ))
        }
        // The create gesture has to be completable in one stroke, at the
        // widest the column gets. This is the check that was being made
        // against a comfortable width instead of the worst one, and the create
        // shipped unperformable: a ceiling on how fast a gesture may travel is
        // also a floor on how long a page takes to cover, and at 360 pt the
        // ring needed almost a quarter of a second of unbroken, saturated
        // movement — longer than an ordinary swipe lasts. Resistance that
        // cannot be overcome in one stroke is not resistance, it is a dead end.
        //
        // The stroke is 0.3 s and it was 0.25, which is not the bound being
        // relaxed to fit a number. The figure has to be the length of the
        // stroke this distance is actually covered by, and that stroke changed:
        // a create used to be a flick continued, so the bound was a flick's,
        // and it is now a deliberate push that ends at rest — `spaceFlickSpeed`
        // excludes the flick by design rather than by distance. A deliberate
        // push also runs under the damping knee, so the ceiling this divides
        // by barely applies to it; 0.3 s is still the conservative reading.
        let stroke: CGFloat = 0.3
        let widest = metric.spaceCreateReach * metric.sidebarWidth.max
        if widest > metric.spaceSwipeSpeed * stroke {
            failures.append(String(
                format: "Metric.spaceCreateReach is %.0f pt at the widest sidebar, %.0f pt/s — more than one stroke",
                widest, metric.spaceSwipeSpeed
            ))
        }
        // The create zone resists, and the resistance has to be visible in
        // the column. `spaceCreateGive` is where its travel bends over, so a
        // give at or past the reach is a column that follows the hand out as if
        // it were going somewhere — which is the one thing the gesture must not
        // look like, because it is the gesture for a Space that does not exist.
        // Under half the reach is where a whole page of push leaves the column
        // visibly held rather than visibly leaving.
        if metric.spaceCreateGive >= metric.spaceCreateReach / 2 {
            failures.append(String(
                format: "Metric.spaceCreateGive is %.2f of a %.2f page reach — the column is not resisting, it is leaving",
                metric.spaceCreateGive, metric.spaceCreateReach
            ))
        }
        // The `+` has to be standing still while the ring is still filling.
        // Its entrance is a fraction of the ring's own sweep, so at 1 it is
        // still sliding in at the instant the gesture commits and the read-out
        // is two things moving at once instead of one thing filling.
        if metric.spaceCreateEntrance <= 0 || metric.spaceCreateEntrance > 0.5 {
            failures.append(String(
                format: "Metric.spaceCreateEntrance is %.2f of the ring — the + is still arriving as the ring closes",
                metric.spaceCreateEntrance
            ))
        }
        // A flick is told from a drag by speed alone, so the threshold has
        // to sit inside the range the gesture can actually report: `damped`
        // holds it under `spaceSwipeSpeed`, and one that met or exceeded the
        // ceiling could never be reached — no swipe would ever turn a page
        // short of half a column, and none would be safe from making a Space.
        if metric.spaceFlickSpeed >= metric.spaceSwipeSpeed {
            failures.append(String(
                format: "Metric.spaceFlickSpeed is %.0f against a %.0f pt/s ceiling — no release can reach it",
                metric.spaceFlickSpeed, metric.spaceSwipeSpeed
            ))
        }
        // A flick still has to be a swipe rather than a twitch, and it must not
        // have to be half a page — that is the distance threshold it exists to
        // stand in for.
        if metric.spaceFlickReach <= 0 || metric.spaceFlickReach >= 0.5 {
            failures.append(String(
                format: "Metric.spaceFlickReach is %.2f pages — a flick is neither a twitch nor half a swipe",
                metric.spaceFlickReach
            ))
        }
        // The ring is drawn around the glass disc, so it has to be bigger
        // than one — and by enough to read as a ring with a button in it
        // rather than as a border painted on the button's edge.
        if metric.spaceCreateRing <= metric.bottomCircle.width + 2 * metric.spaceCreateRingLine {
            failures.append("Metric.spaceCreateRing does not clear the disc it is drawn around")
        }
        if metric.spaceCreateRingLine <= metric.hairline {
            failures.append("Metric.spaceCreateRingLine is at hairline — a progress ring has to be legible when part-drawn")
        }
        let gap = metric.spaceDotPitch - metric.spaceDot
        if gap < metric.spaceDot || gap > metric.spaceDot * 2 {
            failures.append(String(
                format: "Metric.spaceDotPitch leaves %.0f pt between %.0f pt dots — a row wants one to two dots of air",
                gap, metric.spaceDot
            ))
        }
        return failures
    }

    /// §3.4's row geometry, re-derived rather than trusted.
    ///
    /// The insets are the one place §3.4's prose is overridden by the
    /// reference, so what is checked is the rule the reference follows — the
    /// favicon square-inset inside the pill, the same padding leading as above
    /// and below — and that it still lands on the measured numbers (17.2 and
    /// 44.9 px/2.848, from `inspiration/main-tab-bar-and-ui.png`).
    private static func checkRowInsets() -> [String] {
        var failures: [String] = []
        let metric = Tokens.Metric.self
        let leading = metric.rowFaviconInset - metric.rowInset
        let vertical = (metric.rowPillHeight - metric.faviconSize) / 2
        if abs(leading - vertical) > 0.01 {
            failures.append(String(
                format: "Metric.rowFaviconInset leaves %.1f before the favicon and %.1f above it — §3.4 insets it squarely",
                leading, vertical
            ))
        }
        // 42.5, not §3.4's 45.5: `rowTitleGap` is deliberately 3 pt tighter
        // than the reference in the tab list, and only there. The check still
        // runs — it is what catches the next drift — it just expects the
        // number Luna actually ships.
        if abs(metric.rowFaviconInset - 17.5) > 0.5 || abs(metric.rowTitleInset - 42.5) > 0.5 {
            failures.append(String(
                format: "row insets are %.1f / %.1f — Luna draws 17.5 / 42.5 (§3.4's 45.5, less rowTitleGap)",
                metric.rowFaviconInset, metric.rowTitleInset
            ))
        }
        if metric.rowPillHeight <= 0 || metric.rowPillHeight >= metric.rowHeight {
            failures.append("Metric.rowPillHeight is not a pill inside its row")
        }
        // The chip has to be able to hold its glyph with padding left over, or
        // it is not a chip, it is a glyph with a border.
        if metric.rowTrailingGlyph >= metric.rowTrailingChip.width {
            failures.append("Metric.rowTrailingGlyph fills rowTrailingChip — the chip needs padding to read as a button")
        }
        if metric.rowTrailingChip.height > metric.rowPillHeight {
            failures.append("Metric.rowTrailingChip is taller than the pill it sits in")
        }
        if metric.rowTitleInset <= metric.rowFaviconInset + metric.faviconSize {
            failures.append("Metric.rowTitleInset overlaps the favicon")
        }
        if metric.rowGap >= metric.rowHeight {
            failures.append("Metric.rowGap eats the whole row")
        }
        return failures + checkChromeShapes()
    }

    /// The shapes the rows sit in — split out of `checkRowInsets` only because
    /// the two together tripped the complexity limit. Same checks, same order.
    private static func checkChromeShapes() -> [String] {
        var failures: [String] = []
        let metric = Tokens.Metric.self
        // §4's measured finding: the action capsule is taller than the pill it
        // sits beside. Equal heights mean someone "tidied" one into the other.
        if metric.capsuleHeight <= metric.urlPill.height {
            failures.append("Metric.capsuleHeight is not above urlPill.height — §4's capsule measures taller")
        }
        // §3.1: the toggle, back and reload are one circle, and it is the same
        // diameter as a top-bar capsule item — the two layouts agreeing on what
        // a chrome button is. It looked "tidy" as a squircle and it was wrong,
        // and at 35 it was a control as tall as the rows beneath it.
        if metric.controlCircle.cornerRadius * 2 != metric.controlCircle.width {
            failures.append("Metric.controlCircle is not a circle")
        }
        if metric.controlCircle.width != metric.controlSquircle.width {
            failures.append("Metric.controlCircle has drifted from the top bar's item size")
        }
        // A glyph has to fit its button with padding left over; at 17 in a
        // 28 pt circle it read as a glyph that outgrew the control.
        if metric.glyphSize >= metric.controlCircle.width * 0.65 {
            failures.append("Metric.glyphSize crowds controlCircle — the button reads as all glyph")
        }
        // The content pane is flush to three window edges, so anything smaller
        // than the window's own radius shows glass inside the window corners.
        if metric.contentCardRadius < metric.windowCornerRadius {
            failures.append("Metric.contentCardRadius is inside windowCornerRadius — the corners would not nest")
        }
        // §5.0: the file shrinks to the mark on the button it lands on, so
        // the button's glyph has to be the smaller of the two. Equal, and the
        // flight is an icon sliding across the window at a constant size.
        if metric.glyphSize >= metric.downloadsFileIcon {
            failures.append("Metric.glyphSize is not smaller than downloadsFileIcon — §5.0's flight would not shrink")
        }
        return failures + checkSettingsWindow()
    }

    /// §23.1 §1's settings window. Three claims, none of them restated from the
    /// numbers: the window can actually be resized down, the section list
    /// leaves a detail pane behind at the smallest the window goes, and the
    /// preview tile fits in that pane. A list that is wider than the pane it
    /// shares the window with is the failure mode here, and it only shows up
    /// once someone drags the window in.
    private static func checkSettingsWindow() -> [String] {
        var failures: [String] = []
        let metric = Tokens.Metric.self
        if metric.settingsMinWidth >= metric.settingsDefaultWidth
            || metric.settingsMinHeight >= metric.settingsDefaultHeight {
            failures.append("Metric.settings minimum is not below its default — the window would open at its floor")
        }
        let pane = metric.settingsMinWidth - metric.settingsListWidth
        if pane <= metric.settingsListWidth {
            failures.append(String(
                format: "Metric.settingsListWidth leaves a %.0f pt detail pane at the minimum width — the list would dominate", pane
            ))
        }
        if metric.glassPreviewTile.width + 2 * metric.chromeGapWide > pane {
            failures.append("Metric.glassPreviewTile does not fit the §3.2 pane at the settings window's minimum width")
        }
        return failures
    }

    /// §6: nothing over 0.35 s except the two entries tied to real work.
    static func checkMotion() -> [String] {
        let timed: [(String, MotionSpec)] = [
            ("rowHover", Tokens.Motion.rowHover), ("controlHover", Tokens.Motion.controlHover),
            ("controlPress", Tokens.Motion.controlPress), ("essentialGlow", Tokens.Motion.essentialGlow),
            ("selectedRowMove", Tokens.Motion.selectedRowMove), ("tabInsert", Tokens.Motion.tabInsert),
            ("spaceSwitch", Tokens.Motion.spaceSwitch), ("spaceSwitchCrossfade", Tokens.Motion.spaceSwitchCrossfade),
            ("sidebarCollapse", Tokens.Motion.sidebarCollapse), ("sidebarCollapseOpacity", Tokens.Motion.sidebarCollapseOpacity),
            ("layoutSwitch", Tokens.Motion.layoutSwitch), ("splitDividerSnap", Tokens.Motion.splitDividerSnap),
            ("cardFullscreen", Tokens.Motion.cardFullscreen), ("commandBarIn", Tokens.Motion.commandBarIn),
            ("popoverIn", Tokens.Motion.popoverIn), ("hoverPeek", Tokens.Motion.hoverPeek),
            ("themeWash", Tokens.Motion.themeWash), ("reloadArcIn", Tokens.Motion.reloadArcIn),
            ("reloadArcOut", Tokens.Motion.reloadArcOut),
            ("loadLineAdvance", Tokens.Motion.loadLineAdvance), ("loadLineFade", Tokens.Motion.loadLineFade),
            ("downloadFlight", Tokens.Motion.downloadFlight), ("downloadCatch", Tokens.Motion.downloadCatch)
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
        // The one entry §6 exempts: a repeating indicator whose duration is a
        // rate rather than a delay (§3.4's shimmer). It does not belong in
        // `timed` above.
        failures += exemption("rowShimmer", Tokens.Motion.rowShimmer, 1.10)
        if timed.contains(where: { $0.0 == "rowShimmer" }) {
            failures.append("Motion.rowShimmer is in the budget list — it loops, so 0.35 s would make it a strobe")
        }
        // §5.0: the catch is the bigger of the two answers a control gives,
        // and that is the whole reason there are two of them. A press is the
        // user doing something to the button and 5 % confirms it; a catch
        // happens in a corner they are not looking at. See `downloadCatchSwell`.
        if Tokens.Motion.downloadCatchSwell <= Tokens.Motion.pressSwell {
            failures.append("Motion.downloadCatchSwell is no larger than pressSwell — a catch is not a press")
        }
        return failures
    }

    /// One §6 budget exemption, checked by value so the exemption cannot be
    /// used to smuggle an arbitrary duration past the 0.35 s cap. It is not a
    /// spring: a spring settles, and §3.4's shimmer repeats forever.
    private static func exemption(_ name: String, _ spec: MotionSpec, _ expected: TimeInterval) -> [String] {
        var failures: [String] = []
        if abs(spec.duration - expected) > 0.001 {
            failures.append(String(format: "Motion.%@ is %.2f s — its §6 exemption is for %.2f s", name, spec.duration, expected))
        }
        if spec.isSpring {
            failures.append("Motion.\(name) is a spring — a spring settles, and an exemption is not allowed to")
        }
        return failures
    }
}

#endif
