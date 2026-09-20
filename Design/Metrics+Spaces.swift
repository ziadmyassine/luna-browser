//
//  Metrics+Spaces.swift
//  Luna
//
//  §8.2's Space-identity metrics. Its own file for the reason `+Effects` and
//  `+Windows` are theirs: `Metrics.swift` sits exactly on SwiftLint's 400-line
//  limit, so anything added to it has to evict something first.
//
//  The gradient *values* are in `SpacePalette.swift`; these are the sizes the
//  three intensities of §8.2a are drawn at. `spaceDot` stays in `Metrics.swift`
//  next to the §3.5 pill it lives inside.
//
//  The two menu sizes live here as well, beside the swatch that was the first of them.
//  They belong together — both are "how big is the thing to the left of a menu item's
//  word" — and neither has anywhere better to go while `Metrics.swift` sits on the line.
//

import Foundation

extension Tokens.Metric {

    // MARK: - §3.5's Space strip

    /// Centre to centre between two Space dots.
    ///
    /// **It is a constant, and it used to be a division.** The strip took the
    /// pill's width and split it by the number of Spaces, so the spacing was a
    /// consequence of how wide the pill happened to be: two Spaces in a 56 pt
    /// pill stood 28 pt apart — four dot diameters of glass between two marks
    /// whose whole job is to read as one row — and eight Spaces in a 96 pt pill
    /// stood 12 pt apart. One strip, two densities, neither chosen. A page
    /// indicator has one spacing; the pill is what changes size.
    ///
    /// **14, and it was 12 for one build.** Two diameters is where a page
    /// control usually sits, and at a 6 pt dot that put the marks 6 pt apart —
    /// tight enough that three of them started to read as one dashed line
    /// rather than as three things. A dot and a third of clear space between
    /// them is where a row still reads as a group and the individual dots are
    /// still individual, which is the whole job of the strip.
    static let spaceDotPitch: CGFloat = 14

    /// Between §3.5's profile line and the Space strip it labels.
    ///
    /// **Its own number because both neighbours are fixed and this is the only
    /// thing left to tune.** The caption was 18 pt clear of the dots when it
    /// stood above the utility bar, and `rowGap`'s 3 pt put it close enough to
    /// touch. A label belongs to the thing under it at about half a line of
    /// leading, which at 11 pt type is this.
    static let sidebarProfileGap: CGFloat = 6

    // MARK: - SPACES-SPEC D-S12's swipe, read out on §30.9's strip

    /// How far two fingers travel across the sidebar for **one Space**.
    ///
    /// Measured against the gesture it has to live beside rather than picked:
    /// `NSScrollView` treats roughly this much precise scrolling as one
    /// decisive flick, so a Space costs about what a page of a list costs, and
    /// a short flick still carries past the half-way mark that commits it.
    static let spaceSwipeTravel: CGFloat = 80

    /// How far **past the last Space** the same two fingers travel to close
    /// §30.9's ring and make a new one.
    ///
    /// **Twice `spaceSwipeTravel`, and that ratio is the whole of the
    /// resistance.** Moving between Spaces is a reflex performed many times a
    /// day; creating one is a thing you do a handful of times ever, and the two
    /// are the same gesture continued. Anything that can be reached by
    /// over-flicking the reflex will be reached by accident, so the second half
    /// of the gesture is deliberately heavier than the first — the ring is only
    /// closed by a hand that kept going on purpose.
    static let spaceCreateTravel: CGFloat = 160

    /// §30.9's ring, standing in the slot where the new dot will be. 14 pt
    /// leaves 4 pt of pill above and below it, which is the same air the 6 pt
    /// dots have around them once the ring is counted as the mark.
    static let spaceCreateRing: CGFloat = 14

    /// The ring's stroke. Above `hairline`: a 1 pt circle 14 pt across reads as
    /// a smudge rather than as a ring, and this one is a progress read-out
    /// whose *fullness* has to be legible at a glance.
    static let spaceCreateRingLine: CGFloat = 1.5

    /// The `+` inside the ring, sized to clear the stroke on both sides.
    static let spaceCreatePlus: CGFloat = 7

    /// How far the sidebar's content slides under a full Space of swipe.
    ///
    /// A **fraction** of the column, not the whole of it. A page-sized
    /// translation would mean the list has to be drawn twice — the one leaving
    /// and the one arriving — and there is nothing to draw for the second until
    /// the Space is switched, which is the thing the gesture has not decided
    /// yet. So the content leans the way the fingers are going and the §6
    /// cross-fade does the rest; the swipe's real read-out is the wash and the
    /// strip, both of which can show a Space that is not loaded.
    static let spaceSwipeParallax: CGFloat = 40

    /// §3.5's profile line, which names the profile the window's cookies
    /// belong to.
    ///
    /// **One line of 11 pt type and nothing else.** It used to be 20 — a line
    /// with padding, sitting above the utility bar — and between that padding
    /// and the 15 pt of bar above the Space pill the caption ended up 18 pt
    /// clear of the dots it labels. It is 14 because that is what the type
    /// needs; the distance to the strip is `rowGap`, set where it is laid out.
    static let sidebarProfileRow: CGFloat = 14

    /// A gradient swatch in a menu (§8.2's picker).
    ///
    /// 14 pt, and it is a ceiling rather than a preference: `NSMenuItem.image`
    /// is laid out against the menu's own font, so a swatch taller than the cap
    /// height pushes every row in the menu apart — including the rows that have
    /// no image at all.
    static let menuSwatch: CGFloat = 14

    /// §3.4a's glyph beside a menu item's word — the pin, the link, the speaker.
    ///
    /// **Two points under `menuSwatch`, and not for the same reason that one is 14.** A
    /// swatch is a solid disc and reads at whatever size it is given; a symbol is a line
    /// drawing, and at the swatch's size it was heavier than the word it sits beside and
    /// pulled the eye off the text. 12 pt sits just under the menu font's cap height,
    /// which is where a glyph stops competing with the label and starts introducing it.
    static let menuGlyph: CGFloat = 12
}
