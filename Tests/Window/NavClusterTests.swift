//
//  NavClusterTests.swift
//  LunaTests
//
//  §3.1's back/forward capsule, on both the sidebar's row and §3.2b's bar.
//

import XCTest
@testable import Luna

/// §3.2b's history control, which is the one piece of chrome in Luna that
/// changes shape rather than state.
///
/// Forward is unreachable on the great majority of pages, so a permanently
/// dimmed chevron beside a live one would be a control that spends its whole
/// life saying no. It arrives instead — and the thing that must not happen when
/// it does is the chevron the user is aiming at moving out from under them.
@MainActor
final class NavClusterTests: XCTestCase {

    private func cluster(canGoForward: Bool) -> NavCluster {
        let nav = NavCluster()
        nav.update(canGoBack: true, canGoForward: canGoForward)
        nav.frame = NSRect(origin: .zero, size: nav.intrinsicContentSize)
        nav.layoutSubtreeIfNeeded()
        return nav
    }

    private func chevrons(of nav: NavCluster) -> [GlassButton] {
        nav.subviews.compactMap { $0 as? GlassButton }
    }

    /// Everything the capsule holds except the material itself, which is the
    /// one thing that *is* supposed to resize with it.
    private func contents(of nav: NavCluster) -> [NSRect] {
        nav.subviews.filter { !NSStringFromClass(type(of: $0)).contains("GlassBacking") }.map(\.frame)
    }

    /// One circle until there is somewhere to go forward to, then a capsule.
    func testItIsACircleUntilThereIsAForwardToGoTo() {
        XCTAssertEqual(cluster(canGoForward: false).intrinsicContentSize.width, Tokens.Metric.sidebarCircle.width)
        XCTAssertEqual(
            cluster(canGoForward: true).intrinsicContentSize.width,
            Tokens.Metric.sidebarCircle.width * 2
        )
    }

    /// Hidden rather than dimmed, and hidden for good: a view at alpha 0 goes
    /// on hit-testing, so a faded chevron would eat clicks in a capsule it is
    /// no longer part of.
    func testForwardIsAbsentRatherThanDimmedWhenThereIsNoneToGoTo() {
        let shut = cluster(canGoForward: false)
        XCTAssertEqual(chevrons(of: shut).filter { !$0.isHidden }.count, 1)
        let open = cluster(canGoForward: true)
        XCTAssertEqual(chevrons(of: open).filter { !$0.isHidden }.count, 2)
    }

    /// **Back does not move when forward arrives.** The capsule grows out of
    /// its trailing end — the alternative, two halves of the bounds, slides the
    /// button the pointer is already on.
    func testBackKeepsItsPlaceWhenTheCapsuleGrows() {
        let nav = NavCluster()
        nav.update(canGoBack: true, canGoForward: false)
        nav.frame = NSRect(origin: .zero, size: nav.intrinsicContentSize)
        nav.layoutSubtreeIfNeeded()
        let before = try? XCTUnwrap(chevrons(of: nav).first).frame

        nav.update(canGoBack: true, canGoForward: true)
        nav.frame = NSRect(origin: .zero, size: nav.intrinsicContentSize)
        nav.layoutSubtreeIfNeeded()
        XCTAssertEqual(chevrons(of: nav).first?.frame, before)
    }

    /// The divider is the reference's, and it stops short of the ends: a rule
    /// that runs the full height cuts the capsule in two rather than separating
    /// the glyphs.
    func testTheDividerSeparatesTheGlyphsWithoutCuttingTheCapsule() throws {
        let nav = cluster(canGoForward: true)
        let divider = try XCTUnwrap(nav.subviews.first { !($0 is GlassButton) && !$0.isHidden && $0.frame.width <= 1 })
        XCTAssertEqual(divider.frame.midX, nav.bounds.midX, accuracy: 1)
        XCTAssertGreaterThan(divider.frame.minY, nav.bounds.minY)
        XCTAssertLessThan(divider.frame.maxY, nav.bounds.maxY)
    }

    /// **And nothing inside moves when it shrinks either.** The trailing edge
    /// is the only thing that travels in this morph, in both directions. Laid
    /// out against the bounds, a shrink re-reads them at the final width on its
    /// first frame — the divider jumping into the middle of back, the forward
    /// chevron sliding left across it as it fades.
    func testTheGlyphsStandStillWhileTheCapsuleCloses() throws {
        let nav = cluster(canGoForward: true)
        let before = contents(of: nav)

        nav.update(canGoBack: true, canGoForward: false)
        nav.frame = NSRect(origin: .zero, size: nav.intrinsicContentSize)
        nav.layoutSubtreeIfNeeded()
        XCTAssertEqual(contents(of: nav), before, "something inside the capsule moved as it closed")
    }

    /// Back still dims where it always has: it is on every page, and is dimmed
    /// on the first one, so the eye learns where it is.
    func testBackDimsRatherThanLeaving() {
        let nav = NavCluster()
        nav.update(canGoBack: false, canGoForward: false)
        let back = chevrons(of: nav).first
        XCTAssertEqual(back?.isHidden, false)
        XCTAssertEqual(back?.isEnabled, false)
    }
}
