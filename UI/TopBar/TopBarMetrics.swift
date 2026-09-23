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
    /// §3.1's "gap 8", and the one gap between any two things on the bar: the
    /// lights and the plate, the plate and the first tab, two tabs, the tabs
    /// and the capsule. It used to be three numbers — 8, 16, and 16 plus
    /// whatever the run's own lead added — and the bar read as unevenly spaced
    /// even where each number had its reason.
    static var gap: CGFloat { Tokens.Metric.rowInset }
    /// The bar's trailing inset, from the capsule to the window's edge.
    static var clusterGap: CGFloat { Tokens.Metric.rowInset * 2 }
    /// From the green light to the plate. More than the bar's gap: the lights
    /// are three bare discs with no edge of their own, and at 8 pt the plate
    /// read as touching them.
    static var lightsGap: CGFloat { Tokens.Metric.rowInset * 1.5 }
    /// The height of everything standing on the bar's line: the capsule's, so
    /// the plate, the open tabs and the capsule are one height.
    static var lineHeight: CGFloat { capsuleItem.height + capsuleInset * 2 }
    /// §4's plate: the Space's name and every kept tab, on one piece of glass
    /// at the capsule's height. Its corner is a capsule item's squircle plus
    /// the capsule's padding — the corner a padded tile inside it would run
    /// parallel to.
    static var plate: RoundedMetric {
        let radius = Tokens.Metric.controlSquircle.cornerRadius + capsuleInset
        return RoundedMetric(width: lineHeight, height: lineHeight, cornerRadius: radius)
    }
    /// §4's kept tab: a box as tall as the plate, with the plate's own corner,
    /// so the lit one fills the plate top to bottom and its ends meet the
    /// plate's ends exactly. At rest it is its icon on the plate; the glass
    /// and §3.3's light are what the pointer and the selection bring out.
    ///
    /// It was the grid's own 42 pt for one build, then the row pill's 35, then
    /// a padded 28 inside the plate — which read as a box floating in a box.
    static var keptTile: RoundedMetric { plate }
    /// The narrowest an open tab goes. Wide enough that a short title still
    /// reads as a tab rather than as a label with a favicon in front of it —
    /// sized to the title alone, "Google" came out at 95 pt and looked like
    /// one; at 140 it was a tab too long.
    static var tabFloor: CGFloat { 120 }
    /// A tab inside a folder's plate. One width for all of them, shorter than
    /// a loose tab's: the plate reads as one object, a folder of tabs, and
    /// tabs of one width inside it are what make it read that way.
    static var folderTab: CGFloat { 100 }
    /// The room either side of the divider after a folder's name.
    static var dividerGap: CGFloat { gap }
    /// The narrowest a folder's header goes — room for its glyph and a few
    /// letters. Below it the name is an ellipsis with nothing in front of it.
    static var rowFloor: CGFloat { Tokens.Metric.rowTitleInset + Tokens.Metric.rowPillHeight }
    /// The widest. One long page title would otherwise take the whole bar and
    /// push every other tab out of reach; at 220 one long title still read
    /// as a tab too long beside the others.
    static var rowCeiling: CGFloat { 180 }
    /// The Space name's ceiling on this bar.
    static var nameCeiling: CGFloat { 180 }
    /// §3.5's dots under the name, a size down from the column's: a 5 pt dot
    /// for the column's 6, beside a name a point smaller than the tabs'.
    static var dotScale: CGFloat { 5 / 6 }
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
