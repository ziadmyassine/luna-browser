//
//  LoadProgressLineTests.swift
//  LunaTests
//
//  §3.2c: the load line, under whichever address bar is on screen.
//
//  Two halves, and they fail differently. The geometry half is a *placement* —
//  a line 8 pt in on one pill and 12 on another is two lines — and it is
//  checked by rebuilding the capsule the reference measures rather than by
//  restating the tokens. The behaviour half is about a progress bar's three
//  ways of lying: flashing for a load that was already over, retreating when a
//  redirect resets `estimatedProgress`, and vanishing at four fifths.
//

import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class LoadProgressLineTests: XCTestCase {

    private let pill = NSRect(x: 0, y: 0, width: 266, height: Tokens.Metric.urlPill.height)

    private func line() -> LoadProgressLine {
        let line = LoadProgressLine()
        line.frame = LoadProgressLine.frame(inPill: pill)
        line.layoutSubtreeIfNeeded()
        return line
    }

    private func state(_ progress: Double, loading: Bool = true) -> TabState {
        TabState(url: URL(string: "https://apple.com"), isLoading: loading, progress: progress)
    }

    // MARK: - Where it goes

    /// The reference draws the line **inside** the capsule, along its bottom
    /// run: 2 pt thick, a text inset in from each end, and clear of the bottom
    /// edge by twice its own weight.
    func testTheLineSitsOnThePillsBottomRunAndNotUnderIt() {
        let frame = LoadProgressLine.frame(inPill: pill)
        XCTAssertEqual(frame.height, Tokens.Metric.loadLineHeight)
        XCTAssertEqual(frame.minX, Tokens.Metric.loadLineInset)
        XCTAssertEqual(pill.maxX - frame.maxX, Tokens.Metric.loadLineInset, "both ends stand in equally")
        XCTAssertEqual(frame.minY, Tokens.Metric.loadLineFloor)
        XCTAssertLessThan(frame.maxY, pill.height / 2, "it is a line on the pill, not a bar across it")
    }

    /// And it never crosses the capsule's corner, which is the reason the inset
    /// is the text's rather than nothing at all. Rebuilt from the circle: at
    /// `loadLineInset` in from the end of a full-radius pill, the boundary has
    /// come within a point of the bottom, so a line standing at `loadLineFloor`
    /// lies on the flat run with the curve already behind it.
    func testTheLineClearsTheCapsulesCurve() {
        let radius = pill.height / 2
        let acrossFromTheCentre = radius - Tokens.Metric.loadLineInset
        let boundary = radius - (radius * radius - acrossFromTheCentre * acrossFromTheCentre).squareRoot()
        XCTAssertLessThan(boundary, Tokens.Metric.loadLineFloor)
    }

    /// A pill too narrow to hold both insets is a pill with no line in it, not
    /// a line drawn backwards. §3.2b's capsule shrinks with the window.
    func testANarrowPillGetsAnEmptyLineRatherThanANegativeOne() {
        let frame = LoadProgressLine.frame(inPill: NSRect(x: 0, y: 0, width: 10, height: 22))
        XCTAssertEqual(frame.width, 0)
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
