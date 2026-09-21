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
