//
//  SidebarWidthFloorTests.swift
//  LunaTests
//
//  How narrow §3.7's handle may drag the column, which is not one number.
//
//  §1's 250 is §3.1's arithmetic — the head with the traffic lights to clear
//  and its three circles in it — and that head is only in the column in one of
//  the four combinations `Settings.chromeLayout` and `Settings.searchBarPlacement`
//  make. The other three stand on §3.5's foot instead, at 220.
//
//  `SidebarHeadRoomTests` is the other half: the head's arithmetic run against
//  the real row at both floors. This file is the foot's, and the resolution
//  between the two.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarWidthFloorTests: XCTestCase {

    private var storedPlacement: SearchBarPlacement!

    override func setUp() {
        super.setUp()
        storedPlacement = Settings.searchBarPlacement
    }

    override func tearDown() {
        Settings.searchBarPlacement = storedPlacement
        super.tearDown()
    }

    // MARK: - Which floor applies

    /// The one case §1's minimum is for, and the reason it is not simply 220.
    func testALeadingColumnWithThePillInItKeepsTheWideFloor() {
        let span = Settings.sidebarWidth(searchBarOnPage: false, edge: .leading)
        XCTAssertEqual(span.min, Tokens.Metric.sidebarWidth.min)
    }

    /// §3.2b takes the pill and §3.1's three circles with it, leaving a row
    /// that holds nothing but the lights' corner.
    func testThePillOnThePageDropsTheFloorToTheFoots() {
        let span = Settings.sidebarWidth(searchBarOnPage: true, edge: .leading)
        XCTAssertEqual(span.min, Tokens.Metric.sidebarFootFloor)
    }

    /// And a trailing column does not contain the lights to begin with, so its
    /// head is 86 pt cheaper whether or not the pill is still in it.
    func testATrailingColumnDropsToTheSameFloorWithThePillStillInIt() {
        for onPage in [false, true] {
            let span = Settings.sidebarWidth(searchBarOnPage: onPage, edge: .trailing)
            XCTAssertEqual(span.min, Tokens.Metric.sidebarFootFloor, "pill on page: \(onPage)")
        }
    }

    /// Only the floor moves. §3.7's double-click and §1's ceiling are the same
    /// in every layout, and a `default` outside its own span would be a reset
    /// that clamps straight back out of where it reset to.
    func testTheDefaultAndTheCeilingNeverMove() {
        for onPage in [false, true] {
            for edge in SidebarEdge.allCases {
                let span = Settings.sidebarWidth(searchBarOnPage: onPage, edge: edge)
                XCTAssertEqual(span.default, Tokens.Metric.sidebarWidth.default, "\(onPage)/\(edge)")
                XCTAssertEqual(span.max, Tokens.Metric.sidebarWidth.max, "\(onPage)/\(edge)")
                XCTAssertLessThan(span.min, span.default, "\(onPage)/\(edge)")
            }
        }
    }

    /// The property the two readers are there for: the stored placement is what
    /// the live span answers from. Only §3.2b's key is flipped here — the edge
    /// is `tabsPosition`, and moving the column to the other side of the window
    /// is a whole chrome relayout to ask one arithmetic question.
    func testTheLiveSpanFollowsThePlacementSetting() {
        Settings.searchBarPlacement = .sidebar
        XCTAssertEqual(Settings.sidebarWidth.min, Tokens.Metric.sidebarWidth.min)
        Settings.searchBarPlacement = .page
        XCTAssertEqual(Settings.sidebarWidth.min, Tokens.Metric.sidebarFootFloor)
    }

    // MARK: - What the foot needs

    private func foot(width: CGFloat, spaces: Int) -> SidebarUtilityBar {
        let bar = SidebarUtilityBar()
        bar.frame = NSRect(x: 0, y: 0, width: width, height: Tokens.Metric.topBarHeight)
        let made = (0..<spaces).map {
            Space(name: "S\($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
        bar.show(spaces: made, activeSpaceID: made[0].id)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    /// Leading to trailing: the avatar, the Space strip, the cylinder.
    private func clusters(of bar: SidebarUtilityBar) -> [NSRect] {
        bar.subviews.filter { !$0.isHidden }.map(\.frame).sorted { $0.minX < $1.minX }
    }

    /// The floor itself: §3.5's three clusters have air between them at it.
    ///
    /// The Space strip stops widening at `spaceDotWindow`, so this is the
    /// widest the middle cluster ever is — a fourth Space scrolls the pill
    /// instead of growing it, which is what makes one number a floor at all.
    func testTheFootHasAirInItAtTheFloor() {
        for spaces in [Tokens.Metric.spaceDotWindow, Tokens.Metric.spaceDotWindow + 1] {
            let bar = foot(width: Tokens.Metric.sidebarFootFloor, spaces: spaces)
            let parts = clusters(of: bar)
            XCTAssertEqual(parts.count, 3, "\(spaces) Spaces")
            for (left, right) in zip(parts, parts.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    right.minX - left.maxX, Tokens.Metric.chromeGap,
                    "§3.5's clusters are closer than a chrome gap at \(spaces) Spaces"
                )
            }
        }
    }

    /// And `sidebarFootWidth` is where that air runs out, which is what makes
    /// the floor above it a choice rather than the only answer. Both gaps are
    /// exactly one `chromeGap` here and one of them is less a point below —
    /// the derived sum is right, and 220 is 30 pt of deliberate daylight.
    func testTheFootRunsOutOfAirAtTheWidthItOccupies() {
        let fits = clusters(of: foot(width: Tokens.Metric.sidebarFootWidth, spaces: Tokens.Metric.spaceDotWindow))
        for (left, right) in zip(fits, fits.dropFirst()) {
            XCTAssertEqual(right.minX - left.maxX, Tokens.Metric.chromeGap, accuracy: 0.5)
        }
        let under = clusters(of: foot(width: Tokens.Metric.sidebarFootWidth - 1, spaces: Tokens.Metric.spaceDotWindow))
        let gaps = zip(under, under.dropFirst()).map { $1.minX - $0.maxX }
        XCTAssertTrue(
            gaps.contains { $0 < Tokens.Metric.chromeGap },
            "§3.5's foot fits in less than Metric.sidebarFootWidth — the sum has moved"
        )
    }
}
