//
//  SidebarRowModelTests.swift
//  LunaTests
//
//  `SidebarList` is where §3.4's row order and §6.6's drop maths live. Both are
//  pure, and both are the kind of off-by-one that is invisible until a user
//  drags a tab to the wrong section — so they are asserted here rather than
//  eyeballed in a running window.
//

import BrowserKit
import XCTest
@testable import Luna

final class SidebarRowModelTests: XCTestCase {

    private let space = UUID()

    private func tab(_ kind: TabKind, _ name: String) -> Tab {
        Tab(spaceID: space, kind: kind, url: URL(string: "https://\(name).example")!, title: name)
    }

    /// `+ Add Tab` → separator → tabs, Essentials excluded. **Archive is not a
    /// row.** It was a second door to the page the bottom bar's History button
    /// already opens, and it sat where the eye lands first.
    func testRowOrder() {
        let essential = tab(.essential, "e")
        let pinned = tab(.pinned, "p")
        let today = tab(.today, "t")
        let list = SidebarList(tabs: [today, essential, pinned])

        XCTAssertEqual(list.rows, [.addTab, .separator, .tab(pinned.id), .tab(today.id)])
        XCTAssertEqual(list.essentials, [essential])
        XCTAssertEqual(list.listed.map(\.id), [pinned.id, today.id])
    }

    func testRowLookup() {
        let pinned = tab(.pinned, "p")
        let list = SidebarList(tabs: [pinned])

        XCTAssertEqual(list.row(of: pinned.id), 2)
        XCTAssertEqual(list.tab(at: 2), pinned)
        XCTAssertNil(list.tab(at: 0))
        XCTAssertNil(list.tab(at: 99))
        XCTAssertNil(list[99])
    }

    /// The separator is furniture: the keyboard must not be able to land on it.
    func testSeparatorIsNotSelectable() {
        let list = SidebarList(tabs: [tab(.today, "t")])

        XCTAssertTrue(list.isSelectable(0))
        XCTAssertFalse(list.isSelectable(1))
        XCTAssertTrue(list.isSelectable(2))
        XCTAssertFalse(list.isSelectable(3))
    }

    /// §6.6: the row index a drop landed on maps to a section plus an index
    /// *within* that section, which is what `reorderTab` takes.
    func testDropTargets() {
        let list = SidebarList(tabs: [tab(.pinned, "p1"), tab(.pinned, "p2"), tab(.today, "t1")])

        XCTAssertEqual(list.dropTarget(insertingAt: 2).kind, .pinned)
        XCTAssertEqual(list.dropTarget(insertingAt: 2).index, 0)
        XCTAssertEqual(list.dropTarget(insertingAt: 3).index, 1)
        XCTAssertEqual(list.dropTarget(insertingAt: 4).kind, .today)
        XCTAssertEqual(list.dropTarget(insertingAt: 4).index, 0)
        XCTAssertEqual(list.dropTarget(insertingAt: 5).index, 1)
        // Never inside the leading command group.
        XCTAssertEqual(list.dropTarget(insertingAt: 0).kind, .pinned)
        XCTAssertEqual(list.dropTarget(insertingAt: 0).index, 0)
    }

    /// With no pinned section there is no pinned row to sit above, so the top
    /// of the list is the top of today's tabs.
    func testDropAtTopWithoutPinnedSectionIsToday() {
        let list = SidebarList(tabs: [tab(.today, "t1")])

        XCTAssertEqual(list.dropTarget(insertingAt: 2).kind, .today)
        XCTAssertEqual(list.dropTarget(insertingAt: 2).index, 0)
    }

    /// AppKit reports the row under the pointer; a drop belongs in the gap
    /// below it once the pointer is past the midpoint.
    func testInsertionRowClampsToTheFirstTab() {
        XCTAssertEqual(SidebarList.insertionRow(forRow: 0, isBelowMidpoint: false), 2)
        XCTAssertEqual(SidebarList.insertionRow(forRow: 4, isBelowMidpoint: false), 4)
        XCTAssertEqual(SidebarList.insertionRow(forRow: 4, isBelowMidpoint: true), 5)
    }

    /// §3.4's rows fall back to `URLPillView.domain` when a tab has no title
    /// yet, and a brand new tab never does. Luna's own pages have a host like
    /// anything else, so the row said `newtab` until the page's `<title>`
    /// arrived — and the pill above it said the same.
    @MainActor
    func testATabOnLunasOwnPageIsNamedNotHosted() {
        XCTAssertEqual(URLPillView.domain(of: InternalPages.Page.newTab.url), "New Tab")
        XCTAssertEqual(URLPillView.domain(of: InternalPages.Page.archive.url), "History")
        XCTAssertEqual(URLPillView.domain(of: URL(string: "https://www.apple.com")!), "apple.com")
        XCTAssertEqual(URLPillView.domain(of: nil), "")
    }

