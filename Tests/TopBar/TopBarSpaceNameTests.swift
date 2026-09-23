//
//  TopBarSpaceNameTests.swift
//  LunaTests
//
//  §4's Space name: what it says, and when its dots come out.
//
//  The dots are hidden at rest and out under the pointer or a lift, and a drop
//  must never land on a dot that is not showing — that is the one claim here a
//  screenshot could get wrong without looking wrong. The pop the name plays on
//  a switch is a fifth of a second of spring and is not a claim a test can make.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarSpaceNameTests: XCTestCase {

    private func spaces(_ count: Int) -> [Space] {
        (0 ..< count).map {
            Space(name: "Space \($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
    }

    private func name(_ spaces: [Space], at index: Int) -> TopBarSpaceName {
        let name = TopBarSpaceName()
        name.show(spaces: spaces, activeSpaceID: spaces[index].id)
        name.frame = NSRect(origin: .zero, size: name.intrinsicContentSize)
        name.layoutSubtreeIfNeeded()
        return name
    }

    /// §21.1: the control is a word, and the word is the Space's name, so the
    /// group has to say which Space it is standing in.
    func testTheControlNamesTheSpaceItIsShowing() {
        XCTAssertEqual(name(spaces(2), at: 1).accessibilityLabel(), "Space: Space 1")
    }

    func testTheDotsAreOutOnlyWhileAimedAt() {
        let name = name(spaces(3), at: 0)
        XCTAssertFalse(name.showsDots)
        XCTAssertEqual(name.dots.alphaValue, 0)
        name.isAimedAt = true
        XCTAssertTrue(name.showsDots)
        name.isAimedAt = false
        XCTAssertFalse(name.showsDots)
    }

    /// The name and its dots are a size down from the column's.
    func testTheNameAndDotsAreASizeDown() throws {
        let name = name(spaces(2), at: 0)
        XCTAssertLessThan(Tokens.TypeScale.topBarSpaceName.pointSize, Tokens.TypeScale.sidebarRow.pointSize)
        let dot = try XCTUnwrap(name.dots.subviews.compactMap { $0 as? SpaceDotView }.first)
        XCTAssertLessThan(dot.scale, 1)
    }

    /// A lift over a hidden dot has nowhere visible to land, so it is not a
    /// landing; over a showing one it is that dot's Space.
    func testADropFindsASpaceOnlyOnADotThatIsShowing() throws {
        let run = spaces(3)
        let name = name(run, at: 0)
        let dot = try XCTUnwrap(name.dots.subviews.compactMap { $0 as? SpaceDotView }.last)
        let centre = name.convert(NSPoint(x: dot.frame.midX, y: dot.frame.midY), from: name.dots)
        XCTAssertNil(name.space(at: centre, from: name))
        name.isAimedAt = true
        XCTAssertEqual(name.space(at: centre, from: name), run[2].id)
    }

    /// The name is as wide as its word or its dots, whichever is wider, so
    /// the dots never hang out past the plate.
    func testTheNameIsNeverNarrowerThanItsDots() {
        let many = name(spaces(3), at: 0)
        XCTAssertGreaterThan(many.dotsWidth, 0)
        XCTAssertGreaterThanOrEqual(many.intrinsicContentSize.width, many.dotsWidth + TopBarMetrics.gap * 2)
    }
}
