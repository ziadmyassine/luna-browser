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
    /// §4: a kept tab is a 28 pt icon-only tile — and, since the bar took
    /// Safari's language, a circle. A capsule with no word in it is a circle;
    /// there is no separate shape here, only a chip with nothing to say.
    static var tile: RoundedMetric { .circle(Tokens.Metric.controlSquircle.width) }
    /// §4: an open tab, and a folder's header — the tile stretched to hold a
    /// word, at the same full radius, so the run reads as one family of
    /// capsules rather than as circles beside squircles. Its width is its
    /// title's; see `TopBarButton.intrinsicContentSize`.
    static var chip: RoundedMetric {
        RoundedMetric(width: tile.width, height: tile.height, cornerRadius: tile.height / 2)
    }
    /// The glass cylinder the kept run stands in, and the recessed plate a
    /// folder stands on: the chip's height plus its padding, at full radius.
    static var plate: RoundedMetric {
        let height = chip.height + groupPlateInset * 2
        return RoundedMetric(width: height, height: height, cornerRadius: height / 2)
    }
    /// The chip's padding either side of its contents. Half a `rowInset`, so a
    /// chip's favicon stands the same distance from its own edge as a tile's
    /// does from its — a tile is 28 wide around a 16 pt glyph, which is 6.
    static var chipInset: CGFloat { (tile.width - glyph) / 2 }
    /// The narrowest a chip goes: the tile it grew out of, plus room for a few
    /// letters. Below this the title is an ellipsis with nothing in front of it,
    /// which says less than the favicon beside it already said.
    static var chipFloor: CGFloat { tile.width * 3 }
    /// The widest. One long page title would otherwise take the whole bar and
    /// push every other tab out of reach.
    static var chipCeiling: CGFloat { 180 }
    /// The plate an opened folder's tabs stand on, inset from the run's own
    /// line so the folder reads as one thing rather than as a header that
    /// happens to be next to some tabs.
    static var groupPlateInset: CGFloat { gap / 2 }
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
