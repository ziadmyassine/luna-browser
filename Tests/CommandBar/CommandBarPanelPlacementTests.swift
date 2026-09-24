//
//  CommandBarPanelPlacementTests.swift
//  LunaTests
//
//  §9.1 anchors the bar over the page, 20 % down. Both halves of that are
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

    /// One pass, not two. The bar is shown by `animateIn`, which lays the
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

    /// And it stays put. A panel that re-derives its constants on the way out
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

/// §3.2 and §3.2b hand the address to §9.1, and §9.1 stands on the pill that
/// handed it over rather than opening in the middle of the page. So the
/// panel's four numbers stop being a fraction of the page and become the pill's
/// own: its leading edge, its width, its top, and its height for the input row.
@MainActor
final class CommandBarAnchoredPlacementTests: XCTestCase {

    private var window: NSWindow?

    /// A sidebar-width pill near the top of a real window — the panel refuses
    /// to read an anchor that is not in the window it is in, which is the one
    /// state where converting coordinates would answer nonsense.
    private func anchored(
        pill frame: NSRect = NSRect(x: 8, y: 700, width: 244, height: Tokens.Metric.urlPill.height)
    ) -> (panel: CommandBarPanel, pill: URLPillView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        self.window = window
        let root = window.contentView ?? NSView()
        let pill = URLPillView()
        pill.frame = frame
        root.addSubview(pill)
        let panel = CommandBarPanel(
            frame: root.bounds,
            resultsView: CommandBarResultsView(frame: .zero),
            anchor: CommandBarAnchor(view: pill)
        )
        root.addSubview(panel)
        panel.layoutSubtreeIfNeeded()
        return (panel, pill)
    }

    /// The bar stands on the pill's line, and is wider than it: a bar
    /// exactly as wide as a 244 pt sidebar pill is a column of ellipses, so it
    /// takes a `chromeGapWide` at each end and never less than
    /// `commandBarMinWidth`.
    func testTheBarStandsOnThePillsLineAndOutgrowsIt() {
        let (panel, pill) = anchored()
        // A margin above the pill's own top edge, so the query is not hard
        // against the glass — the field stays on the pill's centre line, which
        // `testTheFieldSitsOnTheLineTheAddressWasOn` is what checks.
        XCTAssertEqual(
            panel.body.frame.maxY,
            pill.frame.maxY + CommandBarMetrics.padding,
            accuracy: 0.5
        )
        XCTAssertEqual(
            panel.body.frame.width,
            max(pill.frame.width + 2 * Tokens.Metric.chromeGapWide, Tokens.Metric.commandBarMinWidth),
            accuracy: 0.5
        )
        XCTAssertGreaterThan(panel.body.frame.width, pill.frame.width)
        XCTAssertNotEqual(panel.body.frame.width, CommandBarMetrics.width)
    }

    /// It keeps the pill's centre line where it can — §3.2b's capsule is
    /// centred over the page and its bar belongs on the same axis.
    func testItKeepsThePillsCentreWhenThereIsRoom() {
        let wide = NSRect(x: 380, y: 740, width: 420, height: Tokens.Metric.urlPill.height)
        let (panel, pill) = anchored(pill: wide)
        XCTAssertEqual(panel.body.frame.midX, pill.frame.midX, accuracy: 0.5)
    }

    /// And gives that up at the window's edge rather than hanging off it. A
    /// sidebar's pill is 140 pt from the leading edge, where a 360 pt bar
    /// centred on it would start 40 pt off screen; clamped, it lands
    /// leading-aligned with the pill, which is where a bar growing out of the
    /// first thing in a column belongs anyway.
    func testTheWindowsEdgePushesItOffThatCentre() {
        let (panel, pill) = anchored()
        XCTAssertGreaterThanOrEqual(panel.body.frame.minX, Tokens.Metric.chromeGap)
        XCTAssertEqual(panel.body.frame.minX, pill.frame.minX, accuracy: 0.5)
    }

