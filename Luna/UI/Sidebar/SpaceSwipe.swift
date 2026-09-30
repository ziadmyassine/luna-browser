//
//  SpaceSwipe.swift
//  Luna
//
//  §30.9 / SPACES-SPEC D-S12's two-finger sidebar swipe: slide sideways
//  anywhere on the sidebar to change Space, and keep sliding past the last one
//  to make a new one. This file is the arithmetic, pure and asserted by
//  `SpaceSwipeTests`; `SpaceSwipeController.swift` is the wiring, which needs
//  a trackpad's events to test.
//
//  The page is the ruler: one page of hand is one page of column, at whatever
//  width the §3.7 handle has left the sidebar (`Metric.spaceSwipeSpeed`). One
//  Space per gesture, however hard the flick; a release still moving turns the
//  page however far it got (`Metric.spaceFlickSpeed`), since half a column is
//  too much finger for a reflex. The ring is the threshold, not a promise, and
//  nothing is decided until `.ended`, so an overshoot is always recoverable.
//

import AppKit
import BrowserKit

/// Where a swipe has got to, and what letting go now would do.
struct SpaceSwipe: Equatable {

    /// The indicator's position relative to the active Space, in Spaces: −1 is
    /// the previous one, +1 the next, and it never leaves that range. Where
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
    ///   - offset: finger travel in points, positive toward the next Space.
    ///     `SpaceSwipeController` flips `scrollingDeltaX` into this convention;
    ///     see `accumulate`.
    ///   - speed: how fast the hand was moving, in points per second, signed
    ///     the same way. Only a release has a meaningful one — see `flicked`.
    ///   - span: the page's own width. The ruler, and the reason there is
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

        // Still moving when the fingers left. Three conditions, and all
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

        // Forward, with a Space to go to. Capped at one page: uncapped, a firm
        // swipe from the first of two Spaces reached the second and carried on
        // into the create zone past it.
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
        // The ring is the threshold: full means a release makes a Space, and
        // it is the only thing that does.
        //
        // The column resists rather than travelling. There is nowhere for it
        // to go, so `spaceCreateGive` bends its travel over — 1:1 under the
        // fingers at first and stiffer the further it is pushed, so the last
        // third of the ring is paid against a column that has all but stopped.
        // `tanh` for `damped`'s reason: a stop with a corner on it is a place
        // the hand sits and chatters.
        let give = Tokens.Metric.spaceCreateGive
        let creation = min(reach / Tokens.Metric.spaceCreateReach, 1)
        return SpaceSwipe(
            travel: give * CGFloat(tanh(Double(reach / give))),
            creation: creation,
            landing: nil,
            createsSpace: creation >= 1
        )
    }

    /// Nothing happening — the resting read-out, and what a gesture in a window
    /// with no Spaces resolves to.
    static let rest = SpaceSwipe(travel: 0, creation: 0, landing: nil, createsSpace: false)
}
