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

/// What the capsule's second half costs the column it sits in.
///
/// §3.1's head is `[lights] [toggle] ··· [back·forward] [reload]`, and the
/// cluster is pinned to the trailing edge — so every point it grows is a point
/// its leading end travels towards the toggle. At the old 220 pt minimum the
/// two overlapped the moment there was a forward to go to, which is what Martin
/// photographed. The minimum is arithmetic (see `Metric.sidebarWidth`), and
/// this is that arithmetic run against the real row.
@MainActor
final class SidebarHeadRoomTests: XCTestCase {

    private var window: NSWindow?

    /// In a real window, because the row leaves the traffic lights' corner
    /// clear and there are no lights to clear without one.
    private func head(width: CGFloat, canGoForward: Bool) -> SidebarControlRow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        self.window = window
        let row = SidebarControlRow()
        row.frame = NSRect(x: 0, y: 748, width: width, height: Tokens.Metric.topBarHeight)
        window.contentView?.addSubview(row)
        row.update(canGoBack: true, canGoForward: canGoForward, isLoading: false)
        row.layoutSubtreeIfNeeded()
        return row
    }

    /// Leading to trailing: the toggle, then the cluster, then reload.
    private func parts(of row: SidebarControlRow) -> [NSRect] {
        row.subviews.filter { !$0.isHidden }.map(\.frame).sorted { $0.minX < $1.minX }
    }

    /// **Nothing on the head touches at the narrowest the column can be
    /// dragged**, with the capsule at its widest. This is the whole of the
    /// change: the same row at 220 has the capsule 22 pt inside the toggle.
    ///
    /// The bar is `controlPairGap` rather than `chromeGap`, because that is the
    /// floor the minimum was chosen against — the cluster and reload sit that
    /// close on purpose, and nothing on this row should be closer than the pair
    /// that is deliberately tight.
    func testTheHeadFitsAtTheMinimumWidthWithForwardShowing() throws {
        let row = head(width: Tokens.Metric.sidebarWidth.min, canGoForward: true)
        let frames = parts(of: row)
        XCTAssertEqual(frames.count, 3)
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                right.minX - left.maxX,
                Tokens.Metric.controlPairGap,
                "two of the head's controls are closer than the tight pair"
            )
        }
    }

    /// And the cluster still ends where it always has — at the trailing inset,
    /// one `controlPairGap` short of reload. It grows leftwards into the room
    /// the new minimum is there to keep clear.
    func testTheCapsuleGrowsIntoTheRoomRatherThanOffTheEnd() throws {
        let row = head(width: Tokens.Metric.sidebarWidth.min, canGoForward: true)
        let frames = parts(of: row)
        let reload = try XCTUnwrap(frames.last)
        let nav = frames[1]
        XCTAssertEqual(reload.maxX, row.bounds.maxX - Tokens.Metric.rowInset, accuracy: 0.5)
        XCTAssertEqual(reload.minX - nav.maxX, Tokens.Metric.controlPairGap, accuracy: 0.5)
        XCTAssertEqual(nav.width, Tokens.Metric.sidebarCircle.width * 2, accuracy: 0.5)
    }
}
