//
//  RowPillTests.swift
//  LunaTests
//
//  §3.4's two row fills, and the one thing about them that is not about the
//  pointer: what happens to a fill when the list under it stops being the
//  same list.
//

import AppKit
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

    /// A §6 Space switch used to leave the old Space's selection burning over
    /// the new one. The rows and the tiles both leave in the frame the switch
    /// lands in, but the fill under them faded out over `rowHover` while the
    /// column faded in over `spaceSwitchCrossfade` — so for about a tenth of a
    /// second the Space you had just arrived in had an empty glass pill lying
    /// in it, on a row that was not there any more. Caught on video; this is
    /// the assertion that keeps it caught.
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
}
