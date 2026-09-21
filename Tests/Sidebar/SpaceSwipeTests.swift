//
//  SpaceSwipeTests.swift
//  LunaTests
//
//  §30.9's two-finger swipe, as arithmetic — split out of `SpacesTests.swift`,
//  which holds the other half: where the dots go.
//
//  Three things are asserted here that a trackpad would otherwise be the only
//  way to find out. **That the page is the ruler**: one page of hand is one
//  page of column at every width the §3.7 handle reaches, which is the claim
//  the "it multiplies my swipe" defect was the absence of. **What a gesture
//  means**: the half-a-page commit, the flick that commits without it, the cap
//  that keeps one swipe to one Space, and the page past the last one that makes
//  a new one. And **how much of the gesture is the hand's** — macOS scales a
//  precise scroll by how fast the fingers moved, so the deltas an event carries
//  are not a distance, and everything above is arithmetic on a number that has
//  already been multiplied unless something takes the multiplier back off. What
//  is asserted about that is the *shape* of the curve rather than one number on
//  it: it answers the hand everywhere, it never outruns the hand, it never
//  exceeds the ceiling, and it leaves a slow drag alone. A hard clip passes
//  three of those four and fails the first, which is exactly how it felt.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

/// §30.9's two-finger swipe, as arithmetic. The gesture itself needs a
/// trackpad; what it *means* does not.
@MainActor
final class SpaceSwipeTests: XCTestCase {

    /// One page — the sidebar as it ships. Every distance below is a fraction
    /// of this and of nothing else, which is the point.
    private let page = Tokens.Metric.sidebarWidth.default
    /// A release fast enough to be a flick, and one that is not.
    private var fast: CGFloat { Tokens.Metric.spaceFlickSpeed * 1.5 }
    private var slow: CGFloat { Tokens.Metric.spaceFlickSpeed * 0.5 }

    // MARK: - The page is the ruler

    /// **The reported defect, stated as arithmetic: "a little swipe is too big
    /// a move".** The column used to be measured against a constant — 120 pt —
    /// while the thing it moved was a 280 pt page, so every point of finger
    /// bought two and a third points of column. The page now goes exactly as
    /// far as the hand does, at every width the handle reaches.
    func testOnePageOfHandIsOnePageOfColumn() {
        for span in [Tokens.Metric.sidebarWidth.min, page, Tokens.Metric.sidebarWidth.max] {
            for fraction in [0.1, 0.25, 0.5, 0.9] as [CGFloat] {
                XCTAssertEqual(
                    Self.resolve(span * fraction, span: span, active: 0, of: 3).travel,
                    fraction,
                    accuracy: 0.001,
                    "\(fraction) of a \(span) pt page"
                )
            }
        }
    }

    /// The same claim backwards. Every direction with a Space in it is 1:1.
    func testTheRulerDoesNotChangeWithDirection() {
        XCTAssertEqual(Self.resolve(-page / 2, active: 1, of: 3).travel, -0.5, accuracy: 0.001)
        XCTAssertEqual(Self.resolve(page / 2, active: 1, of: 3).travel, 0.5, accuracy: 0.001)
    }

    /// **Past the last Space it changes gear, and that is the resistance
    /// asked for.** There is nowhere for the column to go out there, so it is
    /// held against a stop instead of carried to one: the same half page of
    /// hand that moves a whole half page of column between two Spaces moves
    /// visibly less of one past the last, and every further point of push
    /// moves it less than the point before.
    func testTheCreateZoneResistsTheHandInsteadOfCarryingIt() {
        var previous: CGFloat = 0
        for fraction in stride(from: 0.1, through: 2.0, by: 0.1) {
            let held = Self.resolve(page * CGFloat(fraction), active: 2, of: 3).travel
            let carried = min(CGFloat(fraction), 1)
            XCTAssertLessThan(held, carried, "\(fraction) of a page was not resisted")
            XCTAssertGreaterThan(held, previous, "the column stopped answering the hand at \(fraction)")
            XCTAssertLessThan(held, Tokens.Metric.spaceCreateGive, "the column passed its own stop")
            previous = held
        }
        // …and it starts out following the hand, so crossing into the zone is
        // one movement rather than a gear change the fingers can feel.
        XCTAssertEqual(Self.resolve(page * 0.05, active: 2, of: 3).travel, 0.05, accuracy: 0.005)
    }

