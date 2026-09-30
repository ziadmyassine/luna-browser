//
//  RowPillTests.swift
//  LunaTests
//
//  §3.4's two row fills, and the one thing about them that is not about the
//  pointer: what happens to a fill when the list under it stops being the
//  same list.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class RowPillTests: XCTestCase {

    private func litPill() -> RowPillView {
        let pill = RowPillView(role: .selected)
        pill.frame = NSRect(x: 0, y: 0, width: 200, height: Tokens.Metric.rowPillHeight)
        pill.alphaValue = 1
        return pill
    }

    /// A §6 Space switch must not leave the old Space's selection over the new
    /// one. The rows and tiles leave in the frame the switch lands in, but a
    /// fill fading out over `rowHover` while the column fades in over
    /// `spaceSwitchCrossfade` leaves an empty glass pill in the new Space for
    /// about a tenth of a second, on a row that is not there.
    ///
    /// The fade already running is the part that matters: parking asks for the
    /// value the in-flight animation is already heading to, so an
    /// `alphaValue` short-cut would return without cancelling anything and the
    /// pill would go on fading.
    func testParkingThePillCancelsAFadeThatIsAlreadyRunning() {
        let pill = litPill()
        pill.fade(to: 0)
        pill.fade(to: 0, animated: false)
        XCTAssertEqual(pill.alphaValue, 0, accuracy: 0.001)
        XCTAssertEqual(pill.layer?.animationKeys() ?? [], [], "the fade is still running")
    }

    /// The other half: a pill moved without a spec lands at full strength
    /// rather than fading up into the Space it arrived in. Same frame, both
    /// ends — one transition per switch, and it is the column's.
    func testAPillMovedWithoutASpecArrivesRatherThanFadingIn() {
        let pill = litPill()
        pill.fade(to: 0, animated: false)
        pill.move(to: NSRect(x: 0, y: 40, width: 200, height: Tokens.Metric.rowPillHeight), spec: nil)
        XCTAssertEqual(pill.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(pill.layer?.animationKeys() ?? [], [], "the pill is still animating somewhere")
    }

    /// And the pointer's own move still springs, or §3.4's selection stops
    /// travelling between rows and starts blinking between them.
    func testTheSelectionStillSpringsWhenItIsTheSelectionMoving() {
        let pill = litPill()
        pill.move(to: NSRect(x: 0, y: 40, width: 200, height: Tokens.Metric.rowPillHeight),
                  spec: Tokens.Motion.selectedRowMove)
        XCTAssertEqual(pill.layer?.animation(forKey: "position") != nil, !Tokens.Motion.reduceMotion)
    }

    /// §3.4b's `⌘W` again. Closing the page of a kept row leaves the Space with
    /// nothing selected, and the list has to hear that. As a plain optional,
    /// "nothing" and "do not change it" are the same value: the fill stays on
    /// the row just closed, and a second `⌘W` lets that row go.
    func testHandingOverNoSelectionClearsTheOneOnScreen() throws {
        let space = UUID()
        let kept = Tab(spaceID: space, kind: .pinned, url: URL(string: "https://example.com/kept")!)
        let controller = TabListController()
        controller.show(saved: [.tab(kept)], today: [], essentials: [], activeTabID: kept.id)
        XCTAssertEqual(controller.activeTabID, kept.id)

        controller.show(saved: [.tab(kept)], today: [], essentials: [], activeTabID: nil)

        XCTAssertNil(controller.activeTabID, "the list kept a selection the Space no longer has")
    }

    /// The read part of the page is a band from the leading edge, as wide as
    /// the fraction read — and square at its trailing end, which is the
    /// reading position rather than a shape.
    func testTheBandIsAsWideAsThePageHasBeenRead() {
        let pill = litPill()
        pill.progress = 0.25
        pill.layoutSubtreeIfNeeded()
        XCTAssertEqual(pill.band.frame, NSRect(x: 0, y: 0, width: 50, height: pill.bounds.height))
        pill.progress = 1
        pill.layoutSubtreeIfNeeded()
        XCTAssertEqual(pill.band.frame.width, 200)
    }

    /// A page with nothing below the fold has nothing to show, and that is not
    /// the same as a page at its top — but both draw no band.
    func testAPageThatCannotScrollDrawsNoBand() {
        let pill = litPill()
        pill.progress = 0.5
        pill.layoutSubtreeIfNeeded()
        pill.progress = nil
        pill.layoutSubtreeIfNeeded()
        XCTAssertEqual(pill.band.frame.width, 0)
    }

    /// Only the selected row is being read. The hover pill sits under a row
    /// the reader is not on, so it never carries the band.
    func testOnlyTheSelectedPillCarriesTheBand() {
        let controller = TabListController()
        controller.setScrollProgress(0.4)
        XCTAssertEqual(controller.selectionPill.progress, 0.4)
        XCTAssertNil(controller.hoverPill.progress)
        controller.setScrollProgress(nil)
        XCTAssertNil(controller.selectionPill.progress)
    }
}
