//
//  SidebarSpacePillTests.swift
//  LunaTests
//
//  §3.5's foot: the Space pill at the leading end, the dots in the middle and
//  the Downloads/History cylinder at the trailing end, on one bottom edge. The
//  pill is its whole name, as §4's is, and the dots stay in the middle unless a
//  name is too long to leave them there.
//
//  The long name is the one the fade was first reported on — 32 characters of
//  one repeated pair, the worst case §6.2's cap allows.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SidebarSpacePillTests: XCTestCase {

    private let long = "yoyooyoyoyoyyoyooyoyoyoyooyoyoyo"

    private func foot(_ name: String, width: CGFloat = 280, spaces count: Int = 3) -> SidebarUtilityBar {
        let bar = SidebarUtilityBar()
        bar.frame = NSRect(x: 0, y: 0, width: width, height: Tokens.Metric.topBarHeight)
        let made = (0..<count).map {
            Space(name: $0 == 0 ? name : "S\($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
        bar.show(spaces: made, activeSpaceID: made[0].id)
        bar.show(spaceName: name, fanOut: nil)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    private func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: Tokens.TypeScale.topBarSpaceName]).size().width
    }

    /// Leading to trailing: the Space pill, the dots, the cylinder.
    private func clusters(of bar: SidebarUtilityBar) -> [NSView] {
        bar.subviews.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Where things stand

    /// The pill is where the Profile avatar was: the first thing in the foot,
    /// a row inset from the edge, as tall as the circles.
    func testThePillLeadsTheFoot() throws {
        let bar = foot("Personal")
        let first = try XCTUnwrap(clusters(of: bar).first)
        XCTAssertTrue(first === bar.spacePill)
        XCTAssertEqual(first.frame.minX, Tokens.Metric.rowInset, accuracy: 0.5)
        XCTAssertEqual(first.frame.height, Tokens.Metric.bottomCircle.height)
    }

    /// The three share a bottom edge, and the dots carry no glass of their own.
    func testTheDotsStandOnTheButtonsBottomEdgeWithNoGlass() {
        let parts = clusters(of: foot("Personal"))
        XCTAssertEqual(parts.count, 3)
        for part in parts.dropFirst() {
            XCTAssertEqual(part.frame.minY, parts[0].frame.minY, accuracy: 0.5)
        }
        let dots = parts[1]
        XCTAssertFalse(dots.subviews.contains { $0 is GlassBackingView }, "the dots have their own glass again")
        XCTAssertEqual(dots.layer?.masksToBounds, true)
    }

    /// And across, they stay in the middle of the bar for the name Luna ships
    /// with. Not at the 220 pt floor with three Spaces: there the 56 pt strip
    /// and the 68 pt cylinder already leave the middle 2 pt short, name or not.
    func testTheShippedNameLeavesTheDotsInTheMiddle() {
        let cases: [(CGFloat, Int)] = [
            (Tokens.Metric.sidebarFootFloor, 1),
            (Tokens.Metric.sidebarWidth.default, 1),
            (Tokens.Metric.sidebarWidth.default, 3)
        ]
        for (width, count) in cases {
            let bar = foot("Personal", width: width, spaces: count)
            let dots = clusters(of: bar)[1]
            XCTAssertEqual(dots.frame.midX, bar.bounds.midX, accuracy: 1, "\(width) pt, \(count) Spaces")
        }
    }

    /// A long name moves them along rather than being cut to keep them
    /// centred, and every cluster keeps a chrome gap from the next.
    func testALongNameMovesTheDotsButNeverOntoANeighbour() {
        for name in ["P", "Personal", long] {
            let parts = clusters(of: foot(name, width: Tokens.Metric.sidebarFootFloor))
            for (left, right) in zip(parts, parts.dropFirst()) {
                XCTAssertGreaterThanOrEqual(right.frame.minX - left.frame.maxX, Tokens.Metric.chromeGap - 0.5, name)
            }
        }
    }

    // MARK: - The name

    /// A pill is sized to its name, and never thinner than the circle it
    /// replaced.
    func testThePillIsAsWideAsItsNameAndNoThinnerThanACircle() {
        let short = foot("P").spacePill
        XCTAssertEqual(short.frame.width, Tokens.Metric.bottomCircle.width)
        let named = foot("Personal").spacePill
        XCTAssertEqual(
            named.frame.width,
            ceil(2 * Tokens.Metric.sidebarSpacePillPad + textWidth("Personal")),
            accuracy: 1
        )
    }

    /// A box cut to what the field reports is 4 pt short of what it draws,
    /// because the cell keeps 2 pt either side and counts neither — "Personal"
    /// once came out "Persona".
    func testAShortNameKeepsItsLastLetterOutOfTheCellsPadding() {
        let pill = foot("Personal").spacePill
        let pad = SidebarSpacePill.padding(of: pill.label)
        XCTAssertGreaterThan(pad, 0, "the cell has stopped padding — the offset in placeContents is now a shift")
        XCTAssertEqual(pill.label.frame.minX + pad, 0, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(pill.label.frame.maxX - pad, pill.clip.frame.width - 0.5)
        XCTAssertNil(pill.clip.layer?.mask)
    }

    /// The name Luna ships with is drawn whole in the narrowest column §1
    /// allows, where a new user has one Space. It was faded there once, to
    /// keep the dots centred.
    func testTheShippedNameFitsAtTheFloor() {
        let pill = foot("Personal", width: Tokens.Metric.sidebarFootFloor, spaces: 1).spacePill
        XCTAssertNil(pill.clip.layer?.mask, "\"Personal\" does not fit the narrowest column")
    }

    /// A name longer than the room stops at the room and fades, and a wider
    /// column shows more of it.
    func testALongNameFadesAndAWiderColumnShowsMore() {
        let narrow = foot(long, width: 280).spacePill
        let wide = foot(long, width: Tokens.Metric.sidebarWidth.max).spacePill
        XCTAssertNotNil(narrow.clip.layer?.mask)
        XCTAssertGreaterThan(wide.clip.frame.width, narrow.clip.frame.width)
        XCTAssertLessThanOrEqual(
            narrow.clip.frame.maxX,
            narrow.bounds.width - Tokens.Metric.sidebarSpacePillPad + 0.5
        )
    }
}
