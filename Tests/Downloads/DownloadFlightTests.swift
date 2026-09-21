//
//  DownloadFlightTests.swift
//  LunaTests
//
//  §5.0's arc, asserted without a window — which is the only way it can be
//  asserted at all.
//
//  The animation is 0.34 s long and happens in a corner nobody is looking
//  at. Bowed the wrong way, short of the button, or flat between two nearby
//  points: every one of those is a defect you have to catch in the act, and
//  three of them look identical to "the download started and nothing happened"
//  at the speed it runs. So the geometry is a pure function and this is where
//  it is checked.
//
//  The two rows below are the two chromes, and they are here as coordinates
//  rather than as a layout: §3.5 puts Downloads at the bottom-left corner
//  of the window and §4 puts it at the top-right, so the same throw has to
//  read as a throw going down-left and going up-right. That is the whole of
//  "make sure it works in both positions".
//

import XCTest
@testable import Luna

final class DownloadFlightTests: XCTestCase {

    /// A 1352 × 801 window — the one Luna restores to — with the file leaving
    /// from the middle of the page.
    private let file = CGPoint(x: 676, y: 400)
    /// §3.5's cylinder, at the foot of the column.
    private let sidebarButton = CGPoint(x: 120, y: 42)
    /// §4's capsule, at the head of the window.
    private let topBarButton = CGPoint(x: 1240, y: 770)

    private var bothLayouts: [(String, CGPoint)] {
        [("the sidebar's foot", sidebarButton), ("the top bar's capsule", topBarButton)]
    }

    /// The arc is the arc between the two points it was given, and not
    /// approximately: a flight that stops 20 pt short leaves the icon hanging
    /// beside the button rather than going into it.
    func testTheArcStartsAtTheFileAndEndsOnTheButton() {
        for (where_, button) in bothLayouts {
            let start = DownloadFlight.point(at: 0, from: file, to: button)
            let end = DownloadFlight.point(at: 1, from: file, to: button)
            XCTAssertEqual(start.x, file.x, accuracy: 0.001, "left from somewhere else, toward \(where_)")
            XCTAssertEqual(start.y, file.y, accuracy: 0.001, "left from somewhere else, toward \(where_)")
            XCTAssertEqual(end.x, button.x, accuracy: 0.001, "missed \(where_)")
            XCTAssertEqual(end.y, button.y, accuracy: 0.001, "missed \(where_)")
        }
    }

    /// A thrown object, in both directions: it covers the ground first and
    /// turns into the button at the end.
    ///
    /// This replaced a lob that always bowed upward, and the difference is the
    /// whole of what was wrong with it on screen. Going up to reach a button
    /// in the bottom corner is a detour the eye follows as a detour — the file
    /// leaves the page in the wrong direction and then comes back. Measured at
    /// the halfway mark: the throw is already past halfway across and still
    /// short of halfway down, in both layouts, which is what a corner control
    /// point buys and what a midpoint one cannot.
    func testTheThrowCoversTheGroundBeforeItTurnsIntoTheButton() {
        for (where_, button) in bothLayouts {
            let arc = DownloadFlight.point(at: 0.5, from: file, to: button)
            let straight = CGPoint(x: (file.x + button.x) / 2, y: (file.y + button.y) / 2)
            XCTAssertLessThan(
                abs(arc.x - button.x), abs(straight.x - button.x),
                "the throw toward \(where_) is no further across than a straight line"
            )
            XCTAssertGreaterThan(
                abs(arc.y - button.y), abs(straight.y - button.y),
                "the throw toward \(where_) has already turned in"
            )
        }
    }

    /// And the wind-up is away from the button: still climbing at halfway when
    /// the button is below, still low when it is above. A curve that bowed
    /// with the travel rather than against it would pass both halves of the
    /// test above and read as a file sliding off a shelf.
    func testTheWindUpIsAwayFromTheButton() {
        let down = CGPoint(x: (file.x + sidebarButton.x) / 2, y: (file.y + sidebarButton.y) / 2)
        XCTAssertGreaterThan(
            DownloadFlight.point(at: 0.5, from: file, to: sidebarButton).y, down.y,
            "a throw to the foot of the sidebar should still be high at halfway"
        )
        let up = CGPoint(x: (file.x + topBarButton.x) / 2, y: (file.y + topBarButton.y) / 2)
        XCTAssertLessThan(
            DownloadFlight.point(at: 0.5, from: file, to: topBarButton).y, up.y,
            "a throw to the head of the window should still be low at halfway"
        )
    }