    // MARK: - What a gesture means

    /// Half a page commits, and under half of it does not. This is the whole of
    /// "I changed my mind half way".
    func testHalfAPageLandsOnTheNextSpaceAndLessThanHalfDoesNot() {
        XCTAssertEqual(Self.resolve(page * 0.6, active: 0, of: 3).landing, 1)
        XCTAssertEqual(Self.resolve(-page * 0.6, active: 1, of: 3).landing, 0)
        XCTAssertNil(Self.resolve(page * 0.4, active: 1, of: 3).landing)
        XCTAssertNil(Self.resolve(-page * 0.4, active: 1, of: 3).landing)
    }

    /// **"One single fast swipe should also go to the next Space."** Half a
    /// page is 140 pt of finger, which is far more than a reflex performed
    /// dozens of times a day can cost — so a release that is still moving turns
    /// the page however far it got. This is what pays for the ruler being a
    /// whole page wide.
    func testAFlickTurnsThePageWithoutTheDistance() {
        let flick = Self.resolve(page * 0.15, speed: fast, active: 0, of: 3)
        XCTAssertEqual(flick.landing, 1)
        XCTAssertEqual(Self.resolve(-page * 0.15, speed: -fast, active: 1, of: 3).landing, 0)
        // …and the same travel, let go gently, is a look.
        XCTAssertNil(Self.resolve(page * 0.15, speed: slow, active: 0, of: 3).landing)
    }

    /// **A hand that reversed before it lifted changed its mind.** Speed alone
    /// is not intent; speed in the direction the page is going is.
    func testAFlickBackTheOtherWayCommitsNothing() {
        XCTAssertNil(Self.resolve(page * 0.2, speed: -fast, active: 0, of: 3).landing)
        XCTAssertNil(Self.resolve(-page * 0.2, speed: fast, active: 1, of: 3).landing)
    }

    /// A flick still has to be a swipe. Two fingers landing with a little
    /// sideways momentum can report one fast event and nothing else.
    func testATwitchIsNotAFlick() {
        let twitch = Tokens.Metric.spaceFlickReach / 2
        XCTAssertNil(Self.resolve(page * twitch, speed: fast * 10, active: 0, of: 3).landing)
    }

    /// **The bug the cap exists for.** A trackpad flick is accelerated by the
    /// system and routinely delivers several hundred points in one stroke, so
    /// before the travel was capped a single firm swipe from the first of two
    /// Spaces ran through the second and into the create zone — the gesture you
    /// use to *change* Space made one instead. Whatever the stroke, a swipe
    /// forward from a Space that has a Space after it lands on that Space.
    func testAHardSwipeLandsOnTheNextSpaceRatherThanMakingOne() {
        for stroke in [page, page * 4, page * 40] {
            let swipe = Self.resolve(stroke, speed: fast, active: 0, of: 2)
            XCTAssertEqual(swipe.landing, 1, "a \(stroke) pt stroke")
            XCTAssertFalse(swipe.createsSpace, "a \(stroke) pt stroke made a Space")
            XCTAssertEqual(swipe.creation, 0, "a \(stroke) pt stroke opened the ring")
            XCTAssertLessThanOrEqual(swipe.travel, 1, "a \(stroke) pt stroke ran past the next Space")
        }
    }

    /// The same cap backwards, and it is what keeps the indicator on the strip:
    /// one Space per gesture, in either direction.
    func testAHardSwipeBackLandsOnThePreviousSpaceAndNoFurther() {
        let swipe = Self.resolve(-page * 40, active: 2, of: 3)
        XCTAssertEqual(swipe.landing, 1)
        XCTAssertEqual(swipe.travel, -1)
    }

    /// **The create zone is only reachable from the last Space**, which is the
    /// whole of why the cap is safe: there is nowhere else "further" could
    /// possibly mean anything but "the one after this".
    func testOnlyTheLastSpaceCanReachTheCreateZone() {
        for active in 0..<3 {
            let swipe = Self.resolve(page * 10, active: active, of: 3)
            XCTAssertEqual(swipe.createsSpace, active == 2, "Space \(active) of 3")
        }
    }

