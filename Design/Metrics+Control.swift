//
//  Metrics+Control.swift
//  Luna
//
//  Luna Control's settings pane: the sky above the switch, the moon and its
//  orbits, and the rows and cards beneath it (docs/LUNA-CONTROL.md, "The
//  Settings pane"). Kept out of Metrics+Windows.swift because none of it is
//  window geometry.
//

import Foundation

extension Tokens.Metric {

    /// The sky's height. Tall enough for a moon, two orbits and the title
    /// under them without the title crossing the lower orbit on the pane's
    /// narrowest width.
    static let controlSkyHeight: CGFloat = 232
    /// The moon's radius is a quarter of the sky's height, held between
    /// these two. The larger is what the default window gives it.
    static let controlMoonRadiusMax: CGFloat = 54
    static let controlMoonRadiusMin: CGFloat = 32
    /// How far the moon's centre sits in from the sky's trailing edge, which
    /// leaves the leading half of the sky to the title.
    static let controlMoonInset: CGFloat = 160
    /// Below this width the inset would push the moon into the title, so the
    /// moon sits at a fixed share of the width instead.
    static let controlSkyWide: CGFloat = 520
    /// The two orbits, as multiples of the moon's radius: the width and height
    /// of each ellipse's half-axes. Tilted by `controlOrbitTilt` radians.
    static let controlOrbitInner = CGSize(width: 1.80, height: 0.46)
    static let controlOrbitOuter = CGSize(width: 2.45, height: 0.70)
    static let controlOrbitTilt: CGFloat = -0.22
    /// An app's light: its core, and the glow round it.
    static let controlSatellite: CGFloat = 3.3
    /// An app's icon when it flies in place of the light: large enough to
    /// read as the app, small enough to stay a body on an orbit.
    static let controlSatelliteIcon: CGFloat = 22
    static let controlSatelliteGlow: CGFloat = 11
    /// One star for this much sky, in square points.
    static let controlStarSpacing: CGFloat = 1100
    /// How far the moon drifts under the pointer; stars drift further, by
    /// their own depth, up to `controlParallaxStars`.
    static let controlParallax: CGFloat = 3
    static let controlParallaxStars: CGFloat = 8
    /// The label chip in the sky's top corner, and its inset from both edges.
    static let controlChipHeight: CGFloat = 24
    static let controlSkyInset: CGFloat = 16

    /// An app's planet in the list, and the row that holds it.
    static let controlPlanet: CGFloat = 30
    static let controlAppRow: CGFloat = 56
    static let controlStatusDot: CGFloat = 7

    /// A permission card's round window on the sky, and the moon in it.
    static let controlModePorthole: CGFloat = 52
    static let controlModeMoon: CGFloat = 15

    /// The activity log's rail: the column it runs down and the dot on it.
    static let controlRailWidth: CGFloat = 14
    static let controlRailDot: CGFloat = 8
    static let controlTimeColumn: CGFloat = 52
}
