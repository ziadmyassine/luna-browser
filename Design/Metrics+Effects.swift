//
//  Metrics+Effects.swift
//  Luna
//
//  §5's downloads popover, §7's reload bloom and §3.3's selection glow. Split
//  out of Metrics.swift when it crossed the 400-line file limit.
//

import Foundation

extension Tokens.Metric {

    // MARK: Downloads popover (§5)

    /// ~330 × 58, radius 14.
    static let downloadsPopover = RoundedMetric(width: 330, height: 58, cornerRadius: 14)
    static let downloadsFileIcon: CGFloat = 34
    static let downloadsConfirm = RoundedMetric(width: 30, height: 30, cornerRadius: 9)
    /// The side of §5's pointer tail: a square rotated 45° and half-buried in
    /// the popover's bottom edge, so the tip reaches `tail × √2 / 2` below the
    /// body. §5 draws the tail and gives it no number; taking it from the
    /// popover's own corner radius keeps it proportioned to the surface it
    /// grows out of.
    static let downloadsPopoverTail = downloadsPopover.cornerRadius

    // MARK: Password autofill (§14.3, §14.4)

    /// The credential picker anchored to a login field. Narrower than §5's
    /// downloads popover: its content is one line of username, and a picker as
    /// wide as the page's form reads as part of the page, which §14.3 says it
    /// must never look like.
    static let passwordPopover = RoundedMetric(width: 288, height: 44, cornerRadius: 12)
    /// Gap between the bottom of the login field and the top of the popover, so
    /// the field's focus ring stays visible underneath.
    static let passwordPopoverOffset: CGFloat = 6
    /// The most rows shown before the list scrolls. Past five a picker stops
    /// being a glance and starts being a list to read.
    static let passwordPopoverMaxRows = 5
    /// §14.4's save chip. Wider than the picker: a sentence and three buttons
    /// rather than a username.
    static let passwordChip = RoundedMetric(width: 360, height: 92, cornerRadius: 14)

    // MARK: Reload bloom (§7)

    /// §7's "light (8 pt), not illegible" blur on the frozen snapshot. Points,
    /// not pixels: the snapshot comes back at the display's backing scale, so
    /// the caller scales this into snapshot space or the blur is half as strong
    /// at 1x and twice as strong on a future 3x.
    static let reloadBlurRadius: CGFloat = 8
    /// §7's Reduce Motion path: a 2 pt progress line across the top of the
    /// content card, no blur and no arc.
    static let reloadProgressLine: CGFloat = 2

    // MARK: Essentials glow (§3.3)

    /// The lit ring round a selected tile: a 1.5 pt line just outside the
    /// tile's hairline, with a bloom carrying 7 pt past it.
    ///
    /// Measured against the reference, then halved. The three tiles in
    /// `inspiration/pinned-tab-glow-*.png` carry a ring about 3 pt thick with a
    /// bloom reaching 14, which at Luna's 5 pt tile gutter has neighbouring
    /// tiles bleeding into each other. Martin's note was "not too thick (not as
    /// thick as the references)". Rendered offscreen at 1.0/5, 1.5/7, 2/9 and
    /// 2.5/12, this is the gauge that still reads as light. `reach` is a
    /// Gaussian radius rather than an edge, so the visible part lands inside
    /// the gutter even though the arithmetic runs past it.
    static let essentialsGlowRim: CGFloat = 1.5
    static let essentialsGlowReach: CGFloat = 7

    /// The three alphas the glow applies to the favicon's colour. Numbers here
    /// rather than colours in Tokens.swift because nothing in this group names
    /// a colour — they are gauges for one that is handed in.
    ///
    /// The rim sits under 1 so the ring reads as light rather than as a drawn
    /// border. `glowBleed` is the colour that gets inside the glass, which is
    /// the difference between a ring round a tile and a tile that has been lit;
    /// at 5 % it is a suggestion, where the reference's heavier bleed turned a
    /// dark tile into a coloured plate.
    static let essentialsGlowRimAlpha: CGFloat = 0.80
    static let essentialsGlowBleed: CGFloat = 0.05
    /// The bloom's opacity. It carries the glow on a dark sidebar and does much
    /// less on a light one, where a coloured haze over a near-white plane has
    /// nothing to be brighter than and the rim does the work.
    static let essentialsGlowBloom: Float = 0.85
}
