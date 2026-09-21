//
//  SpaceSwipeTests.swift
//  LunaTests
//
//  §30.9's two-finger swipe, as arithmetic — split out of `SpacesTests.swift`,
//  which holds the other half: where the dots go.
//
//  Two things are asserted here that a trackpad would otherwise be the only
//  way to find out. **What a gesture means**: the half-a-Space commit, the cap
//  that keeps one swipe to one Space, and the doubled travel that makes a new
//  one. And **how much of the gesture is the hand's** — macOS scales a precise
//  scroll by how fast the fingers moved, so the deltas an event carries are not
//  a distance, and everything above is arithmetic on a number that has already
//  been multiplied unless something takes the multiplier back off.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

/// §30.9's two-finger swipe, as arithmetic. The gesture itself needs a
/// trackpad; what it *means* does not.
@MainActor
final class SpaceSwipeTests: XCTestCase {

    private let travel = Tokens.Metric.spaceSwipeTravel

    /// Half a Space commits — a flick is short, and a gesture that needed the
    /// whole distance would be a drag.
    func testHalfASpaceOfTravelLandsOnTheNextOne() {
        XCTAssertEqual(Self.resolve(travel * 0.6, active: 0, of: 3).landing, 1)
        XCTAssertEqual(Self.resolve(-travel * 0.6, active: 1, of: 3).landing, 0)
    }

    /// …and under half of it does not. This is the whole of "I changed my mind
    /// half way".
    func testLessThanHalfASpaceStaysWhereItIs() {
        XCTAssertNil(Self.resolve(travel * 0.4, active: 1, of: 3).landing)
        XCTAssertNil(Self.resolve(-travel * 0.4, active: 1, of: 3).landing)
    }

    /// **The bug this cap exists for.** A trackpad flick is accelerated by the
    /// system and routinely delivers several hundred points in one stroke, so
    /// before the travel was capped a single firm swipe from the first of two
    /// Spaces ran through the second and into the create zone — the gesture you
    /// use to *change* Space made one instead. Whatever the stroke, a swipe
    /// forward from a Space that has a Space after it lands on that Space.
    func testAHardSwipeLandsOnTheNextSpaceRatherThanMakingOne() {
        for stroke in [travel, travel * 4, travel * 40] {
            let swipe = Self.resolve(stroke, active: 0, of: 2)
            XCTAssertEqual(swipe.landing, 1, "a \(stroke) pt stroke")
            XCTAssertFalse(swipe.createsSpace, "a \(stroke) pt stroke made a Space")
            XCTAssertEqual(swipe.creation, 0, "a \(stroke) pt stroke opened the ring")
            XCTAssertLessThanOrEqual(swipe.travel, 1, "a \(stroke) pt stroke ran past the next Space")
        }
    }

    /// The same cap backwards, and it is what keeps the indicator on the strip:
    /// one Space per gesture, in either direction.
    func testAHardSwipeBackLandsOnThePreviousSpaceAndNoFurther() {
        let swipe = Self.resolve(-travel * 40, active: 2, of: 3)
        XCTAssertEqual(swipe.landing, 1)
        XCTAssertEqual(swipe.travel, -1)
    }

    /// **The create zone is only reachable from the last Space**, which is the
    /// whole of why the cap is safe: there is nowhere else "further" could
    /// possibly mean anything but "the one after this".
    func testOnlyTheLastSpaceCanReachTheCreateZone() {
        for active in 0..<3 {
            let swipe = Self.resolve(Tokens.Metric.spaceCreateTravel * 10, active: active, of: 3)
            XCTAssertEqual(swipe.createsSpace, active == 2, "Space \(active) of 3")
        }
    }

    /// **The leading end simply stops.** There is nothing before the first
    /// Space, so the indicator does not move and nothing is offered.
    func testTheFirstSpaceHasNothingBehindIt() {
        let swipe = Self.resolve(-travel * 3, active: 0, of: 3)
        XCTAssertEqual(swipe.travel, 0)
        XCTAssertNil(swipe.landing)
        XCTAssertEqual(swipe.creation, 0)
        XCTAssertFalse(swipe.createsSpace)
    }

    /// Past the last Space there is no Space to land on — the gesture has
    /// stopped being a switch.
    func testPastTheLastSpaceThereIsNoLanding() {
        let swipe = Self.resolve(travel * 1.5, active: 2, of: 3)
        XCTAssertNil(swipe.landing)
        XCTAssertGreaterThan(swipe.creation, 0)
    }

    /// The `+`'s slot is the only place past the last Space, so the indicator
    /// reaches it and stops there rather than running off the strip.
    func testTheIndicatorNeverLeavesTheStrip() {
        for active in 0..<3 {
            for stroke in [-travel * 40, travel * 40] {
                let swipe = Self.resolve(stroke, active: active, of: 3)
                XCTAssertGreaterThanOrEqual(swipe.travel, -1, "Space \(active), \(stroke) pt")
                XCTAssertLessThanOrEqual(swipe.travel, 1, "Space \(active), \(stroke) pt")
            }
        }
    }

    /// **The resistance, stated as the test that would fail if someone tidied
    /// the two thresholds into one.** A whole Space's worth of travel *past the
    /// last Space* — a third of what it takes to make one, and well past what a
    /// reflex flick delivers — closes the ring and makes nothing.
    func testASpacesWorthOfOvershootDoesNotMakeASpace() {
        let swipe = Self.resolve(travel, active: 1, of: 2)
        XCTAssertFalse(swipe.createsSpace)
        XCTAssertGreaterThan(swipe.creation, 0, "the ring is not even showing — the overshoot said nothing")
    }

