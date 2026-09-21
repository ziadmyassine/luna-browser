//
//  SpaceSwipe.swift
//  Luna
//
//  §30.9 / SPACES-SPEC D-S12's two-finger sidebar swipe: slide sideways
//  anywhere on the sidebar to change Space, and keep sliding past the last one
//  to make a new one.
//
//  **This file is the arithmetic; `SpaceSwipeController.swift` is the wiring.**
//  They were one file until it crossed SwiftLint's 400-line limit, and the seam
//  is the one the next paragraph already described.
//
//  **The arithmetic is a value type and the wiring is a controller**, because
//  the two fail for different reasons and only one of them can be tested
//  without a trackpad. `SpaceSwipe.resolve` is pure: given how far the fingers
//  have travelled, which Space is active and how many there are, it says where
//  the strip's indicator sits, how full the `+` ring is, and what letting go
//  would do. Every rule worth arguing about — the half-a-Space commit, the
//  clamp at the leading end, the doubled travel that makes a Space — is in
//  those twenty lines and is asserted by `SpaceSwipeTests`.
//
//  **The page is the ruler.** One page of hand is one page of column, at
//  whatever width the §3.7 handle has left the sidebar. There is no constant
//  for "one Space" any more and there should never have been one: every value
//  it took was a *fraction* of a page, so the column travelled a multiple of
//  the fingers pushing it — 120 pt against a 280 pt sidebar moved the page two
//  and a third points per point of hand. That is the multiplication the
//  gesture was reported for, twice, and damping the trackpad's acceleration
//  never touched it because the acceleration was not where it came from.
//
//  **One Space per gesture, however hard the flick.** The travel used to
//  accumulate without a ceiling, so a single firm swipe from the first of two
//  Spaces reached the second and then kept going into the create zone past it
//  — and the gesture the user performs to *change* Space made one instead. A
//  page swipe turns one page.
//
//  **The acceleration is taken off before any of that arithmetic runs**, which
//  is the other half of pinning the page to the hand: `scrollingDeltaX` is a
//  distance the system has already scaled by how fast the fingers moved, so a
//  page bound 1:1 to an undamped delta would sit three pages from the hand.
//  `damped(_:since:at:)` bends the top off how much page one event may carry
//  per second of hand, which leaves a deliberate drag as itself and folds the
//  multiplier off a flick.
//
//  **It bends rather than cutting**, and that distinction is the difference
//  between a gesture that is followed and one that is played back at you: a
//  hard ceiling low enough to catch a flick catches *every* event of an
//  ordinary swipe too, and a page whose every frame is the ceiling travels at
//  one fixed speed regardless of the hand. See `damped(_:since:at:)`.
//
//  **Distance is not the only way to commit, and that is what makes a page a
//  page wide affordable.** Half of a 280 pt column is 140 pt of finger, which
//  is far too much to ask of a reflex — so a release that is *still moving*
//  turns the page however far it got (`Metric.spaceFlickSpeed`). A short
//  stroke that is still going is a page turn; a long one that has come to rest
//  is a page turn; a short one that has come to rest is a look, and it springs
//  back. That is the whole of "a little swipe should do a little, and one fast
//  swipe should still change Space".
//
//  **A flick is never a create.** Past the last Space the same two fingers make
//  a new one, and the resistance that keeps that from happening by accident is
//  *how the gesture ended*, not how far it went. This used to be three pages of
//  distance and could not be performed at all: 360 pt against the damping
//  ceiling needs a quarter of a second of unbroken, saturated movement, and an
//  ordinary swipe lasts a sixth — so the ring closed, which only costs a third
//  of that, and the release made nothing. Every time. It is one page now, and
//  what stops a flick off the end from making a Space is that a flick, by
//  definition, has not come to rest.
//
//  **The ring is not the threshold; it is the promise.** It closes a third of
//  the way in (`Metric.spaceCreateRingReach`), which is where the `+` stops
//  being a thing appearing and becomes a thing about to happen — and the two
//  thirds after it are the asking price, watched with the answer already drawn.
//
//  **Nothing is decided while the fingers are down.** `.changed` only moves the
//  read-out; the switch and the create both happen on `.ended`. A gesture that
//  committed as it crossed a threshold would make an overshoot unrecoverable,
//  and the whole point of the ring is that you can see what you are about to
//  get while you can still not get it.
//

