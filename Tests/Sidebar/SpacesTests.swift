//
//  SpacesTests.swift
//  LunaTests
//
//  The two pieces of §3.5/§30.9 arithmetic that are worth more than a
//  screenshot: where the Space dots go, and what a two-finger swipe means.
//
//  **The dot row is here because it shipped crooked.** The strip used to size
//  each dot's slot with `.integral`, which rounds a slot's leading edge down
//  and its trailing edge up, independently of its neighbours — so three dots in
//  a 56 pt pill drew with gaps of 18 and 19 pt and the run sat off centre. That
//  is not a bug a test can catch by asserting a number someone typed; it is
//  caught by asserting the *property* the layout is supposed to have, at every
//  count, which is what `evenlySpaced` does below.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpaceDotsLayoutTests: XCTestCase {

    /// **The reported defect, at the count it was reported at.** Three Spaces
    /// is the pill's resting size and the most common window there is.
    func testThreeDotsAreEvenlySpacedInTheRestingPill() {
        let centres = SpaceDotsView.centres(count: 3, in: Tokens.Metric.spaceDotsPill.width)
        XCTAssertEqual(centres.count, 3)
        XCTAssertEqual(centres[1] - centres[0], centres[2] - centres[1], "the two gaps differ")
    }

    /// Every count the pill is ever asked to hold, against the width it holds
    /// it at. Three claims, and the old layout failed all three at some count:
    /// the gaps are equal, the two end margins are equal, and every centre is a
    /// whole point — a dot on a half point is a dot drawn over two pixels.
    func testEveryCountIsEvenlySpacedSymmetricAndOnWholePoints() {
        for count in 1...8 {
            let width = Self.pillWidth(for: count)
            let centres = SpaceDotsView.centres(count: count, in: width)
            XCTAssertEqual(centres.count, count)
            for centre in centres {
                XCTAssertEqual(centre, centre.rounded(), "a dot at \(centre) with \(count) Spaces is off the grid")
            }
            guard let first = centres.first, let last = centres.last else { return XCTFail("no dots") }
            XCTAssertEqual(first, width - last, accuracy: 0.001, "the run is off centre with \(count) Spaces")
            let gaps = Set(zip(centres, centres.dropFirst()).map { $1 - $0 })
            XCTAssertLessThanOrEqual(gaps.count, 1, "gaps \(gaps.sorted()) with \(count) Spaces")
        }
    }

    /// One Space is one dot in the middle of the pill, not one dot at the head
    /// of a row that happens to have nothing after it.
    func testASingleDotIsCentred() {
        let width = Tokens.Metric.spaceDotsPill.width
        XCTAssertEqual(SpaceDotsView.centres(count: 1, in: width), [width / 2])
    }

    /// The dots have to stay inside the pill they are drawn in, mark and all.
    func testTheRunNeverOverflowsThePill() {
        for count in 1...8 {
            let width = Self.pillWidth(for: count)
            let radius = Tokens.Metric.spaceDot / 2
            let centres = SpaceDotsView.centres(count: count, in: width)
            XCTAssertGreaterThanOrEqual(centres.first ?? 0, radius, "\(count) Spaces overflow the leading edge")
            XCTAssertLessThanOrEqual(centres.last ?? 0, width - radius, "\(count) Spaces overflow the trailing edge")
        }
    }

    // MARK: - The laid-out strip

    /// **§6.6's drop targets abut; they do not overlap.** Each dot owns the
    /// slot from half way to its neighbour, so "which Space does this tab land
    /// in" is never decided by which of two frames `first(where:)` reached
    /// first — which is what the old, independently rounded slots left to
    /// chance at every seam.
    func testTheSlotsAbutAndCoverThePill() {
        let strip = Self.strip(spaces: 4)
        let dots = strip.subviews.compactMap { $0 as? SpaceDotView }
        XCTAssertEqual(dots.count, 4)
        XCTAssertEqual(dots.first?.frame.minX, 0)
        XCTAssertEqual(dots.last?.frame.maxX, strip.bounds.width)
        for (left, right) in zip(dots, dots.dropFirst()) {
            XCTAssertEqual(left.frame.maxX, right.frame.minX, "slots overlap or leave a gap between them")
        }
    }

    /// The mark is drawn where the strip's arithmetic says, not where its own
    /// slot's middle happens to be — the first and last slots run out to the
    /// pill's edges and are not symmetric about their dot.
    func testEachDotIsToldItsOwnCentreRatherThanGuessingFromItsSlot() {
        let strip = Self.strip(spaces: 5)
        let dots = strip.subviews.compactMap { $0 as? SpaceDotView }
        let centres = SpaceDotsView.centres(count: 5, in: strip.bounds.width)
        for (dot, centre) in zip(dots, centres) {
            XCTAssertEqual(dot.frame.minX + dot.markCentreX, centre, accuracy: 0.001)
        }
    }

    /// §30.9's `+` takes a slot of its own, so the pill makes room for it —
    /// otherwise the ring would have to be drawn over the last Space's dot,
    /// which is the one place it must not be.
    func testThePillMakesRoomForTheCreateRing() {
        let strip = Self.strip(spaces: 3)
        let resting = strip.intrinsicContentSize.width
        strip.creation = 0.5
        XCTAssertGreaterThan(strip.intrinsicContentSize.width, resting)
        strip.creation = 0
        XCTAssertEqual(strip.intrinsicContentSize.width, resting)
    }

    // MARK: - Bits

    /// What `SpaceDotsView.intrinsicContentSize` hands back for `count`.
    private static func pillWidth(for count: Int) -> CGFloat {
        let extra = max(count - SpaceDotsView.restingSpaceCount, 0)
        return Tokens.Metric.spaceDotsPill.width + CGFloat(extra) * Tokens.Metric.spaceDotsPillGrowth
    }

    private static func strip(spaces count: Int) -> SpaceDotsView {
        let spaces = (0..<count).map {
            Space(name: "Space \($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace, profileID: UUID())
        }
        let strip = SpaceDotsView()
        strip.show(spaces: spaces, activeSpaceID: spaces[0].id)
        strip.frame = NSRect(origin: .zero, size: strip.intrinsicContentSize)
        strip.layoutSubtreeIfNeeded()
        return strip
    }
}

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

    /// **The resistance, stated as the test that would fail if someone tidied
    /// the two thresholds into one.** A whole Space's worth of travel *past the
    /// last Space* — twice what it takes to switch one, and well past what a
    /// reflex flick delivers — still leaves the ring open.
    func testASpacesWorthOfOvershootDoesNotMakeASpace() {
        let swipe = Self.resolve(travel, active: 1, of: 2)
        XCTAssertLessThan(swipe.creation, 1)
        XCTAssertFalse(swipe.createsSpace)
        XCTAssertGreaterThan(swipe.creation, 0, "the ring is not even showing — the overshoot said nothing")
    }

    /// The ring closes at exactly `spaceCreateTravel` past the last Space, and
    /// not before.
    func testTheRingClosesAtTheCreateTravelAndNotBefore() {
        let create = Tokens.Metric.spaceCreateTravel
        XCTAssertFalse(Self.resolve(create * 0.99, active: 0, of: 1).createsSpace)
        XCTAssertTrue(Self.resolve(create, active: 0, of: 1).createsSpace)
        XCTAssertEqual(Self.resolve(create, active: 0, of: 1).creation, 1)
    }

    /// The ring never over-fills, however far the fingers go.
    func testTheRingStopsAtAFullCircle() {
        XCTAssertEqual(Self.resolve(Tokens.Metric.spaceCreateTravel * 4, active: 0, of: 1).creation, 1)
    }

    /// **One mark, one meaning**: the indicator arrives in the `+`'s slot at
    /// the moment the ring closes, rather than sitting on the last Space while
    /// something else fills up beside it.
    func testTheIndicatorReachesTheNewSlotExactlyAsTheRingCloses() {
        let last = 2
        let swipe = Self.resolve(Tokens.Metric.spaceCreateTravel, active: last, of: last + 1)
        XCTAssertEqual(swipe.travel, 1, accuracy: 0.001)
    }

    /// A gesture in a window with no Spaces cannot mean anything, and must not
    /// crash trying.
    func testAnEmptyOrOutOfRangeWindowResolvesToNothing() {
        XCTAssertNil(Self.resolve(travel * 10, active: 0, of: 0).landing)
        XCTAssertFalse(Self.resolve(travel * 10, active: 4, of: 2).createsSpace)
    }

    private static func resolve(_ offset: CGFloat, active: Int, of count: Int) -> SpaceSwipe {
        SpaceSwipe.resolve(offset: offset, activeIndex: active, count: count)
    }
}