    /// An anchor near the window's top edge — every one Luna has — keeps the
    /// bar inside the window: the glass rises only as far as the edge allows,
    /// and the field stays on the anchor's centre line.
    func testAnAnchorNearTheTopKeepsTheBarInsideTheWindow() {
        let (panel, pill) = anchored(pill: NSRect(x: 380, y: 800 - 8 - 34, width: 300, height: 34))
        XCTAssertLessThanOrEqual(panel.body.frame.maxY, panel.bounds.maxY - CommandBarMetrics.edgeClearance + 0.5)
        XCTAssertGreaterThanOrEqual(panel.body.frame.maxY, pill.frame.maxY)
        let field = panel.body.convert(panel.field.frame, to: panel)
        XCTAssertEqual(field.midY, pill.frame.midY, accuracy: 1)
    }

    /// §4's tab hands over a span as well: the bar grows out of the tab but
    /// never over what is left of the strip — the traffic lights, back and
    /// forward. Clamped only to the window, a tab near the bar's start opened
    /// its bar over the lights.
    func testASpanKeepsTheBarOffWhatIsBesideIt() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        self.window = window
        let root = window.contentView ?? NSView()
        let strip = NSView(frame: NSRect(x: 150, y: 752, width: 900, height: 40))
        let tab = NSView(frame: NSRect(x: 160, y: 756, width: 130, height: 30))
        root.addSubview(strip)
        root.addSubview(tab)
        let panel = CommandBarPanel(
            frame: root.bounds,
            resultsView: CommandBarResultsView(frame: .zero),
            anchor: CommandBarAnchor(view: tab, span: strip)
        )
        root.addSubview(panel)
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.minX, strip.frame.minX, accuracy: 0.5)
        XCTAssertEqual(panel.body.frame.maxY, tab.frame.maxY + CommandBarMetrics.padding, accuracy: 0.5)
    }

    /// And it is more glass than the pill was, downwards — that is the whole of
    /// the morph. A bar that grew upwards or centred itself on the pill would
    /// cover the page's top edge and the controls beside it.
    func testTheGlassItAddsGoesDownwards() {
        let (panel, pill) = anchored()
        XCTAssertGreaterThan(panel.body.frame.height, pill.frame.height)
        XCTAssertLessThan(panel.body.frame.minY, pill.frame.minY)
    }

    /// The input row is the pill's height, not a chrome bar's 52: the field has
    /// to sit on the line the address was already on.
    func testTheFieldSitsOnTheLineTheAddressWasOn() {
        let (panel, pill) = anchored()
        let field = panel.convert(panel.field.frame, from: panel.field.superview)
        XCTAssertEqual(field.midY, pill.frame.midY, accuracy: 1)
    }

    /// The pill moves — a window resize, a sidebar drag — and the bar moves
    /// with it. Every constant is re-derived per pass for exactly this.
    func testItFollowsThePillItGrewFrom() {
        let wide = NSRect(x: 380, y: 740, width: 420, height: Tokens.Metric.urlPill.height)
        let (panel, pill) = anchored(pill: wide)
        pill.frame = pill.frame.offsetBy(dx: 60, dy: -40)
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.midX, pill.frame.midX, accuracy: 0.5)
        XCTAssertEqual(
            panel.body.frame.maxY,
            pill.frame.maxY + CommandBarMetrics.padding,
            accuracy: 0.5
        )
    }

    /// And the list starts below that margin, not against the field: the input
    /// row is the pill's height plus a margin at each end of it.
    func testTheListClearsTheField() {
        let (panel, pill) = anchored()
        let results = panel.convert(panel.results.frame, from: panel.results.superview)
        XCTAssertEqual(
            panel.body.frame.maxY - results.maxY,
            pill.frame.height + 2 * CommandBarMetrics.padding,
            accuracy: 0.5
        )
    }
}
