//
//  TabSwitcherTests.swift
//  LunaTests
//
//  `⌃⇥`'s rules: which tabs it offers, in what order, and what each key means
//  while it is up. The panel itself is a view over these.
//

import AppKit
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class TabSwitcherTests: XCTestCase {

    private let space = UUID()

    private func tab(_ kind: TabKind = .today, dormant: Bool = false) -> Tab {
        Tab(spaceID: space, kind: kind, url: URL(string: "https://example.com")!, isDormant: dormant)
    }

    // MARK: - Which tabs, in what order

    func testTheTabOnScreenComesFirstThenTheMostRecentlyUsed() {
        let first = tab(), second = tab(), third = tab()
        let order = TabSwitcherOrder.tabs(
            [first, second, third],
            recent: [third.id, first.id, second.id],
            live: [],
            active: first.id
        )
        XCTAssertEqual(order, [first.id, third.id, second.id])
    }

    /// Only tabs someone has been using. A pinned tab and a Favorite that
    /// were never opened are places in the sidebar, not tabs to switch to.
    func testATabNobodyOpenedIsNotOffered() {
        let used = tab(), pinned = tab(.pinned), favorite = tab(.essential)
        let order = TabSwitcherOrder.tabs(
            [favorite, pinned, used],
            recent: [used.id],
            live: [],
            active: used.id
        )
        XCTAssertEqual(order, [used.id])
    }

    /// A pinned tab that was closed stays in the sidebar, dimmed. It is closed.
    func testAClosedPinnedTabIsNotOffered() {
        let open = tab(), closed = tab(.pinned, dormant: true)
        let order = TabSwitcherOrder.tabs(
            [closed, open],
            recent: [open.id, closed.id],
            live: [closed.id],
            active: open.id
        )
        XCTAssertEqual(order, [open.id])
    }

    /// `recentTabs` spans every Space. A tab from another one is not this
    /// window's to switch to.
    func testATabFromAnotherSpaceIsNotOffered() {
        let here = tab()
        let elsewhere = Tab(spaceID: UUID(), url: URL(string: "https://example.org")!)
        let order = TabSwitcherOrder.tabs([here], recent: [elsewhere.id, here.id], live: [], active: here.id)
        XCTAssertEqual(order, [here.id])
    }

    /// A page that is loaded but was never promoted — a popup, say — is still
    /// open, and comes after the ones that were used.
    func testALoadedTabNobodyChoseComesLast() {
        let used = tab(), loaded = tab()
        let order = TabSwitcherOrder.tabs([loaded, used], recent: [used.id], live: [loaded.id], active: used.id)
        XCTAssertEqual(order, [used.id, loaded.id])
    }

    func testSteppingWrapsAtBothEnds() {
        XCTAssertEqual(TabSwitcherOrder.step(from: 0, by: 1, count: 3), 1)
        XCTAssertEqual(TabSwitcherOrder.step(from: 2, by: 1, count: 3), 0)
        XCTAssertEqual(TabSwitcherOrder.step(from: 0, by: -1, count: 3), 2)
        XCTAssertEqual(TabSwitcherOrder.step(from: 0, by: 1, count: 1), 0)
        XCTAssertEqual(TabSwitcherOrder.step(from: 0, by: 1, count: 0), 0)
    }

    // MARK: - The keys

    private func read(
        _ type: NSEvent.EventType,
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags,
        engaged: Bool
    ) -> TabSwitcherKey? {
        TabSwitcherKey.reading(type, keyCode: keyCode, modifiers: modifiers, isEngaged: engaged)
    }

    func testControlTabMovesOnAndShiftMovesBack() {
        XCTAssertEqual(read(.keyDown, 48, .control, engaged: false), .forward)
        XCTAssertEqual(read(.keyDown, 48, [.control, .shift], engaged: false), .backward)
        XCTAssertEqual(read(.keyDown, 48, .control, engaged: true), .forward)
    }

    /// `⌃` alone. A Tab with ⌘ or ⌥ added is somebody else's keystroke, and
    /// a bare Tab is the page's.
    func testOnlyControlStartsIt() {
        XCTAssertNil(read(.keyDown, 48, [], engaged: false))
        XCTAssertNil(read(.keyDown, 48, [.control, .option], engaged: false))
        XCTAssertNil(read(.keyDown, 48, [.control, .command], engaged: false))
    }

    func testLettingGoOfControlSwitches() {
        XCTAssertEqual(read(.flagsChanged, 59, [], engaged: true), .commit)
        XCTAssertEqual(read(.flagsChanged, 56, .shift, engaged: true), .commit)
        // Shift going down while ⌃ is still held is not a release.
        XCTAssertNil(read(.flagsChanged, 56, [.control, .shift], engaged: true))
        // And with no switch under way, a release means nothing.
        XCTAssertNil(read(.flagsChanged, 59, [], engaged: false))
    }

    func testTheOtherKeysWhileItIsUp() {
        XCTAssertEqual(read(.keyDown, 53, .control, engaged: true), .cancel)
        XCTAssertEqual(read(.keyDown, 36, .control, engaged: true), .commit)
        XCTAssertEqual(read(.keyDown, 123, .control, engaged: true), .backward)
        XCTAssertEqual(read(.keyDown, 124, .control, engaged: true), .forward)
        XCTAssertEqual(read(.keyDown, 0, .control, engaged: true), .swallow)
        // None of them is the switcher's when it is not up.
        XCTAssertNil(read(.keyDown, 53, [], engaged: false))
        XCTAssertNil(read(.keyDown, 0, .control, engaged: false))
    }

    // MARK: - Settings

    /// A shortcut recorded as `⌃⇥` would never fire: the switcher's monitor
    /// takes the keystroke first. So the recorder says it is taken.
    func testTheSwitcherKeysCannotBeGivenToACommand() {
        XCTAssertNotNil(KeyBindings.conflict(for: KeyBinding("\t", .control), ignoring: .nextTab))
        XCTAssertNotNil(KeyBindings.conflict(for: KeyBinding("\t", [.control, .shift]), ignoring: .nextTab))
        XCTAssertNil(KeyBindings.conflict(for: KeyBinding("\t", [.control, .option]), ignoring: .nextTab))
    }

    // MARK: - The panel

    /// The highlight is on exactly one card, and it follows `select`.
    func testOneCardIsLitAtATime() {
        let view = TabSwitcherView(items: items(3))
        view.select(1)
        XCTAssertEqual(view.cards.map(\.isSelected), [false, true, false])
        view.select(2)
        XCTAssertEqual(view.cards.map(\.isSelected), [false, false, true])
    }

    private func items(_ count: Int) -> [TabSwitcherItem] {
        (0..<count).map { TabSwitcherItem(id: UUID(), title: "Tab \($0)", favicon: nil) }
    }

    // MARK: - Two rows of five

    private func shape(_ count: Int) -> [Int] {
        let grid = TabSwitcherGrid(count: count)
        return [grid.rows, grid.columns]
    }

    func testFiveFitOnOneRowAndTheSixthStartsASecond() {
        XCTAssertEqual(shape(3), [1, 3])
        XCTAssertEqual(shape(5), [1, 5])
        XCTAssertEqual(shape(6), [2, 5])
        XCTAssertEqual(shape(10), [2, 5])
        XCTAssertEqual(shape(25), [2, 5])
    }

    /// Ten at most, the ten most recent.
    func testNoMoreThanTenAreOffered() {
        let open = (0..<14).map { _ in tab() }
        let order = TabSwitcherOrder.tabs(open, recent: open.map(\.id), live: [], active: open[0].id)
        XCTAssertEqual(order, Array(open.prefix(10)).map(\.id))
    }

    /// Row by row: the sixth card is under the first, and ↓ from the fourth
    /// of seven stays put — there is nothing under it.
    func testTheSecondRowReadsOnFromTheFirst() {
        let grid = TabSwitcherGrid(count: 7)
        XCTAssertTrue(grid.place(5) == (1, 0))
        XCTAssertEqual(grid.vertical(from: 0, down: true, count: 7), 5)
        XCTAssertEqual(grid.vertical(from: 6, down: false, count: 7), 1)
        XCTAssertEqual(grid.vertical(from: 3, down: true, count: 7), 3)
        XCTAssertEqual(TabSwitcherGrid(count: 4).vertical(from: 1, down: true, count: 4), 1)
    }

    /// The same size in every window: it does not shrink for a small one.
    func testThePanelIsNeverNarrowedByTheWindow() {
        let metrics = TabSwitcherMetrics.self
        let five = metrics.panelSize(for: 5)
        XCTAssertEqual(five.width, 5 * metrics.cardSize.width + 4 * metrics.cardGap + 2 * metrics.padding)
        XCTAssertEqual(metrics.panelSize(for: 10).width, five.width)
        XCTAssertEqual(metrics.panelSize(for: 10).height, 2 * metrics.cardSize.height + metrics.cardGap + 2 * metrics.padding)
    }

    /// Centred on the whole window, past its edges if it is small, and pulled
    /// back onto the screen at the screen's edge.
    func testThePanelIsCentredOnTheWindowAndKeptOnScreen() {
        let size = CGSize(width: 1128, height: 370)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let small = CGRect(x: 400, y: 200, width: 640, height: 480)
        let centred = TabSwitcherView.frame(size: size, centredOn: small, within: screen)
        XCTAssertEqual(centred.midX, small.midX, accuracy: 1)
        XCTAssertEqual(centred.midY, small.midY, accuracy: 1)
        XCTAssertLessThan(centred.minX, small.minX)
        let nearTheEdge = CGRect(x: 0, y: 200, width: 640, height: 480)
        XCTAssertEqual(TabSwitcherView.frame(size: size, centredOn: nearTheEdge, within: screen).minX, 0)
    }
}