    /// §4.7's icon follows the page, not the snapshot the sidebar was last
    /// handed. An in-tab navigation raises no `onChange` — it writes the tab and
    /// publishes a `TabState` — so a row that asked its stored `Tab` for the
    /// host kept drawing the previous site's favicon, and its fallback name kept
    /// saying the previous site's domain, until something unrelated reloaded the
    /// list. Both read the live URL now, so this asserts the name and the icon
    /// path in one: they are the same `url` in `tabContent`.
    @MainActor
    func testARowFollowsTheTabToItsNewSite() throws {
        let moving = Tab(spaceID: space, kind: .today, url: URL(string: "https://google.com")!)
        let controller = TabListController()
        controller.show([moving], activeTabID: moving.id)
        let row = try XCTUnwrap(controller.list.row(of: moving.id))

        XCTAssertEqual(controller.content(for: row).title, "google.com")

        controller.update(moving.id, state: TabState(url: URL(string: "https://itslearning.com/main")!))

        XCTAssertEqual(controller.content(for: row).title, "itslearning.com")
    }
}

/// §3.4's title ink, which is the answer to "which tab am I on".
///
/// Martin has asked for this rule twice, from two directions: first that only
/// the selected row is bright, and then that a pointer resting on a row must
/// not change any title's colour. `titleInk` takes no `isHovered`, so the
/// second half is true by construction — these are here so it stays that way.
@MainActor
final class SidebarRowInkTests: XCTestCase {

    func testOnlyTheSelectedRowIsBright() {
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: true, isLoading: false), Tokens.Text.primary)
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: false, isLoading: false), Tokens.Text.secondary)
    }

    /// A loading row is quieter than either, selected or not — §3.4's shimmer
    /// is what says it is working, and it sweeps over a dimmed title.
    func testALoadingRowIsQuieterThanBoth() {
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: true, isLoading: true), Tokens.Text.tertiary)
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: false, isLoading: true), Tokens.Text.tertiary)
    }

    /// The three tiers are three colours. If two of them ever resolve to the
    /// same ink the rule above still passes and the list stops saying anything.
    func testTheThreeTiersAreActuallyDifferent() {
        let inks = [
            SidebarRowView.titleInk(isSelected: true, isLoading: false),
            SidebarRowView.titleInk(isSelected: false, isLoading: false),
            SidebarRowView.titleInk(isSelected: false, isLoading: true)
        ]
        XCTAssertEqual(Set(inks).count, 3)
    }
}

/// §3.4's title column, which is the other way a title can dim under the
/// pointer: the close chip is revealed on hover, and a column that gave the
/// chip's slot back when the chip was absent lost 26 pt the moment the pointer
/// arrived — moving §3.4's trailing fade left across a long title. The ink
/// stayed put and the title still went grey at the end. So the column takes no
/// hover either, and reserves the slot on every row.
@MainActor
final class SidebarRowColumnTests: XCTestCase {

    private let width = Tokens.Metric.sidebarWidth.default

    /// The whole point: the slot is reserved whether or not a glyph is in it,
    /// so no row's title moves because the pointer arrived.
    func testTheTitleColumnLeavesTheTrailingSlotClearOnEveryRow() {
        let column = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false)
        XCTAssertEqual(
            column.x + column.width,
            SidebarRowView.trailingSlotX(inRowOfWidth: width) - Tokens.Metric.chromeGap,
            accuracy: 0.01
        )
    }

    /// The slot itself has to fit inside the pill, or reserving it is a fiction
    /// and the chip goes on drawing over the title's last glyphs.
    func testTheReservedSlotIsWhereTheChipIsActuallyDrawn() {
        let slot = SidebarRowView.trailingSlotX(inRowOfWidth: width)
        XCTAssertEqual(
            slot + Tokens.Metric.rowTrailingChip.width,
            width - 2 * Tokens.Metric.rowInset,
            accuracy: 0.01
        )
    }

    /// §3.4's unread dot pushes the title right. It must not also push the
    /// title's trailing edge, or an unread tab would fade differently.
    func testTheUnreadDotMovesOnlyTheTitlesLeadingEdge() {
        let plain = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false)
        let unread = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: true)
        XCTAssertGreaterThan(unread.x, plain.x)
        XCTAssertEqual(unread.x + unread.width, plain.x + plain.width, accuracy: 0.01)
    }

    /// A sidebar dragged to its narrowest still has to produce a box, not a
    /// negative width — `NSRect` would happily take one and flip the box.
    func testAVeryNarrowRowStillProducesANonNegativeColumn() {
        XCTAssertGreaterThanOrEqual(SidebarRowView.titleColumn(inRowOfWidth: 0, hasUnread: true).width, 0)
        XCTAssertGreaterThan(
            SidebarRowView.titleColumn(inRowOfWidth: Tokens.Metric.sidebarWidth.min, hasUnread: true).width,
            0
        )
    }
}
