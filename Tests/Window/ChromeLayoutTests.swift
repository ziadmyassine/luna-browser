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
        let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading)))
        XCTAssertEqual(placed.map(\.x), [18, 41, 64])
    }

    /// The reason the parameter is one number instead of two: the reference
    /// insets the lights equally from the window's leading and top edges, and
    /// 8 pt left against 18 pt top is the asymmetry that got this rewritten.
    func testTheLeadingAndTopInsetsAreTheSame() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading)))
        let fromTop = system.titlebarHeight - placed[0].y - system.buttonHeight
        XCTAssertEqual(fromTop, placed[0].x)
    }

    func testKeepsTheSystemSpacingRatherThanInventingItsOwn() throws {
        let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading)))
        let placedGaps = zip(placed, placed.dropFirst()).map { $1.x - $0.x }
        let naturalGaps = zip(system.natural, system.natural.dropFirst()).map { $1.x - $0.x }
        XCTAssertEqual(placedGaps, naturalGaps)
    }

    /// The whole point of the class: collapsing the sidebar or switching layout
    /// must not move the lights. Both surfaces are a `topBarHeight` row at the
    /// window's top-left, so the frames are identical — no jump to animate.
    func testPlacementIsIdenticalInEveryChromeLayout() throws {
        let sidebar = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading)))
        XCTAssertEqual(try XCTUnwrap(origins(.sidebarCollapsed(edge: .leading))), sidebar)
        XCTAssertEqual(try XCTUnwrap(origins(.topBar)), sidebar)
    }

    func testSidebarWidthDoesNotMoveTheLights() throws {
        let narrow = try XCTUnwrap(origins(.sidebar(width: Tokens.Metric.sidebarWidth.min, edge: .leading)))
        let wide = try XCTUnwrap(origins(.sidebar(width: Tokens.Metric.sidebarWidth.max, edge: .leading)))
        XCTAssertEqual(narrow, wide)
    }

    /// §3.6's page fullscreen: the page has the window and there is no chrome
    /// for the lights to sit in, so nobody places them. `nil` means "do not
    /// touch", and the manager obeys it.
    ///
    /// Window fullscreen — the green button — is a different thing and keeps
    /// its `.sidebar` state throughout; see `TrafficLightStrip`.
    func testPageFullscreenIsSystemOwned() {
        XCTAssertNil(origins(.fullscreen))
    }

    /// The container is measured, not named. Fullscreen takes AppKit's
    /// titlebar out of the window and the lights move into a strip of Luna's
    /// own; what has to survive the move is the distance from the window's top
    /// edge, because that is what "the same position as windowed" means. So the
    /// inset is measured down from whatever container is passed, whatever its
    /// height, and the x placement does not depend on it at all.
    func testMeasuresFromItsContainersTopEdgeWhateverThatContainerIs() throws {
        let titlebar = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading)))
        for height in [system.titlebarHeight, 52, 900] as [CGFloat] {
            var container = system
            container.titlebarHeight = height
            let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading), system: container))
            XCTAssertEqual(placed.map(\.x), titlebar.map(\.x), "height \(height)")
            for origin in placed {
                XCTAssertEqual(height - origin.y - container.buttonHeight, inset, "height \(height)")
            }
        }
    }

    /// A button hung below the titlebar still draws (nothing clips) but stops
    /// hit-testing, which is a traffic light you can see and cannot click.
    func testNeverPlacesAButtonOutsideTheTitlebar() throws {
        for candidate in stride(from: CGFloat(-10), through: 120, by: 2) {
            let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading), inset: candidate))
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
        let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading), inset: Tokens.Metric.trafficLightInset))
        XCTAssertEqual(
            system.titlebarHeight - placed[0].y - system.buttonHeight,
            Tokens.Metric.trafficLightInset
        )
    }

    /// **Fullscreen has to land the lights on the line the titlebar lands them
    /// on.** In fullscreen the buttons move into a strip of Luna's own, and
    /// `origins` clamps the inset into whatever container it is given — so a
    /// strip shorter than the inset plus a button would put the lights higher
    /// than windowed, which is the only way the two states can disagree. The
    /// titlebar height the strip stands in for is read before the window has
    /// ever been on screen, so the strip takes the larger of the two.
    func testTheFullscreenStripAlwaysHoldsTheWholeInset() throws {
        let inset = Tokens.Metric.trafficLightInset
        let windowed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading), inset: inset))
        for measured in stride(from: CGFloat(0), through: 40, by: 2) {
            var strip = system
            strip.titlebarHeight = TrafficLightLayoutManager.stripHeight(
                titlebar: measured,
                buttonHeight: system.buttonHeight,
                inset: inset
            )
            let placed = try XCTUnwrap(origins(.sidebar(width: 280, edge: .leading), system: strip, inset: inset))
            XCTAssertEqual(placed.map(\.x), windowed.map(\.x), "titlebar measured \(measured)")
            for origin in placed {
                XCTAssertEqual(
                    strip.titlebarHeight - origin.y - strip.buttonHeight,
                    inset,
                    "titlebar measured \(measured)"
                )
            }
        }
    }

    func testNoButtonsMeansNoLayout() {
        var empty = system
        empty.natural = []
        XCTAssertNil(origins(.sidebar(width: 280, edge: .leading), system: empty))
    }
}

