//
//  CommandBarOpeningTests.swift
//  LunaTests
//
//  How §9.1's bar opens out of §3.2/§3.2b's pill, which is two separate
//  promises and one of them is about time.
//
//  The shape: the first frame the window server draws is the pill's own
//  size, not the list's. That is what makes the reveal a morph rather than a
//  panel appearing and then being animated — and it is what keeps the panel's
//  expensive first composite off the animation, which is the freeze
//  reported twice.
//
//  The list: whatever the bar opens with is what it stays with. Rows that
//  land while it is opening may take a free place at the bottom and may not
//  move one that is taken, so the eight rows that faded up are still the eight
//  rows under the pointer a quarter of a second later.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarOpeningTests: XCTestCase {

    private var window: NSWindow?

    /// A pill standing where §3.2b's does, in a real window — `anchorRect` is
    /// nil for a view that is not in one, and a panel with no anchor is the
    /// floating bar, which is the case this file is not about.
    private func anchored() -> (CommandBarPanel, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.window = window
        let root = window.contentView!
        let pill = NSView(frame: NSRect(x: 390, y: 730, width: 420, height: 34))
        root.addSubview(pill)

        let results = CommandBarResultsView(frame: .zero)
        results.setResults(rows(8), selecting: nil)
        let panel = CommandBarPanel(
            frame: root.bounds,
            resultsView: results,
            anchor: CommandBarAnchor(view: pill)
        )
        root.addSubview(panel)
        return (panel, pill)
    }

    private func rows(_ count: Int) -> [CommandBarResult] {
        (0..<count).map { index in
            CommandBarResult(
                source: .history,
                title: "Result \(index)",
                subtitle: "example\(index).com",
                action: .open(URL(string: "https://example\(index).com")!),
                url: URL(string: "https://example\(index).com")!,
                symbolName: "clock"
            )
        }
    }

    /// The first thing on screen is the capsule that was clicked, at its size,
    /// with the list already behind it and clipped away.
    func testThePreparedBarIsThePillsOwnHeightAndIsVisible() {
        let (panel, _) = anchored()
        panel.prepareToOpen()
        panel.layoutSubtreeIfNeeded()

        XCTAssertEqual(panel.body.frame.height, panel.inputHeight, accuracy: 0.5)
        XCTAssertEqual(panel.body.alphaValue, 1, accuracy: 0.001, "the pill has gone; something has to be in its place")
        XCTAssertFalse(panel.isOpening, "preparing is not opening — the list may still be replaced")
    }

    /// And it grows to the list, on the list's own measurement rather than on
    /// whatever the body happened to be when the bar was prepared.
    func testItOpensToTheHeightOfTheListItEndsUpWith() {
        let (panel, _) = anchored()
        panel.prepareToOpen()
        panel.layoutSubtreeIfNeeded()
        let target = panel.inputHeight + panel.results.fittingSize.height + CommandBarMetrics.padding

        let opened = expectation(description: "the reveal finishes")
        panel.onOpened = { opened.fulfill() }
        panel.animateIn()
        XCTAssertTrue(panel.isOpening, "the list must not be replaced while this is running")
        wait(for: [opened], timeout: 2)

        panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.body.frame.height, target, accuracy: 0.5)
        XCTAssertFalse(panel.isOpening)
    }

    /// The floating bar has no pill under it, so there is nothing for a first
    /// frame to match: it keeps §6's fade, and stays invisible until it opens.
    func testTheFloatingBarIsStillInvisibleUntilItOpens() {
        let panel = CommandBarPanel(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
            resultsView: CommandBarResultsView(frame: .zero)
        )
        panel.prepareToOpen()
        XCTAssertEqual(panel.body.alphaValue, 0, accuracy: 0.001)
    }

    /// §9.7's no-reorder rule, one step earlier than the cursor: a late arrival
    /// takes a free place and never somebody else's. With eight rows showing
    /// and eight places, that means it takes none — and the list the bar opened
    /// with is the list it settles as.
    func testALateArrivalCannotMoveARowTheBarAlreadyOpenedWith() {
        let onScreen = rows(8)
        let late = rows(3).reversed() + [
            CommandBarResult(
                source: .suggestion,
                title: "late",
                subtitle: "",
                action: .open(URL(string: "https://late.example")!),
                url: URL(string: "https://late.example")!,
                symbolName: "magnifyingglass"
            )
        ]
        let merged = CommandBarRanking.appendingWithoutReordering(onScreen: onScreen, incoming: Array(late))

        XCTAssertEqual(Array(merged.prefix(onScreen.count)).map(\.id), onScreen.map(\.id))
        XCTAssertEqual(
            Array(merged.prefix(CommandBarMetrics.visibleRows)).map(\.id),
            onScreen.map(\.id),
            "a full list has no free place, so nothing visible changes at all"
        )
    }
}
