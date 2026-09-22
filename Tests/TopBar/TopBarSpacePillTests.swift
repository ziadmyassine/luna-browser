//
//  TopBarSpacePillTests.swift
//  LunaTests
//
//  §4's Space cylinder: the two arrows, and what they mean at the ends of the
//  run.
//
//  The arrows are the whole of what §3.5's dot strip offered that a name alone
//  does not — a Space one click away — so the thing worth asserting is that
//  they stop at the ends rather than walking off them. The pop the name plays
//  on a switch is a fifth of a second of spring and is not a claim a test can
//  make; what it stands on is `show(spaces:activeSpaceID:)` noticing the Space
//  changed, which is asserted here by what the arrows do afterwards.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarSpacePillTests: XCTestCase {

    private func spaces(_ count: Int) -> [Space] {
        (0 ..< count).map {
            Space(name: "Space \($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
    }

    private func pill(_ spaces: [Space], at index: Int) -> TopBarSpacePill {
        let pill = TopBarSpacePill()
        pill.show(spaces: spaces, activeSpaceID: spaces[index].id)
        pill.frame = NSRect(origin: .zero, size: pill.intrinsicContentSize)
        pill.layoutSubtreeIfNeeded()
        return pill
    }

    private func arrow(_ pill: TopBarSpacePill, label: String) throws -> TopBarButton {
        try XCTUnwrap(
            pill.subviews.compactMap { $0 as? TopBarButton }.first { $0.accessibilityLabel() == label }
        )
    }

    func testTheArrowsStopAtEitherEndOfTheRun() throws {
        let run = spaces(3)

        let first = pill(run, at: 0)
        XCTAssertFalse(try arrow(first, label: "Previous Space").isEnabled)
        XCTAssertTrue(try arrow(first, label: "Next Space").isEnabled)

        let middle = pill(run, at: 1)
        XCTAssertTrue(try arrow(middle, label: "Previous Space").isEnabled)
        XCTAssertTrue(try arrow(middle, label: "Next Space").isEnabled)

        let last = pill(run, at: 2)
        XCTAssertTrue(try arrow(last, label: "Previous Space").isEnabled)
        XCTAssertFalse(try arrow(last, label: "Next Space").isEnabled)
    }

    /// One Space is not a run, and neither arrow may offer to leave it.
    func testASingleSpaceHasNowhereToGo() throws {
        let only = pill(spaces(1), at: 0)
        XCTAssertFalse(try arrow(only, label: "Previous Space").isEnabled)
        XCTAssertFalse(try arrow(only, label: "Next Space").isEnabled)
    }

    func testEachArrowAsksForTheSpaceBesideThisOne() throws {
        let run = spaces(3)
        let pill = pill(run, at: 1)
        var asked: [UUID] = []
        pill.onSwitch = { asked.append($0) }

        try arrow(pill, label: "Previous Space").performClick(nil)
        try arrow(pill, label: "Next Space").performClick(nil)

        XCTAssertEqual(asked, [run[0].id, run[2].id])
    }

    /// §21.1: the control is icon-and-word, and the word is the Space's name,
    /// so the group has to say which Space it is standing in.
    func testTheControlNamesTheSpaceItIsShowing() {
        let run = spaces(2)
        let pill = pill(run, at: 1)
        XCTAssertEqual(pill.accessibilityLabel(), "Space: Space 1")
    }
}