    /// **The leading end simply stops.** There is nothing before the first
    /// Space, so the indicator does not move and nothing is offered — not even
    /// to a flick.
    func testTheFirstSpaceHasNothingBehindIt() {
        let swipe = Self.resolve(-page * 3, speed: -fast, active: 0, of: 3)
        XCTAssertEqual(swipe.travel, 0)
        XCTAssertNil(swipe.landing)
        XCTAssertEqual(swipe.creation, 0)
        XCTAssertFalse(swipe.createsSpace)
    }

    /// Past the last Space there is no Space to land on — the gesture has
    /// stopped being a switch.
    func testPastTheLastSpaceThereIsNoLanding() {
        let swipe = Self.resolve(page * 0.5, active: 2, of: 3)
        XCTAssertNil(swipe.landing)
        XCTAssertGreaterThan(swipe.creation, 0)
    }

    /// The `+`'s slot is the only place past the last Space, so the indicator
    /// reaches it and stops there rather than running off the strip.
    func testTheIndicatorNeverLeavesTheStrip() {
        for active in 0..<3 {
            for stroke in [-page * 40, page * 40] {
                let swipe = Self.resolve(stroke, active: active, of: 3)
                XCTAssertGreaterThanOrEqual(swipe.travel, -1, "Space \(active), \(stroke) pt")
                XCTAssertLessThanOrEqual(swipe.travel, 1, "Space \(active), \(stroke) pt")
            }
        }
    }

    // MARK: - Making one

    /// **The reported defect: "I cannot create a new Space anymore."** It used
    /// to take three pages of travel, which against the damping ceiling needs
    /// almost a quarter of a second of unbroken, saturated movement — so the
    /// ring closed, because that only cost a third of it, and the release made
    /// nothing. Every time. A whole page, pushed out and let go of, makes one.
    func testAPagePushedOutAndReleasedMakesASpace() {
        let swipe = Self.resolve(page, speed: slow, active: 1, of: 2)
        XCTAssertTrue(swipe.createsSpace)
        XCTAssertEqual(swipe.creation, 1, accuracy: 0.001)
        // The column is held, not gone: the rest of that journey belongs to
        // the release, which makes it in one movement.
        XCTAssertLessThan(swipe.travel, Tokens.Metric.spaceCreateGive)
    }

    /// …and a page that is nearly all the way out is still not a Space.
    func testShortOfAWholePageMakesNothing() {
        XCTAssertFalse(Self.resolve(page * 0.99, speed: slow, active: 0, of: 1).createsSpace)
    }

    /// **A closed ring is a made Space, and nothing else is.** The ring used
    /// to finish drawing a third of the way in and the gesture to commit at the
    /// end of the page, on the reasoning that a progress ring should promise
    /// rather than receipt — which is true of a ring that is promising
    /// something. A user who did what it said (push until the circle closes,
    /// let go) got nothing, exactly as they had before the create distance came
    /// down at all. There is one distance now and the ring is drawn against it.
    func testTheRingIsFullExactlyWhenALetGoWouldMakeASpace() {
        for fraction in stride(from: 0.1, through: 3.0, by: 0.1) {
            let swipe = Self.resolve(page * CGFloat(fraction), speed: slow, active: 0, of: 1)
            XCTAssertEqual(
                swipe.createsSpace, swipe.creation >= 1,
                "at \(fraction) of a page the ring and the release disagreed"
            )
        }
        XCTAssertLessThan(Self.resolve(page * 0.99, active: 0, of: 1).creation, 1)
        XCTAssertEqual(Self.resolve(page, active: 0, of: 1).creation, 1, accuracy: 0.001)
    }

    /// **However the hand left.** A flick past the last Space used to make
    /// nothing however far it went, which is a defensible rule about intent and
    /// an indefensible one about a read-out: it made a closed circle mean
    /// nothing in some releases, which is the same lie as a circle that closes
    /// early. The distance is what tells a reflex from a decision now, and a
    /// reflex does not cover a page.
    func testTheRingDecidesRatherThanTheSpeedTheFingersLeftAt() {
        for speed in [0, slow, fast, fast * 10, -fast] {
            XCTAssertTrue(
                Self.resolve(page, speed: speed, active: 0, of: 1).createsSpace,
                "a closed ring let go of at \(speed) pt/s made nothing"
            )
            XCTAssertFalse(
                Self.resolve(page * 0.9, speed: speed, active: 0, of: 1).createsSpace,
                "an open ring let go of at \(speed) pt/s made a Space"
            )
        }
    }

