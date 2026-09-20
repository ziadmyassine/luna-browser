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

    /// The most Spaces §3.5's strip shows at once.
    ///
    /// **A page indicator is a read-out, and a read-out that grows without
    /// limit stops being one.** The pill is sized to its dots, so twelve Spaces
    /// made a 160 pt strip in a footer that also holds an avatar and the
    /// library cylinder — at which point the dots are neither countable nor
    /// individually hittable, and the bar is full of them. Three is the window:
    /// the Space you are in, the one behind and the one ahead, which is exactly
    /// the set §30.9's swipe can reach from here. The rest of the run slides
    /// through it — see `SpaceDotsView.windowStart`.
    static let spaceDotWindow = 3

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
    /// **A column's width, because the gesture now moves a column.** It was 80
    /// while the swipe only leaned the content 40 pt and let the strip do the
    /// talking. The swipe is a page turn now: the live column travels its own
    /// full width and the next one travels in behind it, so 80 meant the page
    /// ran at three times the speed of the hand pushing it — which is what
    /// "the scroll is multiplied" was describing. At a default 280 pt sidebar
    /// the page is about 264 pt across and this is 220, so it tracks the
    /// fingers to within a fifth. Not derived from `sidebarWidth`: the handle
    /// is draggable and `SpaceSwipe.resolve` is arithmetic that has to mean the
    /// same thing at every width.
    static let spaceSwipeTravel: CGFloat = 220

    /// The fastest §30.9's page is allowed to travel, in points of page per
    /// second of gesture.
    ///
    /// **This is the de-accelerator, and it is the other half of why the swipe
    /// felt multiplied.** `scrollingDeltaX` on a trackpad is not how far the
    /// fingers moved: macOS scales it by how fast they moved, so one firm flick
    /// arrives as several hundred points of "travel" for eighty points of hand.
    /// A flat gain would fix the flick by making a slow, deliberate drag feel
    /// sticky, because a slow drag is barely accelerated to begin with. A
    /// **ceiling on speed** touches only the motion that was multiplied: each
    /// event may contribute at most this much per second of the time since the
    /// last one, so honest movement passes through untouched and the
    /// multiplier is clipped off the top.
    ///
    /// 900 pt/s is a fast hand — roughly the whole sidebar in a third of a
    /// second — and it is stated as a speed rather than as points per event so
    /// it means the same thing on a 60 Hz panel and a 120 Hz one.
    static let spaceSwipeSpeed: CGFloat = 900

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
    static let spaceCreateTravel: CGFloat = 440

    /// §30.9's ring, standing in the slot where the new dot will be. 14 pt
    /// leaves 4 pt of pill above and below it, which is the same air the 6 pt
    /// dots have around them once the ring is counted as the mark.
    static let spaceCreateRing: CGFloat = 14

    /// The strip ring's stroke. Above `hairline`: a 1 pt circle 14 pt across
    /// reads as a smudge rather than as a ring, and this one is a progress
    /// read-out whose *fullness* has to be legible at a glance.
    static let spaceCreateRingLine: CGFloat = 1.5

    /// The same ring at the sidebar's own size (`SpaceCreationView`), and
    /// **deliberately not the same stroke**.
    ///
    /// The two marks are one affordance at two sizes, which is a claim about
    /// how they *read*, not about how many points wide their outlines are. A
    /// ring's weight to the eye is its stroke against its diameter: 1.5 on a
    /// 14 pt mark is a tenth, and the same tenth on the 34 pt disc is this. At
    /// the strip's 1.5 the big ring was a hairline drawn round a glass button —
    /// thin enough that how full it was could not be read at the distance the
    /// hand is actually looking, which is the one thing it is there to say.
    static let spaceCreateDiscLine: CGFloat = 3.5

    /// The `+` inside the ring, sized to clear the stroke on both sides.
    static let spaceCreatePlus: CGFloat = 7

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
