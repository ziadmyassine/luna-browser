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
    /// §3.1's "gap 8", and the one gap between any two things on the bar but
    /// two open tabs (`tabGap`): the lights and the plate, the plate and the
    /// first tab, the tabs and the capsule. It used to be three numbers — 8, 16, and 16 plus
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
    /// Every open tab's width, whatever its title — Dia's, measured off its
    /// tab strip on 2026-09-24: "New Tab" and "Roosta Deck Board" both 172 pt,
    /// 176 pt from one tab's start to the next. Sized to the title between 120
    /// and 180 pt, the bar was a row of different lengths that shifted every
    /// time a page's title arrived; a longer title now fades, as it does in
    /// the column.
    static var tabWidth: CGFloat { 172 }
    /// Between two open tabs: Dia's, off the same measurement — 176 pt from
    /// one tab's start to the next, less the 172 pt tab. The bar's `gap`
    /// between tabs read as a row of separate buttons rather than one strip.
    static var tabGap: CGFloat { 4 }
    /// The room either side of the divider after a folder's name.
    static var dividerGap: CGFloat { gap }
    /// The narrowest a folder's header goes — room for its glyph and a few
    /// letters. Below it the name is an ellipsis with nothing in front of it.
    static var rowFloor: CGFloat { Tokens.Metric.rowTitleInset + Tokens.Metric.rowPillHeight }
    /// The room an open folder's plate keeps past its first and last tab: the
    /// column's own (`groupMemberTrailingInset`, 8 pt — the room a loose tab
    /// keeps from the sidebar's edge), so a folder holds its tabs the same way
    /// in both layouts. Flush, the lit tab lay on the plate's ends; at 4 pt it
    /// still looked pressed against them.
    static var folderPadding: CGFloat { Tokens.Metric.groupMemberTrailingInset }
    /// How far an open folder's tabs stand in from its plate's top and bottom:
    /// `rowPillInset`, the sidebar's own gap between two row pills. Just
    /// enough that a lit tab reads as lying on the plate, not as filling it.
    static var folderLift: CGFloat { Tokens.Metric.rowPillInset }
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

    /// The bar's height: twice the traffic lights' centre line, so the bar's
    /// own middle is the lights' line and a tab standing on it has the same
    /// room above as below — 7 pt each side of the 36 pt line. The bar was the
    /// sidebar's 52 pt row (`topBarHeight`) until 2026-09-24, which left the
    /// tabs 7 pt from the window's top edge and 9 pt from the page.
    static var barHeight: CGFloat {
        (Tokens.Metric.trafficLightInset + Tokens.Metric.trafficLightHeight / 2) * 2
    }

    /// How far the traffic lights' centre line falls below the bar's own, in
    /// AppKit's sense where a positive constant moves a view down. Zero while
    /// `barHeight` is derived from that line; kept so the relation stays
    /// written down in the one place both constraints read it.
    ///
    /// §3.1's control row shares that line and §4's bar has to as well, or the
    /// two layouts put the same three lights next to controls on two different
    /// lines. It is arithmetic rather than a measurement: the lights hang
    /// `trafficLightInset` from the window's top edge and the bar is
    /// `barHeight` tall against that same edge. Measuring it instead — from
    /// the lights' own rect, inside `layout()` — reads frames that the
    /// constants it is about to set have not been applied to yet, and the bar
    /// spends a pass wearing the offset for the size it used to be.
    static var lightsCentreOffset: CGFloat {
        Tokens.Metric.trafficLightInset + Tokens.Metric.trafficLightHeight / 2
            - barHeight / 2
    }
}
