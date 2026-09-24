//
//  HiddenSidebarTests.swift
//  LunaTests
//
//  What the chrome does while `⌘S` has the sidebar away, and when it comes
//  back. Both of the things tested here were bugs in the same corner of the
//  window — the one the traffic lights are in, which is also the one §3.2b puts
//  the sidebar toggle in when there is no sidebar to put it on.
//

import XCTest
@testable import Luna

@MainActor
final class SidebarPeekReachTests: XCTestCase {

    /// §7.2's trigger strip, in the window it lies along.
    private func strip() throws -> (strip: NSView, root: NSView) {
        let controller = BrowserWindowController()
        let root = try XCTUnwrap(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let strip = try XCTUnwrap(root.subviews.first { $0 is SidebarPeekEdgeView })
        return (strip, root)
    }

    /// The strip starts below the bar. With the sidebar hidden, §3.2b puts
    /// the toggle on the page at the window's leading corner — inside the top
    /// `pageBar` points — so a strip that ran the window's full height pulled
    /// the sidebar out from under the pointer on its way to that button. The
    /// button then moved a column's width to the right, the pointer followed it
    /// off the strip, the peek closed and the button went back.
    func testThePeekStripLeavesThePageBarsOwnBandAlone() throws {
        let (strip, root) = try strip()
        XCTAssertEqual(root.bounds.maxY - strip.frame.maxY, Tokens.Metric.pageBar, accuracy: 0.5)
    }

    /// It still covers everything below that, which is the whole of what §7.2
    /// is for: a hidden sidebar has to be reachable without the keystroke that
    /// hid it.
    func testItStillLiesAlongTheRestOfTheLeadingEdge() throws {
        let (strip, root) = try strip()
        XCTAssertEqual(strip.frame.minX, root.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(strip.frame.minY, root.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(strip.frame.width, Tokens.Metric.sidebarPeekEdge, accuracy: 0.5)
    }

    /// Dia's rule: past the window's edge beside the strip still counts, so a
    /// 4 pt strip cannot be overshot. Level with the strip only — not above
    /// it, where the page bar's own controls are — and only past its own edge.
    func testLeavingTheWindowAcrossTheStripStillCounts() {
        let root = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let leading = NSRect(x: 0, y: 0, width: 4, height: 648)
        XCTAssertTrue(SidebarPeekEdgeView.isBeyond(NSPoint(x: -150, y: 300), strip: leading, in: root))
        XCTAssertFalse(SidebarPeekEdgeView.isBeyond(NSPoint(x: -150, y: 690), strip: leading, in: root),
                       "above the strip is the page bar's corner")
        XCTAssertFalse(SidebarPeekEdgeView.isBeyond(NSPoint(x: 2, y: 300), strip: leading, in: root),
                       "inside the window is the strip's own business")
        XCTAssertFalse(SidebarPeekEdgeView.isBeyond(NSPoint(x: 1200, y: 300), strip: leading, in: root),
                       "the far edge is not this strip's")
    }

    /// Fullscreen: up in the menu bar counts, and anywhere below it does not.
    /// The screen's top is its `maxY`, which is what a pointer pushed against
    /// it reads — measured on a 1512 × 982 display.
    func testTheMenuBarCountsWhileThePointerIsInIt() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        func check(_ x: CGFloat, _ y: CGFloat, was: Bool) -> Bool {
            SidebarPeekMenuBarWatch.isInMenuBar(NSPoint(x: x, y: y), wasInside: was, screen: screen, menuBarHeight: 37)
        }
        XCTAssertTrue(check(700, 982, was: false), "the top edge reveals the menu bar")
        XCTAssertFalse(check(700, 960, was: false), "near the top is the page bar, not the menu bar")
        XCTAssertTrue(check(20, 950, was: true), "along the revealed menu bar")
        XCTAssertFalse(check(700, 940, was: true), "below it")
        XCTAssertFalse(check(1600, 982, was: false), "another display's menu bar")
    }

    /// A sidebar parked on the trailing side peeks from that edge instead.
    func testTrailingStripAlsoCountsBeyondItsOwnEdge() {
        let root = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let trailing = NSRect(x: 996, y: 0, width: 4, height: 648)
        XCTAssertTrue(SidebarPeekEdgeView.isBeyond(NSPoint(x: 1100, y: 300), strip: trailing, in: root))
        XCTAssertFalse(SidebarPeekEdgeView.isBeyond(NSPoint(x: -100, y: 300), strip: trailing, in: root))
    }
}

/// The traffic lights come and go — `⌘S` takes them with the sidebar, §7.2's
/// peek lends them back for the length of a peek — and that changes no view's
/// bounds, so nothing in AppKit marks the chrome that lays itself out against
/// them as dirty. They have to be named; `TrafficLightNeighbour` is the name.
///
/// Missing the second caller is what left the sidebar's toggle drawn on top of
/// the close button after `⌘S` twice: the row had laid itself out while there
/// were no lights to clear, which correctly puts the toggle at the row inset,
/// and nothing asked it to look again once they were back.
@MainActor
final class TrafficLightNeighbourTests: XCTestCase {

    func testANeighbourNestedInTheChromeIsAskedToLayOutAgain() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 800))
        let host = NSView(frame: root.bounds)
        let row = SidebarControlRow()
        row.frame = NSRect(x: 0, y: 748, width: 280, height: Tokens.Metric.topBarHeight)
        host.addSubview(row)
        root.addSubview(host)
        root.layoutSubtreeIfNeeded()
        row.needsLayout = false

        TrafficLightSpace.neighboursNeedLayout(in: root)
        XCTAssertTrue(row.needsLayout, "the row that clears the lights was not asked to look again")
    }

    /// §3.2b's bar is the other one: it puts the same toggle in the same corner
    /// when the column is away.
    func testThePageBarIsANeighbourToo() {
        XCTAssertTrue(PageChromeBar() is any TrafficLightNeighbour)
        XCTAssertTrue(SidebarControlRow() is any TrafficLightNeighbour)
    }
}