/// The card's half of the geometry (UI-SPEC §3.6 vs §4): inset and floating in
/// the sidebar layout, flush and full-bleed under the top bar.
final class ContentCardGeometryTests: XCTestCase {

    private let row = Tokens.Metric.topBarHeight

    /// The sidebar is the only thing that insets the page. Everything else is a
    /// window edge, and the reference runs the page flush to all three.
    func testSidebarLayoutInsetsTheCardFromTheSidebarAndNothingElse() {
        let insets = ChromeState.sidebar(width: 280, edge: .leading).cardInsets
        XCTAssertEqual(insets.left, 280)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.right, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertTrue(ChromeState.sidebar(width: 280, edge: .leading).cardIsInset)
    }

    /// The mirror image, and the whole of what "sidebar on the right" is: the
    /// page is inset from the trailing edge instead of the leading one, and the
    /// corners it rounds move with it.
    func testATrailingSidebarInsetsTheOtherEdge() {
        let state = ChromeState.sidebar(width: 280, edge: .trailing)
        XCTAssertEqual(state.cardInsets.right, 280)
        XCTAssertEqual(state.cardInsets.left, 0)
        XCTAssertEqual(state.cardInsets.top, 0)
        XCTAssertEqual(state.cardInsets.bottom, 0)
        XCTAssertEqual(state.cardInsetEdge, .trailing)
    }

    /// The two sides take the same room, on opposite edges. A test rather than
    /// an assumption because the insets are written out per case: a copy-paste
    /// that left `left:` in the trailing branch would put the page under the
    /// sidebar and look like a z-order bug.
    func testBothSidesInsetTheSameAmount() {
        for width in [Tokens.Metric.sidebarWidth.min, 280, Tokens.Metric.sidebarWidth.max] {
            let leading = ChromeState.sidebar(width: width, edge: .leading).cardInsets
            let trailing = ChromeState.sidebar(width: width, edge: .trailing).cardInsets
            XCTAssertEqual(leading.left, trailing.right, "width \(width)")
            XCTAssertEqual(leading.right, trailing.left, "width \(width)")
        }
    }

