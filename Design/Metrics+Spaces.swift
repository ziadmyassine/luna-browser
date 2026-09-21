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
    /// **One swipe across a trackpad, and no more than that.** Changing Space
    /// is a reflex performed dozens of times a day, and a reflex that needs a
    /// second stroke is not one — this is short enough that a single
    /// comfortable slide crosses the half of it that commits. It was 220 for
    /// one build, which is about the width the page travels: the column then
    /// tracked the fingers almost exactly, and the gesture cost more than what
    /// it did was worth. The page leads the hand by about two to one at 120,
    /// which is a page turn following a flick rather than a sheet being
    /// dragged, and that is the right trade the moment the distance is the
    /// thing being complained about.
    ///
    /// The **resistance lives in `spaceCreateTravel` alone**, which is the
    /// whole point of having two numbers: reaching a Space you already have
    /// should be free, and making one should not be.
    static let spaceSwipeTravel: CGFloat = 120

    /// Where the system's acceleration starts being taken back off, in points
    /// of hand per second.
    ///
    /// **This is the de-accelerator's knee, and it is not a wall.**
    /// `scrollingDeltaX` on a trackpad is not how far the fingers moved: macOS
    /// scales it by how fast they moved, so one firm flick arrives as several
    /// hundred points of "travel" for eighty points of hand. A flat gain would
    /// fix the flick by making a slow, deliberate drag feel sticky, because a
    /// slow drag is barely accelerated to begin with. So the curve is 1:1 at
    /// the bottom and bends over at the top: movement under this speed passes
    /// through untouched and movement far above it is compressed toward it —
    /// see `SpaceSwipeController.damped`.
    ///
    /// **1600, and it was 900 as a hard clip for one build.** Both halves of
    /// that were wrong in the hand. A hard clip turns every event a real swipe
    /// delivers into exactly the ceiling, which is a page travelling at one
    /// fixed speed no matter what the hand is doing — the gesture stops being
    /// followed and starts being played back. And 900 pt/s is *under* a
    /// deliberate drag, let alone a flick, so the clip was firing on the whole
    /// gesture rather than on the accelerated top of it: `spaceCreateTravel`'s
    /// 360 pt then needed four tenths of a second of sustained movement, which
    /// is longer than a trackpad stroke lasts, so the ring could not be closed
    /// in one go at all.
    ///
    /// 1600 pt/s is about where a hand stops moving and starts flicking: a
    /// deliberate drag runs well under it and loses nothing, and a flick
    /// arrives at three or four times it and is folded back down. Stated as a
    /// speed rather than as points per event so it means the same thing on a
    /// 60 Hz panel and a 120 Hz one.
    static let spaceSwipeSpeed: CGFloat = 1600

    /// How far **past the last Space** the same two fingers travel to close
    /// §30.9's ring and make a new one.
    ///
    /// **Three times `spaceSwipeTravel`, and this is the only place any
    /// resistance lives.** Moving between Spaces is a reflex; creating one is
    /// a thing you do a handful of times ever, and the two are the same gesture
    /// continued — so anything that can be reached by over-flicking the reflex
    /// will be reached by accident. The ratio was two for one build, when the
    /// switch itself was long; now that a switch is one easy slide, a create
    /// has to be a deliberate stroke rather than the same slide continued.
    ///
    /// **The resistance is now in the two thirds after the ring closes, which
    /// is where it was always supposed to be.** The ring used to fill over
    /// exactly this distance, so the gesture had no resistance in it at all:
    /// the moment the `+` looked finished, it was finished, and every argument
    /// above about deliberate strokes was being made by a mark that had not
    /// finished drawing. The `+` now closes in the first third
    /// (`spaceCreateRingTravel`) and the remaining 240 pt are the asking price
    /// — the same distance, spent on the part of the gesture that is a
    /// decision rather than on the part that is an animation.
    ///
    /// **It is not longer than that**, however much more resistance it is
    /// tempting to ask for: `TokenCheck` holds `spaceCreateTravel` under what
    /// one trackpad stroke can deliver at `spaceSwipeSpeed`, and resistance
    /// that cannot be overcome in one gesture is not resistance, it is a dead
    /// end.
    static let spaceCreateTravel: CGFloat = 360

    /// How far into that stroke §30.9's ring is **already closed**.
    ///
    /// **A third of the way, which lands on exactly one `spaceSwipeTravel`.**
    /// The `+` used to finish drawing itself at the same instant the gesture
    /// committed, and a progress ring that completes on the last frame is not
    /// a read-out — it is a receipt. Closed early, it becomes the thing it was
    /// meant to be: *this is what you are about to make*, said while there is
    /// still two thirds of a stroke in which to decide against it. The rest of
    /// the travel is then read as the new Space pushing the old column out of
    /// the way, which is the other half of what the gesture is doing.
    ///
    /// That the number lands on one Space's worth of travel is the reason to
    /// trust it: the `+` is fully drawn by the time the hand has gone one Space
    /// past the last one, and everything after that is the asking price.
    static let spaceCreateRingTravel = spaceCreateTravel / 3

    /// §30.9's ring, drawn **around** the sidebar's `+` disc.
    ///
    /// **There is one of these now, and it used to be two.** A 14 pt copy also
    /// stood in the §3.5 strip, on the reasoning that one affordance at two
    /// sizes is one thing to learn. In the hand it was the opposite: the strip
    /// is a read-out of *which Space*, and a `+` in it is an answer to a
    /// different question sitting in the middle of that answer — so the strip
    /// is dots and only dots, and the gesture is read where the gesture is
    /// happening.
    ///
    /// 46 against a 34 pt disc leaves 6 pt of clear sidebar between the glass
    /// and the ring. Drawn *outside* rather than on the disc's own edge for
    /// `SpaceSwatchChip`'s reason: a ring painted over the edge of a glass
    /// button takes a bite out of the button.
    static let spaceCreateRing: CGFloat = 46

    /// The ring's stroke.
    ///
    /// A ring reads by its weight **against its own diameter**, not by its
    /// width in points: at the 1.5 pt the 14 pt strip mark was drawn with, a
    /// ring this size was a hairline round a glass button — too thin to read
    /// how full it was, which is the only thing it says. This is the same
    /// tenth of a diameter at the size it is actually drawn.
    static let spaceCreateRingLine: CGFloat = 4

    /// The ring a chosen §6.2 swatch wears (`SpaceSwatchChip`).
    ///
    /// Its own number, and it borrowed `spaceCreateRingLine` for one build —
    /// which is how thickening a gesture's progress ring would have gone on to
    /// resize a grid of colours. They are the same size today and they answer
    /// to nothing in common: this is a selection mark on a 28 pt disc, that is
    /// a read-out on a 46 pt one.
    ///
    /// The disc inside is inset by **twice** it, so the ring is drawn outside
    /// the colour with a stroke's worth of air between the two — a border
    /// painted over the edge of the disc takes a tenth of the colour away, and
    /// that tenth is the darkest part of the ramp.
    static let spaceSwatchRing: CGFloat = 1.5

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
