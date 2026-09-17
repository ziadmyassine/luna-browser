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
    private let row: CGFloat = 52
    private let leading: CGFloat = 8

    private func origins(_ state: ChromeState, system: TrafficLightMetrics? = nil) -> [CGPoint]? {
        TrafficLightLayout.origins(
            for: state,
            system: system ?? self.system,
            controlRowHeight: row,
            leading: leading
        )
    }

    func testSidebarPlacesAllThreeButtonsFromTheLeadingInset() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280)))
        XCTAssertEqual(placed.map(\.x), [8, 31, 54])
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
        for rowHeight in stride(from: CGFloat(20), through: 120, by: 4) {
            let placed = try XCTUnwrap(TrafficLightLayout.origins(
                for: .sidebar(width: 280),
                system: system,
                controlRowHeight: rowHeight,
                leading: leading
            ))
            for origin in placed {
                XCTAssertGreaterThanOrEqual(origin.y, 0, "row \(rowHeight)")
                XCTAssertLessThanOrEqual(
                    origin.y + system.buttonHeight,
                    system.titlebarHeight,
                    "row \(rowHeight)"
                )
            }
        }
    }

    /// At the measured macOS 26 sizes the clamp costs 1 pt: the ideal centre of
    /// a 52 pt row is 26 pt from the top, the clamp lands at 25 pt.
    func testClampCostsAtMostOnePointAtTheShippingSizes() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280)))
        let centreFromTop = system.titlebarHeight - placed[0].y - system.buttonHeight / 2
        XCTAssertEqual(centreFromTop, row / 2, accuracy: 1)
    }

    /// When the titlebar is tall enough there is no clamp and the lights are
    /// exactly centred — this is what the clamp degrades from.
    func testCentresExactlyWhenTheTitlebarIsAsTallAsTheRow() throws {
        var tall = system
        tall.titlebarHeight = row
        let placed = try XCTUnwrap(origins(.sidebar(width: 280), system: tall))
        XCTAssertEqual(placed[0].y, (row - system.buttonHeight) / 2)
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

    private let gap = Tokens.Metric.contentCardGap
    private let row = Tokens.Metric.topBarHeight

    func testSidebarLayoutInsetsTheCardFromTheSidebarAndEveryWindowEdge() {
        let insets = ChromeState.sidebar(width: 280).cardInsets
        XCTAssertEqual(insets.left, 280 + gap)
        XCTAssertEqual(insets.top, gap)
        XCTAssertEqual(insets.right, gap)
        XCTAssertEqual(insets.bottom, gap)
        XCTAssertTrue(ChromeState.sidebar(width: 280).cardIsInset)
    }

    func testTheGapSurvivesEverySidebarWidth() {
        for width in [Tokens.Metric.sidebarWidth.min, 280, Tokens.Metric.sidebarWidth.max] {
            XCTAssertEqual(ChromeState.sidebar(width: width).cardInsets.left, width + gap)
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
    func testCollapsedSidebarKeepsTheControlRowClear() {
        let insets = ChromeState.sidebarCollapsed.cardInsets
        XCTAssertEqual(insets.top, row)
        XCTAssertEqual(insets.left, gap)
        XCTAssertTrue(ChromeState.sidebarCollapsed.cardIsInset)
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