    /// **"If the user then pans back then it shouldn't."** The ring empties
    /// under the hand on the way out again, so calling a create off is the same
    /// movement that started it, run backwards, and it is watched the whole
    /// way. Nothing latches.
    func testPanningBackEmptiesTheRingAndCallsTheCreateOff() {
        let closed = Self.resolve(page * 1.5, speed: slow, active: 0, of: 1)
        XCTAssertTrue(closed.createsSpace)
        let backOff = Self.resolve(page * 0.7, speed: slow, active: 0, of: 1)
        XCTAssertFalse(backOff.createsSpace)
        XCTAssertEqual(backOff.creation, 0.7, accuracy: 0.001)
        // …all the way back to the Space it started from.
        XCTAssertEqual(Self.resolve(0, active: 0, of: 1), .rest)
    }

    /// The ring never over-fills, however far the fingers go.
    func testTheRingStopsAtAFullCircle() {
        XCTAssertEqual(Self.resolve(page * 4, active: 0, of: 1).creation, 1)
    }

    /// A gesture in a window with no Spaces — or in a column with no width yet
    /// — cannot mean anything, and must not crash trying.
    func testAnEmptyWindowOrAnUnlaidColumnResolvesToNothing() {
        XCTAssertNil(Self.resolve(page * 10, active: 0, of: 0).landing)
        XCTAssertFalse(Self.resolve(page * 10, active: 4, of: 2).createsSpace)
        XCTAssertEqual(SpaceSwipe.resolve(offset: 999, span: 0, activeIndex: 0, count: 2), .rest)
    }

    // MARK: - The acceleration, bent back off

    private static let frame = 1.0 / 60
    /// One frame's worth of honest hand, which is what the curve's knee is.
    private static var knee: CGFloat { Tokens.Metric.spaceSwipeSpeed * CGFloat(frame) }

    /// **The multiplier the trackpad itself adds.** macOS scales the delta by
    /// how fast the fingers moved, so a flick arrives as several times the
    /// travel the hand actually covered — and now that the page is pinned to
    /// the hand 1:1, an undamped delta would put the column three pages from
    /// the fingers pushing it. Four times a hand's worth of movement in one
    /// frame comes back as about a hand's.
    func testAnAcceleratedFlickIsFoldedBackTowardWhatAHandCanCover() {
        let folded = SpaceSwipeController.damped(Self.knee * 4, since: 1, at: 1 + Self.frame)
        XCTAssertLessThan(folded, Self.knee)
        XCTAssertGreaterThan(folded, Self.knee * 0.9)
        XCTAssertEqual(SpaceSwipeController.damped(-Self.knee * 4, since: 1, at: 1 + Self.frame), -folded)
    }

    /// However hard the flick, and whichever way.
    func testNoEventEverCarriesMoreThanTheCeiling() {
        for delta in [Self.knee * 2, Self.knee * 40, Self.knee * 4000] {
            XCTAssertLessThan(SpaceSwipeController.damped(delta, since: 1, at: 1 + Self.frame), Self.knee)
            XCTAssertGreaterThan(SpaceSwipeController.damped(-delta, since: 1, at: 1 + Self.frame), -Self.knee)
        }
    }

    /// …and a deliberate drag passes through as itself, which is the whole
    /// reason this is a ceiling and not a gain. A slow drag is barely
    /// accelerated to begin with, so scaling it down would only make the one
    /// gesture that was already honest feel sticky.
    func testADeliberateDragIsAllButUntouched() {
        for delta in [Self.knee / 20, Self.knee / 8, -Self.knee / 8] {
            let damped = SpaceSwipeController.damped(delta, since: 1, at: 1 + Self.frame)
            XCTAssertEqual(damped, delta, accuracy: abs(delta) * 0.03, "\(delta) pt lost more than 3 %")
        }
    }

