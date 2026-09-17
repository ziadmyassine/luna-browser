//
//  ChromeLayoutTests.swift
//  LunaTests
//
//  TODO.md §7.7: "write a single `TrafficLightLayoutManager` and unit-test its
//  output for the window states rather than nudging frames in 4 different view
//  controllers". This file is that test — it is the reason the geometry is a
//  pure function instead of a pile of `setFrameOrigin` calls.
//
//  The fixtures are measured, not invented: a probe run against macOS 26 reports
//  a 32 pt `NSTitlebarView` holding three 14 × 14 buttons at x = 9 / 32 / 55.
//

import XCTest
@testable import Luna

final class TrafficLightLayoutTests: XCTestCase {

    private let system = TrafficLightMetrics(
        natural: [CGPoint(x: 9, y: 9), CGPoint(x: 32, y: 9), CGPoint(x: 55, y: 9)],
        buttonHeight: 14,
        titlebarHeight: 32
    )
    private let inset: CGFloat = 18

    private func origins(
        _ state: ChromeState,
        system: TrafficLightMetrics? = nil,
        inset: CGFloat? = nil
    ) -> [CGPoint]? {
        TrafficLightLayout.origins(
            for: state,
            system: system ?? self.system,
            inset: inset ?? self.inset
        )
    }

    func testSidebarPlacesAllThreeButtonsFromTheLeadingInset() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280)))
        XCTAssertEqual(placed.map(\.x), [18, 41, 64])
    }

    /// The reason the parameter is one number instead of two: the reference
    /// insets the lights equally from the window's leading and top edges, and
    /// 8 pt left against 18 pt top is the asymmetry that got this rewritten.
    func testTheLeadingAndTopInsetsAreTheSame() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280)))
        let fromTop = system.titlebarHeight - placed[0].y - system.buttonHeight
        XCTAssertEqual(fromTop, placed[0].x)
    }

    func testKeepsTheSystemSpacingRatherThanInventingItsOwn() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280)))
        let placedGaps = zip(placed, placed.dropFirst()).map { $1.x - $0.x }
        let naturalGaps = zip(system.natural, system.natural.dropFirst()).map { $1.x - $0.x }
        XCTAssertEqual(placedGaps, naturalGaps)
    }

    /// The whole point of the class: collapsing the sidebar or switching layout
    /// must not move the lights. Both surfaces are a `topBarHeight` row at the
    /// window's top-left, so the frames are identical — no jump to animate.
    func testPlacementIsIdenticalInEveryChromeLayout() throws {
        let sidebar = try XCTUnwrap(origins(.sidebar(width: 280)))
        XCTAssertEqual(try XCTUnwrap(origins(.sidebarCollapsed)), sidebar)
        XCTAssertEqual(try XCTUnwrap(origins(.topBar)), sidebar)
    }

    func testSidebarWidthDoesNotMoveTheLights() throws {
        let narrow = try XCTUnwrap(origins(.sidebar(width: Tokens.Metric.sidebarWidth.min)))
        let wide = try XCTUnwrap(origins(.sidebar(width: Tokens.Metric.sidebarWidth.max)))
        XCTAssertEqual(narrow, wide)
    }

    /// In fullscreen the system owns the buttons — it slides them into the menu
    /// bar overlay. `nil` means "do not touch", and the manager obeys it.
    func testFullscreenIsSystemOwned() {
        XCTAssertNil(origins(.fullscreen))
    }

    /// A button hung below the titlebar still draws (nothing clips) but stops
    /// hit-testing, which is a traffic light you can see and cannot click.
    func testNeverPlacesAButtonOutsideTheTitlebar() throws {
        for candidate in stride(from: CGFloat(-10), through: 120, by: 2) {
            let placed = try XCTUnwrap(origins(.sidebar(width: 280), inset: candidate))
            for origin in placed {
                XCTAssertGreaterThanOrEqual(origin.y, 0, "inset \(candidate)")
                XCTAssertLessThanOrEqual(
                    origin.y + system.buttonHeight,
                    system.titlebarHeight,
                    "inset \(candidate)"
                )
            }
        }
    }

    /// The shipping inset fits inside the measured macOS 26 titlebar with
    /// nothing to clamp, so the lights land exactly where they were asked to.
    func testTheShippingInsetIsNotClamped() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280), inset: Tokens.Metric.trafficLightInset))
        XCTAssertEqual(
            system.titlebarHeight - placed[0].y - system.buttonHeight,
            Tokens.Metric.trafficLightInset
        )
    }

    func testNoButtonsMeansNoLayout() {
        var empty = system
        empty.natural = []
        XCTAssertNil(origins(.sidebar(width: 280), system: empty))
    }
}

/// The card's half of the geometry (UI-SPEC §3.6 vs §4): inset and floating in
/// the sidebar layout, flush and full-bleed under the top bar.
final class ContentCardGeometryTests: XCTestCase {

    private let row = Tokens.Metric.topBarHeight

    /// The sidebar is the only thing that insets the page. Everything else is a
    /// window edge, and the reference runs the page flush to all three.
    func testSidebarLayoutInsetsTheCardFromTheSidebarAndNothingElse() {
        let insets = ChromeState.sidebar(width: 280).cardInsets
        XCTAssertEqual(insets.left, 280)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.right, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertTrue(ChromeState.sidebar(width: 280).cardIsInset)
    }

    func testTheSidebarEdgeTracksEverySidebarWidth() {
        for width in [Tokens.Metric.sidebarWidth.min, 280, Tokens.Metric.sidebarWidth.max] {
            XCTAssertEqual(ChromeState.sidebar(width: width).cardInsets.left, width)
        }
    }

    /// §4: "Content is flush full-bleed below it — no inset card, no gap."
    func testTopBarLayoutIsFlushFullBleed() {
        let insets = ChromeState.topBar.cardInsets
        XCTAssertEqual(insets.top, row)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertFalse(ChromeState.topBar.cardIsInset)
    }

    /// With no sidebar the lights still need their row, or they sit on the page.
    /// Nothing is rounded there: every edge the page has is a window edge.
    func testCollapsedSidebarKeepsTheControlRowClear() {
        let insets = ChromeState.sidebarCollapsed.cardInsets
        XCTAssertEqual(insets.top, row)
        XCTAssertEqual(insets.left, 0)
        XCTAssertFalse(ChromeState.sidebarCollapsed.cardIsInset)
    }

    func testFullscreenFillsTheWindow() {
        let insets = ChromeState.fullscreen.cardInsets
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertFalse(ChromeState.fullscreen.cardIsInset)
    }
}