import AppKit
import BrowserKit

/// Where a swipe has got to, and what letting go now would do.
struct SpaceSwipe: Equatable {

    /// The indicator's position relative to the active Space, in Spaces: −1 is
    /// the previous one, +1 the next, and **it never leaves that range**. Where
    /// there is no next Space, +1 is the slot the `+` stands in instead.
    var travel: CGFloat
    /// 0…1 — how much of §30.9's ring is drawn. 1 is a closed circle.
    var creation: CGFloat
    /// The index a release would switch to, or nil for "stay where you are".
    var landing: Int?
    /// A release would make a new Space. Never true at the same time as
    /// `landing`: the fingers have left the Spaces that exist.
    var createsSpace: Bool

    /// - Parameters:
    ///   - offset: finger travel in points, **positive toward the next Space**.
    ///     `SpaceSwipeController` flips `scrollingDeltaX` into this convention;
    ///     see `accumulate`.
    ///   - speed: how fast the hand was moving, in points per second, signed
    ///     the same way. Only a *release* has a meaningful one — see `flicked`.
    ///   - span: the page's own width. **The ruler**, and the reason there is
    ///     no "points per Space" token: see the file header.
    ///   - activeIndex: the Space the window is in.
    ///   - count: how many there are.
    static func resolve(
        offset: CGFloat,
        speed: CGFloat = 0,
        span: CGFloat,
        activeIndex: Int,
        count: Int
    ) -> SpaceSwipe {
        guard count > 0, activeIndex >= 0, activeIndex < count, span > 0 else { return .rest }
        let reach = offset / span

        // **Still moving when the fingers left.** Three conditions, and all
        // three are the same claim from different sides: it was fast, it was
        // going the way the page is going — a hand that reversed before lifting
        // changed its mind — and it was a swipe rather than a twitch.
        let flicked = abs(speed) >= Tokens.Metric.spaceFlickSpeed
            && speed * offset > 0
            && abs(reach) >= Tokens.Metric.spaceFlickReach

        guard offset > 0 else {
            // Backward, and the first Space simply stops: a rubber band here
            // would be motion that means nothing, which is worse than none.
            guard activeIndex > 0 else { return .rest }
            let travel = max(reach, -1)
            return SpaceSwipe(
                travel: travel,
                creation: 0,
                landing: travel <= -0.5 || flicked ? activeIndex - 1 : nil,
                createsSpace: false
            )
        }

        // Forward, with a Space to go to. **Capped at one page**, so a hard
        // flick arrives at the next Space rather than sailing through it — see
        // the file header for what happened without this line.
        guard activeIndex == count - 1 else {
            let travel = min(reach, 1)
            return SpaceSwipe(
                travel: travel,
                creation: 0,
                landing: travel >= 0.5 || flicked ? activeIndex + 1 : nil,
                createsSpace: false
            )
        }

        // Forward from the last Space, where "further" has only one meaning.
        //
        // **The ring and the page are two different clocks**, and they used to
        // be one. The `+` closed at exactly the moment the gesture committed,
        // which made it a receipt rather than a read-out: by the time it told
        // you what you were about to get, you had it. The ring now fills over
        // the first third of the page and the column keeps travelling for the
        // other two, so the hand is told early and then has to mean it.
        //
        // **A flick makes nothing.** It is the only thing standing between a
        // reflex performed a hundred times a day and a Space nobody asked for,
        // and it is a better guard than distance ever was: distance punishes
        // the deliberate gesture as hard as the accidental one.
        let creation = min(reach / Tokens.Metric.spaceCreateRingReach, 1)
        let travel = min(reach / Tokens.Metric.spaceCreateReach, 1)
        return SpaceSwipe(
            travel: travel,
            creation: creation,
            landing: nil,
            createsSpace: travel >= 1 && !flicked
        )
    }

    /// Nothing happening — the resting read-out, and what a gesture in a window
    /// with no Spaces resolves to.
    static let rest = SpaceSwipe(travel: 0, creation: 0, landing: nil, createsSpace: false)
}