    func testTheSidebarEdgeTracksEverySidebarWidth() {
        for width in [Tokens.Metric.sidebarWidth.min, 280, Tokens.Metric.sidebarWidth.max] {
            XCTAssertEqual(ChromeState.sidebar(width: width, edge: .leading).cardInsets.left, width)
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

    /// Hiding the sidebar gives the page the whole window — no reserved row for
    /// the traffic lights, which keep their own place in the titlebar and float
    /// over the page. Nothing is rounded: every edge the page has is a window
    /// edge.
    func testCollapsedSidebarFillsTheWindow() {
        let insets = ChromeState.sidebarCollapsed(edge: .leading).cardInsets
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertFalse(ChromeState.sidebarCollapsed(edge: .leading).cardIsInset)
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

// MARK: - §8.2a's corner fill

/// The two notches `ContentCardView`'s rounded leading corners leave, which
/// `SpaceCornerFillView` paints the Space's colour into.
///
/// Geometry, asserted rather than eyeballed — the same reason `cardInsets` and
/// `TrafficLightLayout` are pure functions. Getting this shape wrong does not
/// crash; it lays a tinted stripe down the edge of the page, which is the exact
/// failure the mask exists to prevent.
@MainActor
final class SpaceCornerFillTests: XCTestCase {

    private let bounds = NSRect(x: 0, y: 0, width: 305, height: 720)
    private let column: CGFloat = 280

    private var path: CGPath {
        SpaceCornerFillView.notches(in: bounds, besideColumnOf: column)
    }

    /// Nothing to the left of the sidebar's trailing edge. That region is
    /// already carrying the sidebar's own wash; painting it here as well would
    /// be 16 % laid over 16 %, and the column would come up darker than the
    /// notches it is supposed to match.
    func testTheFillNeverReachesBackOverTheSidebar() {
        XCTAssertGreaterThanOrEqual(path.boundingBox.minX, column - 0.001)
    }

    /// And nothing beyond the corner: the fill is two corners, not a stripe
    /// down the page's leading edge.
    func testTheFillStopsAtTheCornerRadius() {
        XCTAssertLessThanOrEqual(
            path.boundingBox.maxX,
            column + Tokens.Metric.contentCardRadius + 0.001,
            "the fill ran past the card's corner and onto the page"
        )
    }

    /// One notch at the top and one at the bottom, each exactly as tall as the
    /// radius — the middle of the card's leading edge is square and needs none.
    func testThereIsANotchAtEachEndAndNothingBetween() {
        let radius = Tokens.Metric.contentCardRadius
        XCTAssertTrue(path.contains(CGPoint(x: column + 1, y: bounds.maxY - 1)), "no notch at the top")
        XCTAssertTrue(path.contains(CGPoint(x: column + 1, y: bounds.minY + 1)), "no notch at the bottom")
        XCTAssertFalse(
            path.contains(CGPoint(x: column + 1, y: bounds.midY)),
            "the straight part of the card's leading edge is being painted over"
        )
        XCTAssertFalse(
            path.contains(CGPoint(x: column + 1, y: bounds.maxY - radius - 2)),
            "the notch is taller than the corner it fills"
        )
    }

    /// The disc the card's corner takes out is not painted — that area is the
    /// card itself, and the fill sits below it.
    func testTheArcFollowsTheCardsOwnCorner() {
        let radius = Tokens.Metric.contentCardRadius
        // Well inside the quarter disc, near its centre.
        let insideTheCard = CGPoint(x: column + radius - 2, y: bounds.maxY - radius + 2)
        XCTAssertFalse(path.contains(insideTheCard), "the fill is painting under the card's corner, not around it")
    }

    /// A trailing sidebar's notches are the same two corners reflected about
    /// the window's centre line — so everything asserted above holds, measured
    /// from the other edge.
    func testTheTrailingSidebarsNotchesAreTheMirrorImage() {
        let mirrored = SpaceCornerFillView.notches(in: bounds, besideColumnOf: column, on: .trailing)
        XCTAssertLessThanOrEqual(
            mirrored.boundingBox.maxX,
            bounds.maxX - column + 0.001,
            "the fill reached back over a trailing sidebar"
        )
        XCTAssertGreaterThanOrEqual(
            mirrored.boundingBox.minX,
            bounds.maxX - column - Tokens.Metric.contentCardRadius - 0.001,
            "the fill ran past the card's corner and onto the page"
        )
        XCTAssertEqual(mirrored.boundingBox.width, path.boundingBox.width, accuracy: 0.001)
    }

    /// A window shorter than two radii has no straight edge left between the
    /// corners; the guard returns an empty path rather than two overlapping
    /// notches.
    func testAWindowTooShortForTwoCornersPaintsNothing() {
        let squat = NSRect(x: 0, y: 0, width: 305, height: Tokens.Metric.contentCardRadius)
        XCTAssertTrue(SpaceCornerFillView.notches(in: squat, besideColumnOf: column).isEmpty)
    }
}
