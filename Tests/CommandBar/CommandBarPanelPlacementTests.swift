//
//  CommandBarPanelPlacementTests.swift
//  LunaTests
//
//  §9.1 anchors the bar over the **page**, 20 % down. Both halves of that are
//  constraint constants the panel derives per layout pass, and a constant that
//  is derived at the wrong moment does not go wrong quietly — it opens the bar
//  at the window's top-centre, which is a sidebar's half-width to the left of
//  the page and a fifth of a window too high, and leaves it there.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarPanelPlacementTests: XCTestCase {

    /// A window with a sidebar: the page is inset from three edges, so
    /// "centred on the window" and "centred on the page" are 120 pt apart and a
    /// misplacement cannot hide.
    private let window = NSRect(x: 0, y: 0, width: 1200, height: 800)
    private let page = NSRect(x: 240, y: 16, width: 944, height: 744)

    private func panel() -> CommandBarPanel {
        let host = NSView(frame: window)
        let panel = CommandBarPanel(frame: host.bounds, resultsView: CommandBarResultsView(frame: .zero))
        panel.contentRegion = { self.page }
        host.addSubview(panel)
        return panel
    }

    /// **One pass, not two.** The bar is shown by `animateIn`, which lays the
    /// subtree out once and then fades it up; anything the panel leaves for a
    /// later pass is on screen in the meantime.
    func testTheBarIsOverThePageAfterItsFirstLayoutPass() {
        let panel = panel()
        panel.layoutSubtreeIfNeeded()

        XCTAssertEqual(panel.body.frame.midX, page.midX, accuracy: 0.5)
        XCTAssertEqual(
            panel.bounds.maxY - panel.body.frame.maxY,
            (window.maxY - page.maxY) + page.height * CommandBarMetrics.topAnchorFraction,
            accuracy: 0.5
        )
    }

    /// And it stays put. A panel that re-derives its constants on the way *out*
    /// of `layout()` reports itself clean while holding a frame it has already
    /// disagreed with, so the give-away is a second pass that moves it.
    func testASecondLayoutPassDoesNotMoveTheBar() {
        let panel = panel()
        panel.layoutSubtreeIfNeeded()
        let first = panel.body.frame
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()

        XCTAssertEqual(panel.body.frame, first)
    }
}
