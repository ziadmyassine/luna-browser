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
    /// §4: inactive tabs are 28 pt icon-only tiles.
    static var tile: RoundedMetric { Tokens.Metric.controlSquircle }
    /// One capsule item, and the diameter **every** button on this bar uses —
    /// back included. Round because the capsule it sits in is a cylinder with
    /// rounded ends.
    static var capsuleItem: RoundedMetric { .circle(Tokens.Metric.controlSquircle.width) }
    /// The capsule's padding around its items. Half a `rowInset`, which lands
    /// the capsule at 36 pt tall — the measured height in the reference.
    static var capsuleInset: CGFloat { Tokens.Metric.rowInset / 2 }
    /// Glyph and favicon size for every control on the bar.
    static var glyph: CGFloat { Tokens.Metric.faviconSize }

    /// The weight a symbol has to be drawn at to carry the same ink as the rest
    /// of the bar's glyphs.
    ///
    /// **SF Symbols size to a shared cap height, not to a shared amount of
    /// mark.** Measured at `glyph` pt, `plus` covers 36 pt² of ink in a 14 × 14
    /// box, `arrow.down.to.line` 57, `clock.arrow.circlepath` 79 and
    /// `person.crop.circle` 116 — and `chevron.backward` 28, in a box 8 pt
    /// wide. Back is a bare pair of diagonals and nothing else, so at the same
    /// nominal size it is the faintest thing on the bar, sitting a bar's width
    /// from the heaviest cluster on it. Semibold puts it at 39, just past
    /// `plus`, without making it taller than its neighbours.
    ///
    /// A chevron is the only mark this is true of, so it is the only one named.
    static func weight(for symbolName: String) -> NSFont.Weight {
        symbolName.hasPrefix("chevron.") ? .semibold : .regular
    }

    /// How far the traffic lights' centre line falls below the bar's own, in
    /// AppKit's sense where a positive constant moves a view **down**.
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