    /// The ring closes at `spaceCreateRingTravel` — a third of the way — and
    /// not before.
    func testTheRingClosesAThirdOfTheWayAndNotBefore() {
        let ring = Tokens.Metric.spaceCreateRingTravel
        XCTAssertLessThan(Self.resolve(ring * 0.99, active: 0, of: 1).creation, 1)
        XCTAssertEqual(Self.resolve(ring, active: 0, of: 1).creation, 1, accuracy: 0.001)
        XCTAssertEqual(ring * 3, Tokens.Metric.spaceCreateTravel, accuracy: 0.001)
    }

    /// **A closed ring is not a made Space**, which is the whole of the
    /// resistance: two thirds of the stroke happen with the `+` already drawn,
    /// and letting go in any of them makes nothing.
    func testAClosedRingStillHasTwoThirdsOfTheStrokeToPayFor() {
        let create = Tokens.Metric.spaceCreateTravel
        XCTAssertEqual(Self.resolve(Tokens.Metric.spaceCreateRingTravel, active: 0, of: 1).creation, 1)
        XCTAssertFalse(Self.resolve(Tokens.Metric.spaceCreateRingTravel, active: 0, of: 1).createsSpace)
        XCTAssertFalse(Self.resolve(create * 0.99, active: 0, of: 1).createsSpace)
        XCTAssertTrue(Self.resolve(create, active: 0, of: 1).createsSpace)
    }

    /// The ring never over-fills, however far the fingers go.
    func testTheRingStopsAtAFullCircle() {
        XCTAssertEqual(Self.resolve(Tokens.Metric.spaceCreateTravel * 4, active: 0, of: 1).creation, 1)
    }

    /// **The page arrives as the gesture commits**, with the ring long since
    /// closed: the `+` finishes in the first third and the last two thirds are
    /// the new Space pushing the old column the rest of the way out.
    func testThePageArrivesAsTheGestureCommitsAndTheRingClosedLongBefore() {
        let third = Self.resolve(Tokens.Metric.spaceCreateRingTravel, active: 2, of: 3)
        XCTAssertEqual(third.creation, 1, accuracy: 0.001)
        XCTAssertEqual(third.travel, 1.0 / 3, accuracy: 0.001, "the page is a third of the way across")
        let swipe = Self.resolve(Tokens.Metric.spaceCreateTravel, active: 2, of: 3)
        XCTAssertEqual(swipe.travel, 1, accuracy: 0.001)
        XCTAssertEqual(swipe.creation, 1, accuracy: 0.001)
    }

    /// A gesture in a window with no Spaces cannot mean anything, and must not
    /// crash trying.
    func testAnEmptyOrOutOfRangeWindowResolvesToNothing() {
        XCTAssertNil(Self.resolve(travel * 10, active: 0, of: 0).landing)
        XCTAssertFalse(Self.resolve(travel * 10, active: 4, of: 2).createsSpace)
    }

    // MARK: - The acceleration, taken back off

    /// **The reported defect: "the scroll is like multiplied".** A trackpad
    /// does not report how far the fingers moved — macOS scales the delta by
    /// how fast they moved, so a flick arrives as several times the travel the
    /// hand actually covered and the page races out from under it. A frame
    /// carrying four times a hand's worth of movement is clipped to a hand's.
    func testAnAcceleratedFlickIsClippedToWhatAHandCanCover() {
        let frame = 1.0 / 60
        let honest = Tokens.Metric.spaceSwipeSpeed * CGFloat(frame)
        let clipped = SpaceSwipeController.damped(honest * 4, since: 1, at: 1 + frame)
        XCTAssertEqual(clipped, honest, accuracy: 0.001)
        XCTAssertEqual(SpaceSwipeController.damped(-honest * 4, since: 1, at: 1 + frame), -honest, accuracy: 0.001)
    }

    /// …and a deliberate drag passes through untouched, which is the whole
    /// reason this is a ceiling and not a gain. A slow drag is barely
    /// accelerated to begin with, so scaling it down would only make the one
    /// gesture that was already honest feel sticky.
    func testADeliberateDragIsNotDampedAtAll() {
        let frame = 1.0 / 60
        for delta in [CGFloat(1), 4, -6] {
            XCTAssertEqual(SpaceSwipeController.damped(delta, since: 1, at: 1 + frame), delta, accuracy: 0.001)
        }
    }

    /// **The ceiling is a speed, so it means the same thing on a 120 Hz panel
    /// as on a 60 Hz one.** Twice the events, half the budget each, and the
    /// same total travel for the same hand.
    func testTheCeilingIsASpeedRatherThanAnAmountPerEvent() {
        let sixty = SpaceSwipeController.damped(1000, since: 1, at: 1 + 1.0 / 60)
        let twenty = SpaceSwipeController.damped(1000, since: 1, at: 1 + 1.0 / 120)
        XCTAssertEqual(sixty, twenty * 2, accuracy: 0.001)
    }

    /// The first event of a gesture has nothing to measure from, and a frame
    /// the app spent elsewhere must not hand one event the budget of ten.
    func testAGapWithNothingBehindItIsReadAsOneFrame() {
        let frame = SpaceSwipeController.damped(1000, since: 1, at: 1 + 1.0 / 60)
        XCTAssertEqual(SpaceSwipeController.damped(1000, since: 0, at: 99), frame, accuracy: 0.001)
        XCTAssertEqual(SpaceSwipeController.damped(1000, since: 1, at: 2), frame, accuracy: 0.001)
    }

    private static func resolve(_ offset: CGFloat, active: Int, of count: Int) -> SpaceSwipe {
        SpaceSwipe.resolve(offset: offset, activeIndex: active, count: count)
    }
}
