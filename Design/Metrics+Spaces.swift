//
//  Metrics+Spaces.swift
//  Luna
//
//  §8.2's Space-identity metrics, plus the two menu sizes. Its own file because
//  Metrics.swift sits on the 400-line limit.
//
//  The gradient values are in SpacePalette.swift; these are the sizes the three
//  intensities of §8.2a are drawn at. `spaceDot` stays in Metrics.swift next to
//  the §3.5 pill it lives inside.
//

import Foundation

extension Tokens.Metric {

    // MARK: - §3.5's Space strip

    /// Centre to centre between two Space dots.
    ///
    /// A constant, and it used to be a division: the strip split the pill's
    /// width by the number of Spaces, so two Spaces in a 56 pt pill stood 28 pt
    /// apart and eight in a 96 pt pill stood 12 pt apart. A page indicator has
    /// one spacing; the pill is what changes size.
    ///
    /// 14, not the two-diameter 12 a page control usually uses — at a 6 pt dot
    /// that left 6 pt of clear space and three marks read as one dashed line.
    static let spaceDotPitch: CGFloat = 14

    /// The most Spaces §3.5's strip shows at once.
    ///
    /// The pill is sized to its dots, so twelve Spaces made a 160 pt strip in a
    /// footer that also holds the Space pill and the library cylinder — at which
    /// point the dots are neither countable nor individually hittable. Three is
    /// the window: the Space you are in, the one behind and the one ahead, which
    /// is the set §30.9's swipe can reach from here. The rest of the run slides
    /// through it — see `SpaceDotsView.windowStart`.
    static let spaceDotWindow = 3

    // MARK: - SPACES-SPEC D-S12's swipe, read out on §30.9's strip

    /// The page is the ruler, so there is no constant here for one Space.
    ///
    /// Every number this used to be — 220, then 120 — was wrong at some sidebar
    /// width, because the thing the gesture moves is a page and the §3.7 handle
    /// makes a page anything from 250 to 420 pt wide. 120 against a 280 pt
    /// column moved the page 2.33 pt for every point of finger, which is the
    /// "it multiplies my swipe" this gesture was reported for twice. Damping the
    /// system's acceleration did not touch it: the multiplier was this division.
    ///
    /// One page of hand is one page of column at every width, and half a page
    /// commits. `SpaceSwipe.resolve` is handed the span for that reason. What a
    /// short swipe costs is paid by `spaceFlickSpeed` instead.

    /// Where the system's acceleration starts being taken back off, in points
    /// of hand per second.
    ///
    /// A knee, not a wall. `scrollingDeltaX` on a trackpad is not how far the
    /// fingers moved — macOS scales it by how fast they moved, so one firm flick
    /// arrives as several hundred points of travel for eighty points of hand. A
    /// flat gain would fix the flick by making a slow drag feel sticky, since a
    /// slow drag is barely accelerated to begin with. So the curve is 1:1 at the
    /// bottom and bends over at the top — see `SpaceSwipeController.damped`.
    ///
    /// 1600, and it was 900 as a hard clip for one build. Both halves were
    /// wrong: a hard clip turns every event into exactly the ceiling, so the
    /// page travels at one fixed speed and the gesture is played back rather
    /// than followed; and 900 pt/s is under a deliberate drag, so the clip fired
    /// on the whole gesture. 1600 pt/s is about where a hand stops moving and
    /// starts flicking. Stated as a speed rather than points per event so it
    /// means the same thing at 60 Hz and 120 Hz.
    static let spaceSwipeSpeed: CGFloat = 1600

    /// The release speed at which a swipe stops being a drag and becomes a
    /// flick — the page turns however far the fingers actually got.
    ///
    /// This is what pays for a page being a page wide. Half of a 280 pt column
    /// is 140 pt of finger, and a reflex performed dozens of times a day cannot
    /// cost that; a distance threshold could only meet "one single fast swipe
    /// should go to the next Space" by being short, which is what put the page
    /// ahead of the hand. So a short stroke still moving when it ends is a page
    /// turn, a long one that has come to rest is a page turn, and a short one
    /// that has come to rest springs back.
    ///
    /// Measured against the damped travel, not the raw delta, which is why it
    /// can be a plain number: `damped` holds the reported speed under
    /// `spaceSwipeSpeed`, so this is a little over a third of the fastest thing
    /// the gesture can report. A deliberate drag runs at two or three hundred
    /// points a second; a flick saturates the ceiling and clears this four times
    /// over.
    static let spaceFlickSpeed: CGFloat = 550

    /// The least a flick must still have covered, in pages.
    ///
    /// A tenth of a column, under 30 pt. Not resistance: two fingers landing on
    /// the trackpad with a little sideways momentum can report one fast event
    /// and nothing else, and without a floor that would turn the page.
    static let spaceFlickReach: CGFloat = 0.1

