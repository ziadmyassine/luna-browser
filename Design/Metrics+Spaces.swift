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

    /// §3.5's profile line: the row above the Space strip that names the
    /// profile the window's cookies belong to. One line of 11 pt type with the
    /// chrome's own 8 pt of air under it.
    static let sidebarProfileRow: CGFloat = 20

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