    /// Two points on one line still get an arc. Without the wind-up the corner
    /// control point collapses onto the straight line and the throw is a
    /// slide — which is exactly the case a link low on the page hits in the
    /// sidebar layout.
    func testAThrowAlongOneLineIsStillAThrow() {
        let level = CGPoint(x: 900, y: sidebarButton.y)
        let arc = DownloadFlight.point(at: 0.5, from: level, to: sidebarButton)
        XCTAssertGreaterThan(arc.y - level.y, DownloadFlight.minimumLift / 3, "a flat slide, not a throw")
    }

    /// It arrives the size of the mark on the button it is landing on, which is
    /// what makes the landing read as the file going into the shelf.
    func testTheIconArrivesTheSizeOfTheButtonsOwnGlyph() {
        let start = Tokens.Metric.downloadsFileIcon * DownloadFlight.scale(at: 0)
        let end = Tokens.Metric.downloadsFileIcon * DownloadFlight.scale(at: 1)
        XCTAssertEqual(start, Tokens.Metric.downloadsFileIcon, accuracy: 0.001)
        XCTAssertEqual(end, Tokens.Metric.glyphSize, accuracy: 0.001)
        XCTAssertLessThan(DownloadFlight.scale(at: 0.5), 1, "it should be shrinking on the way")
    }

    /// Whole until it is almost there. An icon that fades across the whole
    /// arc is a ghost drifting off the page; one that is solid until the last
    /// fifth is a file being caught.
    func testTheIconOnlyFadesAsItLands() {
        XCTAssertEqual(DownloadFlight.opacity(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(DownloadFlight.opacity(at: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(DownloadFlight.opacity(at: 0.8), 1, accuracy: 0.001)
        XCTAssertLessThan(DownloadFlight.opacity(at: 0.95), 0.4)
        XCTAssertEqual(DownloadFlight.opacity(at: 1), 0, accuracy: 0.001)
    }

    /// Progress outside 0…1 is a clock that overran, not a file that overshot.
    func testTheArcIsClampedToItsOwnEnds() {
        XCTAssertEqual(DownloadFlight.point(at: -1, from: file, to: topBarButton).x, file.x, accuracy: 0.001)
        XCTAssertEqual(DownloadFlight.point(at: 2, from: file, to: topBarButton).x, topBarButton.x, accuracy: 0.001)
        XCTAssertEqual(DownloadFlight.scale(at: -1), 1, accuracy: 0.001)
        XCTAssertEqual(DownloadFlight.scale(at: 9), DownloadFlight.landingScale, accuracy: 0.001)
    }
}

/// The catch, and the progress bar the list opens with.
@MainActor
final class DownloadCatchTests: XCTestCase {

    /// The button ends its own size. The bulge is an animation from 1.18
    /// back to 1 with the model layer already at rest, so a catch interrupted
    /// by a second download — or by Reduce Motion coming on mid-flight —
    /// leaves the Downloads button the size it has always been. Written the
    /// other way round it leaves a permanently swollen button in the corner of
    /// the window, which is the one failure here that never heals.
    func testTheCatchLeavesTheButtonItsOwnSize() {
        let capsule = NSView(frame: NSRect(x: 0, y: 0, width: 68, height: 34))
        capsule.wantsLayer = true
        Tokens.Motion.catchDownload(on: capsule)
        let scale = capsule.layer?.value(forKeyPath: "transform.scale.x") as? CGFloat ?? 0
        XCTAssertEqual(scale, 1, accuracy: 0.001, "the button is left mid-bulge")
    }

    /// §3.2c's rule 2, here too: a download that reports a smaller fraction
    /// after a resume is not a file getting further away.
    func testTheProgressBarNeverGoesBackwards() {
        let line = DownloadProgressLine(frame: NSRect(x: 0, y: 0, width: 200, height: 2))
        line.advance(to: 0.4)
        XCTAssertEqual(line.fraction, 0.4, accuracy: 0.001)
        line.advance(to: 0.1)
        XCTAssertEqual(line.fraction, 0.4, accuracy: 0.001, "the bar retreated")
        line.advance(to: 1)
        XCTAssertEqual(line.fraction, 1, accuracy: 0.001)
        // A retry does start over, and that is a reset rather than a retreat.
        line.reset()
        XCTAssertEqual(line.fraction, 0, accuracy: 0.001)
    }

    /// Anything a server sends is clamped before it reaches the bar: a
    /// `Content-Length` that disagrees with the bytes gives a fraction over 1.
    func testTheProgressBarIsClampedToItsOwnTrack() {
        let line = DownloadProgressLine(frame: NSRect(x: 0, y: 0, width: 200, height: 2))
        line.advance(to: 4)
        XCTAssertEqual(line.fraction, 1, accuracy: 0.001)
    }
}
