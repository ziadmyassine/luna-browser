//
//  TopBarMetrics.swift
//  Luna
//
//  The §4 bar's gaps and control sizes. Its own file only because `TopBarView`
//  is at SwiftLint's 400-line limit — the same reason `TopBarSeparator` has
//  one — and because every view on the bar reads these rather than `TopBarView`.
//

import AppKit

/// §4 gives no gap table of its own, so the bar borrows §3.1's: 8 pt between
/// tight neighbours, 16 pt between clusters. Both are derived from an existing
/// token rather than written down again — there is no `chromeGap` token yet,
/// and rule 2 forbids inventing one here.
enum TopBarMetrics {
    /// §3.1's "gap 8".
    static var gap: CGFloat { Tokens.Metric.rowInset }
    /// §3.1's "gap 16", and the bar's own leading / trailing inset.
    static var clusterGap: CGFloat { Tokens.Metric.rowInset * 2 }
    /// §4's kept tab: §3.3's tile — the same well, hairline, radius and glow —
    /// made square at the height of §3.4's row pill.
    ///
    /// Not the grid's own 42 pt. It was, for one build, and on a 52 pt bar a
    /// run of 62 × 42 tiles stood a head taller than the rows beside them and
    /// all but touched the bar's edges. At the pill's height the kept tiles and
    /// the open rows share one line, which is what a bar is.
    static var keptTile: RoundedMetric {
        RoundedMetric(
            width: Tokens.Metric.rowPillHeight,
            height: Tokens.Metric.rowPillHeight,
            cornerRadius: Tokens.Metric.essentialsTile.cornerRadius
        )
    }
    /// Between two kept tiles: the grid's own gutter.
    static var keptGap: CGFloat { Tokens.Metric.essentialsTileGap }
    /// Between two rows: §3.4's gap between two pills, turned on its side.
    static var rowGap: CGFloat { Tokens.Metric.rowGap }
    /// The narrowest an open tab's pill goes — room for its favicon and a few
    /// letters. Below it the title is an ellipsis with nothing in front of it.
    static var rowFloor: CGFloat { Tokens.Metric.rowTitleInset + Tokens.Metric.rowPillHeight }
    /// The widest. One long page title would otherwise take the whole bar and
    /// push every other tab out of reach.
    static var rowCeiling: CGFloat { 200 }
    /// The Space cylinder's padding, and its height.
    static var groupPlateInset: CGFloat { gap / 2 }
    static var plate: RoundedMetric {
        let height = Tokens.Metric.controlSquircle.height + groupPlateInset * 2
        return RoundedMetric(width: height, height: height, cornerRadius: height / 2)
    }
    /// The Space cylinder's two arrows.
    static var arrow: RoundedMetric { .circle(Tokens.Metric.controlSquircle.width) }
    /// The Space name's ceiling on this bar.
    static var nameCeiling: CGFloat { 180 }
    /// One capsule item, and the diameter every button on this bar uses —
    /// back included. Round because the capsule it sits in is a cylinder with
    /// rounded ends.
    static var capsuleItem: RoundedMetric { .circle(Tokens.Metric.controlSquircle.width) }
    /// The capsule's padding around its items. Half a `rowInset`, which lands
    /// the capsule at 36 pt tall — the measured height in the reference.
    static var capsuleInset: CGFloat { Tokens.Metric.rowInset / 2 }
    /// Glyph and favicon size for every control on the bar.
    static var glyph: CGFloat { Tokens.Metric.faviconSize }

    /// How far the traffic lights' centre line falls below the bar's own, in
    /// AppKit's sense where a positive constant moves a view down.
    ///
    /// §3.1's control row shares that line and §4's bar has to as well, or the
    /// two layouts put the same three lights next to controls on two different
    /// lines. It is arithmetic rather than a measurement: the lights hang
    /// `trafficLightInset` from the window's top edge and the bar is
    /// `topBarHeight` tall against that same edge. Measuring it instead — from
    /// the lights' own rect, inside `layout()` — reads frames that the
    /// constants it is about to set have not been applied to yet, and the bar
    /// spends a pass wearing the offset for the size it used to be.
    static var lightsCentreOffset: CGFloat {
        Tokens.Metric.trafficLightInset + Tokens.Metric.trafficLightHeight / 2
            - Tokens.Metric.topBarHeight / 2
    }
}
