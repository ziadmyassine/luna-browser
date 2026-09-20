//
//  SpacesTests.swift
//  LunaTests
//
//  The two pieces of §3.5/§30.9 arithmetic that are worth more than a
//  screenshot: where the Space dots go, and what a two-finger swipe means.
//
//  The swipe's own arithmetic is next door, in `SpaceSwipeTests.swift`.
//
//  **The dot row is here because it shipped crooked, and then because it
//  shipped loose.** The strip used to size each dot's slot with `.integral`,
//  which rounds a slot's leading edge down and its trailing edge up,
//  independently of its neighbours — so three dots in a 56 pt pill drew with
//  gaps of 18 and 19 pt and the run sat off centre. The slot was also the
//  pill's width divided by the count, so the *spacing* was a consequence of how
//  wide the pill happened to be: two Spaces stood 28 pt apart and eight stood
//  12 pt apart, in the same strip. Neither is a bug a test can catch by
//  asserting a number someone typed; both are caught by asserting the
//  *properties* the layout is supposed to have, at every count.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SpaceDotsLayoutTests: XCTestCase {

    /// **The reported defect, at the count it was reported at.** Three Spaces
    /// is the most common window there is.
    func testThreeDotsAreEvenlySpaced() {
        let centres = SpaceDotsView.centres(count: 3, in: Self.pillWidth(for: 3))
        XCTAssertEqual(centres.count, 3)
        XCTAssertEqual(centres[1] - centres[0], centres[2] - centres[1], "the two gaps differ")
    }

    /// **The second reported defect: the dots stood much too far apart** — and
    /// then, for one build, much too close.
    ///
    /// The gap is asserted as a *band* rather than as `spaceDotPitch` written
    /// out a second time, because a test that restates the token it is checking
    /// passes whatever the token becomes. What matters is the range in which a
    /// row of dots reads as one group of separate marks: under a dot's width
    /// apart they start to merge into a dashed line, and over two they stop
    /// being a row. The same claim holds at every count, which is the part the
    /// old width-divided-by-count arithmetic could not manage — it put two
    /// Spaces four diameters apart and eight Spaces one.
    func testTheGapBetweenTwoDotsReadsAsOneRowAtEveryCount() {
        let dot = Tokens.Metric.spaceDot
        for count in 2...8 {
            let centres = SpaceDotsView.centres(count: count, in: Self.pillWidth(for: count))
            XCTAssertEqual(centres.count, count, "\(count) Spaces")
            let gaps = Set(zip(centres, centres.dropFirst()).map { $1 - $0 - dot })
            XCTAssertEqual(gaps.count, 1, "gaps \(gaps.sorted()) differ with \(count) Spaces")
            guard let gap = gaps.first else { return XCTFail("no gaps with \(count) Spaces") }
            XCTAssertGreaterThanOrEqual(gap, dot, "\(count) Spaces are closer than a dot apart")
            XCTAssertLessThanOrEqual(gap, dot * 2, "\(count) Spaces are further than two dots apart")
        }
    }

    /// The pill is sized to its dots rather than the dots divided into the
    /// pill, so two Spaces do not sit in the middle of a pill built for three
    /// — **and it stops growing at the window**, which is the other half of the
    /// same rule: a strip whose width tracked the Space count had no ceiling,
    /// and twelve Spaces filled a footer that also holds two other clusters.
    func testThePillGrowsByAPitchUntilTheWindowIsFullAndThenStops() {
        let window = Tokens.Metric.spaceDotWindow
        var last = SpaceDotsView.width(forDots: 1)
        for count in 2...8 {
            let width = SpaceDotsView.width(forDots: count)
            let grown = count <= window ? Tokens.Metric.spaceDotPitch : 0
            XCTAssertEqual(width - last, grown, accuracy: 0.001, "\(count) Spaces")
            last = width
        }
    }

    /// **The window holds the indicator in the middle and stops at both
    /// ends**, so the Space you are in is always on the strip and the first and
    /// last never drift off their own pill.
    func testTheWindowKeepsTheIndicatorInItAndStopsAtBothEnds() {
        let window = Tokens.Metric.spaceDotWindow
        for count in 1...8 {
            for active in 0..<count {
                let start = SpaceDotsView.windowStart(indicator: CGFloat(active), count: count)
                XCTAssertGreaterThanOrEqual(start, 0, "\(active) of \(count)")
                XCTAssertLessThanOrEqual(start, CGFloat(max(count - window, 0)), "\(active) of \(count)")
                let position = CGFloat(active) - start
                XCTAssertGreaterThanOrEqual(position, 0, "Space \(active) of \(count) is off the leading end")
                XCTAssertLessThanOrEqual(position, CGFloat(window - 1), "Space \(active) of \(count) is off the end")
            }
        }
    }

    /// The window moves **with** the finger, not in steps: half a Space of
    /// swipe moves the run half a slot, so the strip scrolls at exactly the
    /// rate the column does.
    func testTheWindowSlidesContinuouslyRatherThanPaging() {
        let start = SpaceDotsView.windowStart(indicator: 3, count: 8)
        let half = SpaceDotsView.windowStart(indicator: 3.5, count: 8)
        XCTAssertEqual(half - start, 0.5, accuracy: 0.001)
    }

    /// Only the window's worth of dots is drawn, and the ones outside it are
    /// faded rather than snapped away — a mark cut in half by the pill's edge
    /// reads as a drawing bug.
    func testOnlyTheWindowIsInkedAndItsEdgeIsAFade() {
        let window = Tokens.Metric.spaceDotWindow
        let start = SpaceDotsView.windowStart(indicator: 4, count: 8)
        for index in 0..<8 {
            let alpha = SpaceDotsView.alpha(forDot: index, from: start)
            let inside = CGFloat(index) >= start && CGFloat(index) <= start + CGFloat(window - 1)
            XCTAssertEqual(alpha, inside ? 1 : 0, accuracy: 0.001, "dot \(index)")
        }
        XCTAssertEqual(SpaceDotsView.alpha(forDot: 0, from: 0.5), 0.5, accuracy: 0.001)
    }

    /// A dot sits on the centre of the pill's end cap — the inset is the
    /// radius, which is what stops it looking pushed into the curve.
    func testTheEndDotsSitOnTheCapsCentre() {
        for count in 1...Tokens.Metric.spaceDotWindow {
            let width = Self.pillWidth(for: count)
            let centres = SpaceDotsView.centres(count: count, in: width)
            XCTAssertEqual(centres.first, Tokens.Metric.spaceDotsPill.cornerRadius + Tokens.Metric.spaceDot / 2)
            XCTAssertEqual(centres.last, width - Tokens.Metric.spaceDotsPill.cornerRadius - Tokens.Metric.spaceDot / 2)
        }
    }

    /// Every count the pill is ever asked to hold, against the width it holds
    /// it at. Three claims, and the old layout failed all three at some count:
    /// the gaps are equal, the two end margins are equal, and every centre is a
    /// whole point — a dot on a half point is a dot drawn over two pixels.
    func testEveryCountIsEvenlySpacedSymmetricAndOnWholePoints() {
        for count in 1...Tokens.Metric.spaceDotWindow {
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
        let width = Self.pillWidth(for: 1)
        XCTAssertEqual(SpaceDotsView.centres(count: 1, in: width), [width / 2])
    }

    /// The dots have to stay inside the pill they are drawn in, mark and all.
    func testTheRunNeverOverflowsThePill() {
        for count in 1...Tokens.Metric.spaceDotWindow {
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
        let strip = Self.strip(spaces: 3)
        let dots = strip.subviews.compactMap { $0 as? SpaceDotView }
        XCTAssertEqual(dots.count, 3)
        XCTAssertEqual(dots.first?.frame.minX, 0)
        XCTAssertEqual(dots.last?.frame.maxX, strip.bounds.width)
        XCTAssertEqual(strip.bounds.width, SpaceDotsView.width(forDots: 3))
        for (left, right) in zip(dots, dots.dropFirst()) {
            XCTAssertEqual(left.frame.maxX, right.frame.minX, "slots overlap or leave a gap between them")
        }
    }

    /// The mark is drawn where the strip's arithmetic says, not where its own
    /// slot's middle happens to be — the first and last slots run out to the
    /// pill's edges and are not symmetric about their dot.
    func testEachDotIsToldItsOwnCentreRatherThanGuessingFromItsSlot() {
        let strip = Self.strip(spaces: 3)
        let dots = strip.subviews.compactMap { $0 as? SpaceDotView }
        let centres = SpaceDotsView.centres(count: 3, in: strip.bounds.width)
        for (dot, centre) in zip(dots, centres) {
            XCTAssertEqual(dot.frame.minX + dot.markCentreX, centre, accuracy: 0.001)
        }
    }

    /// §30.9's `+` takes a step of its own, so the pill makes room for it —
    /// otherwise the ring would have to be drawn over the last Space's dot,
    /// which is the one place it must not be.
    func testThePillMakesRoomForTheCreateRing() {
        let strip = Self.strip(spaces: 3)
        let resting = strip.intrinsicContentSize.width
        strip.creation = 0.5
        XCTAssertEqual(strip.intrinsicContentSize.width - resting, SpaceDotsView.createStep)
        strip.creation = 0
        XCTAssertEqual(strip.intrinsicContentSize.width, resting)
    }

    /// **The `+` stands in the row, not beside it.** It used to be centred in a
    /// slot of its own at the end of the pill, which put it 25 pt out from a
    /// run laid out on 14 — visibly detached from the Spaces it is offering to
    /// extend. Its step is the one that leaves the same clear air between the
    /// last dot and the ring as there is between any two dots.
    func testTheCreateRingStandsAtTheSameClearAirAsTheDots() {
        let dot = Tokens.Metric.spaceDot
        let betweenDots = Tokens.Metric.spaceDotPitch - dot
        let betweenDotAndRing = SpaceDotsView.createStep - dot / 2 - Tokens.Metric.spaceCreateRing / 2
        XCTAssertEqual(betweenDotAndRing, betweenDots, accuracy: 0.001)
    }

    /// **The ring never lands on the last Space's dot.** It is wider than the
    /// strip's own pitch, so a slot sized like a dot's would have drawn the two
    /// marks on top of each other — and the one dot the ring must never touch
    /// is the Space you are about to leave behind.
    func testTheCreateRingClearsTheLastDot() {
        let strip = Self.strip(spaces: 3)
        strip.creation = 1
        strip.frame = NSRect(origin: .zero, size: strip.intrinsicContentSize)
        strip.layoutSubtreeIfNeeded()
        let dots = strip.subviews.compactMap { $0 as? SpaceDotView }
        let ring = strip.subviews.compactMap { $0 as? SpaceCreateMarkView }.first
        let lastMark = (dots.last?.frame.minX ?? 0) + (dots.last?.markCentreX ?? 0)
        XCTAssertGreaterThan(ring?.frame.minX ?? 0, lastMark + Tokens.Metric.spaceDot / 2)
    }

    // MARK: - Bits

    /// What `SpaceDotsView.intrinsicContentSize` hands back for `count`.
    private static func pillWidth(for count: Int) -> CGFloat {
        SpaceDotsView.width(forDots: count)
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