    /// **The bug the curve exists for, stated as arithmetic.** This was a hard
    /// clip for one build, which is a worse gesture than no damping at all: a
    /// ceiling low enough to catch a flick catches every event of an ordinary
    /// swipe too, so every frame comes back as *exactly* the ceiling and the
    /// page travels at one fixed speed whatever the hand is doing. A curve that
    /// is still answering the hand keeps rising all the way up, and it never
    /// rises faster than the hand did — which is the pair of claims that rules
    /// out both a clip and a gain.
    func testTheResponseKeepsAnsweringTheHandAndNeverOutrunsIt() {
        var previous: CGFloat = 0
        for step in 1...200 {
            let delta = Self.knee * CGFloat(step) / 20
            let damped = SpaceSwipeController.damped(delta, since: 1, at: 1 + Self.frame)
            XCTAssertGreaterThan(damped, previous, "the curve stopped answering at \(delta) pt")
            XCTAssertLessThanOrEqual(damped, delta, "the curve outran the hand at \(delta) pt")
            previous = damped
        }
    }

    /// **The ceiling is a speed, so it means the same thing on a 120 Hz panel
    /// as on a 60 Hz one.** Twice the events, half the budget each, and the
    /// same total travel for the same hand.
    func testTheCeilingIsASpeedRatherThanAnAmountPerEvent() {
        let sixty = SpaceSwipeController.damped(10_000, since: 1, at: 1 + Self.frame)
        let twenty = SpaceSwipeController.damped(10_000, since: 1, at: 1 + 1.0 / 120)
        XCTAssertEqual(sixty, twenty * 2, accuracy: 0.001)
    }

    /// The first event of a gesture has nothing to measure from, and a frame
    /// the app spent elsewhere must not hand one event the budget of ten. The
    /// distance and the speed read it from the same place, or a speed measured
    /// over one interval would be divided out of a distance measured over
    /// another.
    func testAGapWithNothingBehindItIsReadAsOneFrame() {
        let frame = SpaceSwipeController.damped(1000, since: 1, at: 1 + Self.frame)
        XCTAssertEqual(SpaceSwipeController.damped(1000, since: 0, at: 99), frame, accuracy: 0.001)
        XCTAssertEqual(SpaceSwipeController.damped(1000, since: 1, at: 2), frame, accuracy: 0.001)
        XCTAssertEqual(SpaceSwipeController.interval(since: 0, at: 99), Self.frame, accuracy: 0.0001)
        XCTAssertEqual(SpaceSwipeController.interval(since: 1, at: 2), Self.frame, accuracy: 0.0001)
    }

    /// **The create gesture has to be completable in one stroke, at the widest
    /// the column gets.** This is the claim that was false in the shipped
    /// build: three pages against the ceiling needed longer than a trackpad
    /// stroke lasts, so the one gesture the resistance is *for* could not be
    /// performed at all. One deliberate push now clears a page even against a
    /// sidebar dragged out to its maximum — and this is the worst case twice
    /// over, because the stroke is simulated at the damping ceiling, which a
    /// deliberate push never reaches.
    func testAStrokeCoversAWholePageAtTheWidestTheColumnGets() {
        let stroke = 0.3
        var offset: CGFloat = 0
        var last = 1.0
        // A flick the system has already multiplied, at 120 Hz, for 0.2 s.
        for step in 1...Int(stroke * 120) {
            let now = 1 + Double(step) / 120
            offset += SpaceSwipeController.damped(60, since: last, at: now)
            last = now
        }
        let widest = Tokens.Metric.sidebarWidth.max * Tokens.Metric.spaceCreateReach
        XCTAssertGreaterThan(offset, widest, "a 0.2 s stroke cannot push a \(widest) pt page out")
    }

    // MARK: - Helpers

    private static func resolve(
        _ offset: CGFloat,
        speed: CGFloat = 0,
        span: CGFloat = Tokens.Metric.sidebarWidth.default,
        active: Int,
        of count: Int
    ) -> SpaceSwipe {
        SpaceSwipe.resolve(offset: offset, speed: speed, span: span, activeIndex: active, count: count)
    }
}