    /// How far past the last Space the same two fingers travel to make a new
    /// one, in pages — and the sweep of §30.9's ring, because they are the same
    /// distance.
    ///
    /// The ring is the threshold. It used to close a third of the way in while
    /// the gesture committed at the end, so a user who did what the read-out
    /// told them — push until the circle closes, let go — got nothing. When it
    /// is full, letting go makes a Space; when it is not, it does not; panning
    /// back empties it, which is how the gesture is called off.
    ///
    /// One page of hand, twice what changing Space costs (`SpaceSwipe.resolve`
    /// commits a switch at half a page). That asymmetry is the only thing
    /// standing between a reflex off the end of the Spaces and a Space nobody
    /// asked for, so `TokenCheck` holds it.
    ///
    /// It was three pages' worth and could not be performed: 360 pt against a
    /// damping ceiling of 1600 pt/s needs almost a quarter second of unbroken
    /// saturated movement, and an ordinary swipe lasts a sixth. One page is the
    /// most this can be and still be performable at the widest the §3.7 handle
    /// goes — `TokenCheck.checkSpaceSwipe` checks it against that width.
    static let spaceCreateReach: CGFloat = 1

    /// How far the column is actually pushed by that page of hand, in pages —
    /// the resistance.
    ///
    /// The create zone is the one place the page stops being the ruler.
    /// Everywhere else the column is going somewhere and the hand takes it
    /// there; past the last Space there is nowhere to go, so the column is held
    /// against a stop while the ring fills, and a stop the hand slides through
    /// is not one. The travel is 1:1 under the fingers at first, so the `+`
    /// slides in as part of the same movement, and stiffens the further it is
    /// pushed.
    ///
    /// 0.4, so a whole page of hand leaves the column a little under half way
    /// out: far enough to read as pushed, nowhere near far enough to read as
    /// gone. The rest of that journey is the commit's, in one movement the
    /// moment the fingers leave.
    static let spaceCreateGive: CGFloat = 0.4

    /// How much of the ring's sweep the `+` disc spends arriving, as a fraction
    /// of it.
    ///
    /// The disc is not a progress bar and must not be paced like one: one that
    /// took the ring's whole sweep would still be crossing the column when the
    /// gesture was already half paid for. At a third the `+` is settled at its
    /// own margin with two thirds of a ring still to fill — a thing that appears
    /// and then a thing that fills.
    static let spaceCreateEntrance: CGFloat = 1.0 / 3

    /// §30.9's ring, drawn around the sidebar's `+` disc.
    ///
    /// One of these, and it used to be two: a 14 pt copy also stood in the §3.5
    /// strip. The strip is a read-out of which Space, and a `+` in it is an
    /// answer to a different question sitting in the middle of that answer — so
    /// the strip is dots only, and the gesture is read where it is happening.
    ///
    /// 46 against a 34 pt disc leaves 6 pt of clear sidebar between the glass
    /// and the ring. Drawn outside rather than on the disc's own edge, for
    /// `SpaceSwatchChip`'s reason: a ring painted over the edge of a glass
    /// button takes a bite out of the button.
    static let spaceCreateRing: CGFloat = 46

    /// The ring's stroke.
    ///
    /// A ring reads by its weight against its own diameter, not by its width in
    /// points: at the 1.5 pt the 14 pt strip mark used, a ring this size was a
    /// hairline round a glass button, too thin to read how full it was. This is
    /// the same tenth of a diameter at the size it is actually drawn.
    static let spaceCreateRingLine: CGFloat = 4

    /// The ring a chosen §6.2 swatch wears (`SpaceSwatchChip`).
    ///
    /// Its own number. It borrowed `spaceCreateRingLine` for one build, which is
    /// how thickening a gesture's progress ring would have resized a grid of
    /// colours: this is a selection mark on a 28 pt disc, that is a read-out on
    /// a 46 pt one.
    ///
    /// The disc inside is inset by twice it, so the ring is drawn outside the
    /// colour with a stroke's worth of air between — a border painted over the
    /// edge takes a tenth of the colour away, and that tenth is the darkest part
    /// of the ramp.
    static let spaceSwatchRing: CGFloat = 1.5

    /// Either side of the name in §3.5's Space pill (`SidebarSpacePill`).
    ///
    /// The room §4's name has in its cylinder (`TopBarMetrics.gap`), so the
    /// Space is the same pill in both layouts.
    static let sidebarSpacePillPad = rowInset

    /// How far a name too long for §3.5's Space pill takes to dissolve, which
    /// is twice what a §3.4 row takes.
    ///
    /// The row's 12 pt ramp ends against the pill's inner edge, where the eye
    /// already expects the line to stop, and at 12 pt the last glyph here read
    /// as a letter that had been cut rather than a name that ran out. 24 starts
    /// the dissolve about two characters early, so the tail thins rather than
    /// stopping.
    static let sidebarSpaceNameFade = 2 * rowTitleFade

    /// A gradient swatch in a menu (§8.2's picker).
    ///
    /// 14 pt, a ceiling rather than a preference: `NSMenuItem.image` is laid out
    /// against the menu's own font, so a swatch taller than the cap height
    /// pushes every row in the menu apart, including the rows with no image.
    static let menuSwatch: CGFloat = 14

    /// §3.4a's glyph beside a menu item's word — the pin, the link, the speaker.
    ///
    /// Two points under `menuSwatch`, and not for that one's reason. A swatch is
    /// a solid disc and reads at any size; a symbol is a line drawing, and at
    /// 14 pt it was heavier than the word beside it. 12 pt sits just under the
    /// menu font's cap height.
    static let menuGlyph: CGFloat = 12
}
