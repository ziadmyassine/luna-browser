//
//  LoadProgressLineTests.swift
//  LunaTests
//
//  §3.2c: the load line, under whichever address bar is on screen.
//
//  Two halves, and they fail differently. The geometry half is a *placement* —
//  a line lying on the edge of one pill and floating inside another is two
//  lines — and it is checked by asking the capsule the reference measures
//  where it is, rather than by restating the tokens. The behaviour half is
//  about a progress bar's three ways of lying: flashing for a load that was
//  already over, retreating when a redirect resets `estimatedProgress`, and
//  vanishing at four fifths.
//

import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class LoadProgressLineTests: XCTestCase {

    private let pill = NSRect(x: 0, y: 0, width: 266, height: Tokens.Metric.urlPill.height)

    private func line() -> LoadProgressLine {
        let line = LoadProgressLine()
        line.place(inPill: pill, cornerRadius: Tokens.Metric.urlPill.cornerRadius)
        line.layoutSubtreeIfNeeded()
        return line
    }

    private func state(_ progress: Double, loading: Bool = true) -> TabState {
        TabState(url: URL(string: "https://apple.com"), isLoading: loading, progress: progress)
    }

    // MARK: - Where it goes

    /// The reference draws the line **on** the capsule's bottom, not inside it
    /// at a distance: 2 pt thick, lying on the inner edge with the pill's own
    /// hairline under it, and spanning the whole pill so that a finished load
    /// reaches the far end rather than stopping a text inset short.
    func testTheLineLiesOnThePillsBottomEdgeRatherThanFloatingAboveIt() {
        let frame = LoadProgressLine.frame(inPill: pill)
        XCTAssertEqual(frame.height, Tokens.Metric.loadLineHeight)
        XCTAssertEqual(frame.minY, Tokens.Metric.hairline, "on the inside of the pill's own border")
        XCTAssertLessThanOrEqual(frame.minY, Tokens.Metric.loadLineHeight, "touching the edge, not clear of it")
        XCTAssertEqual(frame.minX, 0)
        XCTAssertEqual(frame.width, pill.width, "the whole capsule, end to end")
    }

    /// And the ends are the capsule's, which is the other half of reading as
    /// the pill filling up: the mask keeps the strip inside the corner, so the
    /// leading end is the curve itself rather than a cap drawn short of it.
    func testTheCapsuleCutsTheLinesEndsRatherThanTheLineStandingClearOfThem() {
        let radius = Tokens.Metric.urlPill.cornerRadius
        let path = LoadProgressLine.capsule(inPill: pill, cornerRadius: radius)
        let onTheFlatRun = CGPoint(x: radius, y: Tokens.Metric.loadLineHeight / 2)
        let outInTheCorner = CGPoint(x: Tokens.Metric.hairline, y: Tokens.Metric.loadLineHeight / 2)
        XCTAssertTrue(path.contains(onTheFlatRun), "the line is drawn where the capsule is")
        XCTAssertFalse(path.contains(outInTheCorner), "and cut where the capsule has curved away")
        XCTAssertEqual(path.boundingBox.minY, 0, accuracy: 0.001, "the well starts where the line does")
    }

    /// A pill too narrow to hold a full corner still gets a shape rather than
    /// a `CGPath` drawn with a radius bigger than the rect — §3.2b's capsule
    /// shrinks with the window, and §4's with the tab count.
    func testANarrowPillGetsACapsuleItCanActuallyDraw() {
        let narrow = NSRect(x: 0, y: 0, width: 10, height: 22)
        let path = LoadProgressLine.capsule(inPill: narrow, cornerRadius: 11)
        XCTAssertFalse(path.isEmpty)
        XCTAssertLessThanOrEqual(path.boundingBox.width, narrow.width)
        XCTAssertEqual(LoadProgressLine.frame(inPill: narrow).width, narrow.width)
    }

    // MARK: - What it draws

    /// Rule 2. `estimatedProgress` falls when a load commits a new document —
    /// a redirect two thirds of the way through a page is not the page getting
    /// further away, and a bar that retreats reads as a fault in the page.
    func testTheLineDoesNotRetreatWhenProgressDoes() {
        let line = line()
        let tab = UUID()
        line.show(state(0.6), for: tab)
        line.show(state(0.2), for: tab)
        XCTAssertEqual(line.fraction, 0.6, accuracy: 0.001)
    }

    /// A switch is not progress. The pill is reused across one — §4's is
    /// literally the same view — so without the id the line would carry the
    /// tab you just left half way into the tab you just opened.
    func testATabSwitchStartsTheLineOverRatherThanContinuingIt() {
        let line = line()
        line.show(state(0.8), for: UUID())
        line.show(state(0.1), for: UUID())
        XCTAssertEqual(line.fraction, 0.1, accuracy: 0.001)
    }

    /// Rule 1, and the one that decides whether this is worth having at all: a
    /// cached reload is over before a progress bar could say anything true
    /// about it, and a line that flashed on every back-navigation would be
    /// noise on the most common navigation there is.
    func testALoadShorterThanTheSkipThresholdNeverShows() async throws {
        let line = line()
        let tab = UUID()
        line.show(state(0.1), for: tab)
        line.show(state(1, loading: false), for: tab)
        try await Task.sleep(for: .seconds(Tokens.Motion.reloadSkipThreshold * 2))
        XCTAssertEqual(line.alphaValue, 0, "a load that was already over played nothing")
        XCTAssertEqual(line.fraction, 0)
    }

    /// A load that outlives the threshold does show — and rule 3: it is at full
    /// when it goes, not at whatever fraction `didFinish` happened to land on.
    func testALongerLoadShowsAndLeavesAtFull() async throws {
        let line = line()
        let tab = UUID()
        line.show(state(0.2), for: tab)
        try await Task.sleep(for: .seconds(Tokens.Motion.reloadSkipThreshold * 2))
        XCTAssertEqual(line.alphaValue, 1, "a load still running after the threshold is worth drawing")

        line.show(state(0.8, loading: false), for: tab)
        XCTAssertEqual(line.fraction, 1, "it runs to the end before it fades")
    }

    // MARK: - Which surface wears it

    /// The view really is in the window, really is on top of the chrome, and
    /// really does appear and disappear with the address bar. The pure rule
    /// above is only worth having if something reads it.
    func testTheWindowsLineFollowsWhichAddressBarIsShowing() throws {
        let controller = BrowserWindowController()
        let root = try XCTUnwrap(controller.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let line = try XCTUnwrap(root.subviews.compactMap { $0 as? LoadProgressLine }.first)

        controller.setChromeStateWithoutAnimation(.sidebar(width: 280, edge: .leading))
        XCTAssertTrue(line.isHidden, "the column's pill is wearing it")

        controller.setChromeStateWithoutAnimation(.sidebarCollapsed(edge: .leading))
        XCTAssertFalse(line.isHidden, "nothing else is showing an address")

        controller.setSearchBarOnPage(true)
        XCTAssertTrue(line.isHidden, "§3.2b's bar is on the page, and it has the pill")

        controller.setSearchBarOnPage(false)
        XCTAssertFalse(line.isHidden)
        XCTAssertEqual(line.frame.height, Tokens.Metric.loadLineHeight)
        XCTAssertEqual(line.frame.width, root.bounds.width, accuracy: 0.5, "it spans the window")
        XCTAssertEqual(root.bounds.maxY - line.frame.maxY, 0, accuracy: 0.5, "on the top edge")
        XCTAssertIdentical(root.subviews.last, line, "above the chrome — §3.8's peek covers that corner")
    }

    /// And it is fed while it is hidden, which is the point of feeding it from
    /// the window rather than from whichever view happens to be showing:
    /// `⌘S` half way through a load hands over a line that is already at the
    /// right fraction instead of one starting again from nothing.
    func testTheWindowsLineKeepsCountingWhileAPillIsWearingIt() throws {
        let controller = BrowserWindowController()
        _ = try XCTUnwrap(controller.window?.contentView)
        controller.setChromeStateWithoutAnimation(.sidebar(width: 280, edge: .leading))
        let tab = UUID()
        controller.setLoadProgress(state(0.7), for: tab)

        let root = try XCTUnwrap(controller.window?.contentView)
        let line = try XCTUnwrap(root.subviews.compactMap { $0 as? LoadProgressLine }.first)
        XCTAssertEqual(line.fraction, 0.7, accuracy: 0.001)
    }

    /// §3.2c's whole fallback, in one table. The question is never "which
    /// layout is this" but "is there an address bar the user can see" — a
    /// hidden sidebar is the case that has none, and the window's top edge is
    /// what is left.
    func testTheWindowOnlyTakesTheLineWhenNoAddressBarIsShowing() {
        let width = Tokens.Metric.sidebarWidth.default
        let cases: [(ChromeState, Bool, LoadProgressHost)] = [
            (.sidebar(width: width, edge: .leading), false, .sidebarPill),
            (.sidebar(width: width, edge: .leading), true, .pageBarPill),
            (.sidebarCollapsed(edge: .leading), true, .pageBarPill),
            (.sidebarCollapsed(edge: .leading), false, .windowTop),
            (.topBar, false, .topBarPill),
            (.fullscreen, false, .windowTop)
        ]
        for (state, onPage, expected) in cases {
            XCTAssertEqual(
                state.loadProgressHost(searchBarOnPage: onPage),
                expected,
                "\(state) with the search bar \(onPage ? "on the page" : "in the chrome")"
            )
        }
    }
}
