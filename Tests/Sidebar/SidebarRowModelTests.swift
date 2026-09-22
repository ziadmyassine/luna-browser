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

    private func group(_ name: String, kind: TabKind = .today, collapsed: Bool = false) -> TabGroup {
        TabGroup(spaceID: space, name: name, kind: kind, isCollapsed: collapsed)
    }

    /// §3.4b's order: the saved tier, the rule, `New Tab`, then today's tabs.
    /// The rule is under the saved rows and the command is under the rule —
    /// which is the opposite of where both stood before groups existed.
    func testRowOrder() {
        let essential = tab(.essential, "e")
        let saved = tab(.pinned, "s")
        let today = tab(.today, "t")
        let list = SidebarList(saved: [.tab(saved)], today: [.tab(today)], essentials: [essential])

        XCTAssertEqual(list.rows, [.tab(saved.id), .separator, .addTab, .tab(today.id)])
        XCTAssertEqual(list.essentials, [essential])
        XCTAssertEqual(list.listed.map(\.id), [saved.id, today.id])
    }

    /// The rule marks the bottom of the saved tier, so with nothing saved there
    /// is no bottom to mark: the list starts at `New Tab`, exactly as it did
    /// before §3.4b.
    func testTheRuleIsAbsentWithNothingSaved() {
        let today = tab(.today, "t")
        let list = SidebarList(today: [.tab(today)])

        XCTAssertFalse(list.showsRule)
        XCTAssertEqual(list.rows, [.addTab, .tab(today.id)])
    }

    /// …and it comes out for the length of a drag, because a zone you cannot
    /// see is a zone you cannot aim at.
    func testADragRevealsTheRule() {
        let list = SidebarList(today: [.tab(tab(.today, "t"))], revealingSaved: true)

        XCTAssertTrue(list.showsRule)
        XCTAssertEqual(list.rows.first, .separator)
        XCTAssertEqual(list.destination(forRow: 0, isBelowMidpoint: false).kind, .pinned)
    }

    /// A group is one row with its tabs under it.
    func testAGroupDrawsItsTabsUnderIt() {
        let folder = group("Research")
        let first = tab(.today, "a")
        let second = tab(.today, "b")
        let loose = tab(.today, "c")
        let list = SidebarList(today: [.group(folder, tabs: [first, second]), .tab(loose)])

        XCTAssertEqual(
            list.rows,
            [.addTab, .group(folder.id), .tab(first.id), .tab(second.id), .tab(loose.id)]
        )
        XCTAssertEqual(list.group(ofTab: first.id), folder)
        XCTAssertNil(list.group(ofTab: loose.id))
    }

    /// Folded, it is the header alone — and its tabs are not in `listed`
    /// either, because nothing is drawing them.
    func testAFoldedGroupDrawsOnlyItsHeader() {
        let folder = group("Research", collapsed: true)
        let inside = tab(.today, "a")
        let list = SidebarList(today: [.group(folder, tabs: [inside])])

        XCTAssertEqual(list.rows, [.addTab, .group(folder.id)])
        XCTAssertEqual(list.listed, [])
        XCTAssertEqual(list.group(at: 1), folder)
    }

    /// §6.6: which run and which index a drop means. Read from the two halves
    /// of a row rather than from the gap between two, which is the whole reason
    /// a group can be dropped into at its end — see `SidebarList`.
    func testDestinations() {
        let saved = tab(.pinned, "s")
        let folder = group("Work")
        let first = tab(.today, "a")
        let second = tab(.today, "b")
        let loose = tab(.today, "c")
        let list = SidebarList(
            saved: [.tab(saved)],
            today: [.group(folder, tabs: [first, second]), .tab(loose)]
        )
        // rows: 0 saved · 1 rule · 2 New Tab · 3 header · 4 a · 5 b · 6 loose

        XCTAssertEqual(list.destination(forRow: 0, isBelowMidpoint: false), .init(kind: .pinned, index: 0))
        XCTAssertEqual(list.destination(forRow: 0, isBelowMidpoint: true), .init(kind: .pinned, index: 1))
        // The rule and the command are one block and the whole of it is the
        // foot of the saved tier — see `testNothingLandsBetweenTheRuleAndNewTab`.
        XCTAssertEqual(list.destination(forRow: 1, isBelowMidpoint: true), .init(kind: .pinned, index: 1))
        XCTAssertEqual(list.destination(forRow: 2, isBelowMidpoint: false), .init(kind: .pinned, index: 1))
        XCTAssertEqual(list.destination(forRow: 2, isBelowMidpoint: true), .init(kind: .pinned, index: 1))
        // Over the header is before the group; under it is inside, at the top.
        XCTAssertEqual(list.destination(forRow: 3, isBelowMidpoint: false), .init(kind: .today, index: 0))
        XCTAssertEqual(
            list.destination(forRow: 3, isBelowMidpoint: true),
            .init(kind: .today, groupID: folder.id, index: 0)
        )
        XCTAssertEqual(
            list.destination(forRow: 4, isBelowMidpoint: true),
            .init(kind: .today, groupID: folder.id, index: 1)
        )
        // The end of the group, and — one half-row later — after it.
        XCTAssertEqual(
            list.destination(forRow: 5, isBelowMidpoint: true),
            .init(kind: .today, groupID: folder.id, index: 2)
        )
        XCTAssertEqual(list.destination(forRow: 6, isBelowMidpoint: false), .init(kind: .today, index: 1))
        XCTAssertEqual(list.destination(forRow: 6, isBelowMidpoint: true), .init(kind: .today, index: 2))
        // Past the last row is the foot of the list.
        XCTAssertEqual(list.destination(forRow: 99, isBelowMidpoint: false), .init(kind: .today, index: 2))
    }

    /// A folded group has no rows to drop between, so the one place under its
    /// header is the end of it.
    func testDroppingUnderAFoldedHeaderLandsAtTheEndOfTheGroup() {
        let folder = group("Work", collapsed: true)
        let list = SidebarList(today: [.group(folder, tabs: [tab(.today, "a"), tab(.today, "b")])])

        XCTAssertEqual(
            list.destination(forRow: 1, isBelowMidpoint: true),
            .init(kind: .today, groupID: folder.id, index: 2)
        )
    }

    /// §3.4b: a group holds tabs, not other groups. One carried over another
    /// lands beside it — above when the pointer asked for its first place.
    func testAGroupCannotLandInsideAGroup() {
        let folder = group("Work")
        let list = SidebarList(today: [.tab(tab(.today, "a")), .group(folder, tabs: [tab(.today, "b")])])

        let intoTheTop = SidebarDestination(kind: .today, groupID: folder.id, index: 0)
        let intoTheEnd = SidebarDestination(kind: .today, groupID: folder.id, index: 1)
        XCTAssertEqual(list.topLevel(intoTheTop), .init(kind: .today, index: 1))
        XCTAssertEqual(list.topLevel(intoTheEnd), .init(kind: .today, index: 2))
        // A loose destination is already top level and comes back untouched.
        let loose = SidebarDestination(kind: .today, index: 1)
        XCTAssertEqual(list.topLevel(loose), loose)
    }

    /// Where a tab stands now in the run a drop counts, which is what §6.6
    /// subtracts one from for a move further down the same run.
    func testCurrentIndexIsReadFromTheRunTheDropMeans() {
        let folder = group("Work")
        let inside = tab(.today, "a")
        let loose = tab(.today, "b")
        let list = SidebarList(today: [.group(folder, tabs: [inside]), .tab(loose)])

        XCTAssertEqual(list.currentIndex(of: loose.id, in: .init(kind: .today, index: 0)), 1)
        XCTAssertEqual(
            list.currentIndex(of: inside.id, in: .init(kind: .today, groupID: folder.id, index: 0)),
            0
        )
        // A grouped tab is not in the top-level run, and a loose one is not in
        // the group — neither is "at index 0 of somewhere it is not".
        XCTAssertNil(list.currentIndex(of: inside.id, in: .init(kind: .today, index: 0)))
        XCTAssertNil(list.currentSlotIndex(ofGroup: folder.id, in: .pinned))
        XCTAssertEqual(list.currentSlotIndex(ofGroup: folder.id, in: .today), 0)
    }

    func testRowLookup() {
        let saved = tab(.pinned, "s")
        let list = SidebarList(saved: [.tab(saved)])

        XCTAssertEqual(list.row(of: saved.id), 0)
        XCTAssertEqual(list.tab(at: 0), saved)
        XCTAssertNil(list.tab(at: 1))
        XCTAssertNil(list.tab(at: 99))
        XCTAssertNil(list[99])
    }

    /// The rule is furniture: the keyboard must not be able to land on it. A
    /// group header is not — Enter on one folds it.
    func testTheRuleIsNotSelectableAndAGroupIs() {
        let folder = group("Work")
        let list = SidebarList(saved: [.tab(tab(.pinned, "s"))], today: [.group(folder, tabs: [])])

        XCTAssertTrue(list.isSelectable(0))
        XCTAssertFalse(list.isSelectable(1))
        XCTAssertTrue(list.isSelectable(2))
        XCTAssertTrue(list.isSelectable(3))
        XCTAssertFalse(list.isSelectable(4))
    }

    /// The submenu that moves a tab offers every group but the one it is in.
    func testGroupsBesidesLeavesOutTheOneItIsIn() {
        let work = group("Work")
        let play = group("Play")
        let list = SidebarList(today: [.group(work, tabs: []), .group(play, tabs: [])])

        XCTAssertEqual(list.groups().map(\.id), [work.id, play.id])
        XCTAssertEqual(list.groups(besides: work.id).map(\.id), [play.id])
    }

    /// AppKit reports the row under the pointer; a drop belongs in the gap
    /// below it once the pointer is past the midpoint.
    func testTheGapFollowsTheMidpoint() {
        // saved tab, rule, New Tab, then three of today's.
        let list = SidebarList(saved: [.tab(tab(.pinned, "Kept"))], today: (0 ..< 3).map { .tab(tab(.today, "T\($0)")) })

        XCTAssertEqual(list.gapRow(forRow: 0, isBelowMidpoint: false), 0)
        XCTAssertEqual(list.gapRow(forRow: 4, isBelowMidpoint: false), 4)
        XCTAssertEqual(list.gapRow(forRow: 4, isBelowMidpoint: true), 5)
    }

    /// §3.4b: the rule and New Tab are one block, so no half of either opens a
    /// gap between them — both open it above the rule. A tab dropped there is
    /// dropped on the saved tier, which is what the whole block now means.
    func testNothingLandsBetweenTheRuleAndNewTab() throws {
        let list = SidebarList(saved: [.tab(tab(.pinned, "Kept"))], today: [.tab(tab(.today, "Loose"))])
        let rule = try XCTUnwrap(list.rows.firstIndex(of: .separator))
        let addTab = try XCTUnwrap(list.rows.firstIndex(of: .addTab))
        XCTAssertEqual(addTab, rule + 1, "the block is the two of them, in that order")

        for row in [rule, addTab] {
            for half in [true, false] {
                XCTAssertEqual(list.gapRow(forRow: row, isBelowMidpoint: half), rule)
                XCTAssertEqual(list.destination(forRow: row, isBelowMidpoint: half).kind, .pinned)
            }
        }
        // The head of today's tabs is still reachable — from the first of them.
        XCTAssertEqual(list.gapRow(forRow: addTab + 1, isBelowMidpoint: false), addTab + 1)
        XCTAssertEqual(
            list.destination(forRow: addTab + 1, isBelowMidpoint: false),
            SidebarDestination(kind: .today, groupID: nil, index: 0)
        )
    }

    /// With nothing saved and no lift up there is no rule, so there is no block
    /// either: New Tab's two halves are the two tiers, as they were before §3.4b.
    func testWithoutTheRuleNewTabStillDividesTheTwoTiers() throws {
        let list = SidebarList(today: [.tab(tab(.today, "Loose"))])
        XCTAssertFalse(list.showsRule)
        let addTab = try XCTUnwrap(list.rows.firstIndex(of: .addTab))
        XCTAssertEqual(list.destination(forRow: addTab, isBelowMidpoint: false).kind, .pinned)
        XCTAssertEqual(list.destination(forRow: addTab, isBelowMidpoint: true).kind, .today)
    }

    /// §3.4's rows fall back to `URLPillView.domain` when a tab has no title
    /// yet, and a tab that has only just been opened never does. Luna's own
    /// pages have a host like anything else, so the row said `archive` until
    /// the page's `<title>` arrived — and the pill above it said the same.
    @MainActor
    func testATabOnLunasOwnPageIsNamedNotHosted() {
        XCTAssertEqual(URLPillView.domain(of: InternalPages.Page.history.url), "History")
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
        controller.show(saved: [], today: [.tab(moving)], essentials: [], activeTabID: moving.id)
        let row = try XCTUnwrap(controller.list.row(of: moving.id))

        XCTAssertEqual(controller.content(for: row).title, "google.com")

        controller.update(moving.id, state: TabState(url: URL(string: "https://itslearning.com/main")!))

        XCTAssertEqual(controller.content(for: row).title, "itslearning.com")
    }
}

/// §3.4's title ink, which is the answer to "which tab am I on".
///
/// The rule has been asked for twice, from two directions: first that only the
/// selected row is bright, and then that a pointer resting on a row must not
/// change any title's colour. `titleInk` takes no `isHovered`, so the
/// second half is true by construction — these are here so it stays that way.
@MainActor
final class SidebarRowInkTests: XCTestCase {

    func testOnlyTheSelectedRowIsBright() {
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: true, isLoading: false), Tokens.Text.primary)
        XCTAssertEqual(SidebarRowView.titleInk(isSelected: false, isLoading: false), Tokens.Text.secondary)
    }

    /// §3.4b: a saved row whose page has been closed reads like a loading one,
    /// because both are rows with no page behind them right now. Deliberately
    /// not `Text.disabled` — that tier is for a control that cannot be
    /// operated, and this row is one click from being open again.
    func testADimmedRowReadsLikeALoadingOne() {
        XCTAssertEqual(
            SidebarRowView.titleInk(isSelected: false, isLoading: false, isDormant: true),
            Tokens.Text.tertiary
        )
        XCTAssertEqual(
            SidebarRowView.titleInk(isSelected: true, isLoading: false, isDormant: true),
            Tokens.Text.tertiary
        )
        XCTAssertNotEqual(
            SidebarRowView.titleInk(isSelected: false, isLoading: false, isDormant: true),
            Tokens.Text.disabled
        )
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

/// §3.4's title column, which is the other half of "how bright is a title" —
/// the ink says what colour it is, this says how much of it survives the fade.
///
/// The slot the close chip sits in is given back when no chip is in it, so a
/// resting title runs to the pill's inner edge. That is a decision, not an
/// accident: it means the column moves when the pointer arrives, which is how
/// a long title's last glyphs dissolve on hover. It was chosen with both
/// versions side by side, and `rowTitleFade` at 12 keeps the shift to about
/// two characters.
@MainActor
final class SidebarRowColumnTests: XCTestCase {

    private let width = Tokens.Metric.sidebarWidth.default

    /// Nothing in the slot: the title runs to the pill's inner edge, which is
    /// one `rowInset` inside the pill and two inside the row.
    func testARowWithNoTrailingGlyphRunsToThePillsEdge() {
        let column = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: false)
        XCTAssertEqual(column.x + column.width, width - 2 * Tokens.Metric.rowInset, accuracy: 0.01)
    }

    /// A glyph in the slot: the title stops half an inset short of it — the
    /// fade is the rest of the gap, so a full `chromeGap` here would be pill
    /// left empty for nothing.
    func testAGlyphInTheSlotPushesTheTitleBackByHalfAnInset() {
        let column = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: true)
        XCTAssertEqual(
            column.x + column.width,
            SidebarRowView.trailingSlotX(inRowOfWidth: width) - Tokens.Metric.rowInset / 2,
            accuracy: 0.01
        )
    }

    /// §3.4b: a group's tab steps in by exactly the width of the chevron's
    /// slot, which is the same amount a group header steps aside for it — so a
    /// member's favicon lands in the same column as its group's icon, and the
    /// two read as one column with a heading on it. Derived from one token, so
    /// this asserts the consequence rather than the arithmetic.
    func testAGroupsTabStepsInByTheChevronsSlot() {
        let loose = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: false)
        let inside = SidebarRowView.titleColumn(
            inRowOfWidth: width,
            hasUnread: false,
            slotOccupied: false,
            indent: Tokens.Metric.groupIndent
        )
        XCTAssertEqual(inside.x - loose.x, Tokens.Metric.groupChevronSlot.width, accuracy: 0.01)
        // The title gives the space up rather than running past the pill.
        XCTAssertEqual(loose.width - inside.width, Tokens.Metric.groupIndent, accuracy: 0.01)
    }

    /// The whole cost of the decision, stated as a number so it cannot drift
    /// upward unnoticed: what the title gives up when the chip appears.
    func testTheChipCostsTheTitleTwentyTwoPoints() {
        let resting = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: false)
        let hovered = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: true)
        XCTAssertEqual(resting.width - hovered.width, 22, accuracy: 0.01)
        XCTAssertEqual(resting.x, hovered.x, accuracy: 0.01)
    }

    /// The slot has to be where the chip is actually drawn, or reserving it is
    /// a fiction and the chip goes on top of the title's last glyphs.
    func testTheReservedSlotIsWhereTheChipIsActuallyDrawn() {
        let slot = SidebarRowView.trailingSlotX(inRowOfWidth: width)
        XCTAssertEqual(
            slot + Tokens.Metric.rowTrailingChip.width,
            width - 2 * Tokens.Metric.rowInset,
            accuracy: 0.01
        )
    }

    /// §3.4's unread dot pushes the title right. It must not also move the
    /// title's trailing edge, or an unread tab would fade somewhere else.
    func testTheUnreadDotMovesOnlyTheTitlesLeadingEdge() {
        for occupied in [false, true] {
            let plain = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: false, slotOccupied: occupied)
            let unread = SidebarRowView.titleColumn(inRowOfWidth: width, hasUnread: true, slotOccupied: occupied)
            XCTAssertGreaterThan(unread.x, plain.x)
            XCTAssertEqual(unread.x + unread.width, plain.x + plain.width, accuracy: 0.01)
        }
    }

    /// A sidebar dragged to its narrowest still has to produce a box, not a
    /// negative width — `NSRect` would happily take one and flip the box.
    func testAVeryNarrowRowStillProducesANonNegativeColumn() {
        XCTAssertGreaterThanOrEqual(
            SidebarRowView.titleColumn(inRowOfWidth: 0, hasUnread: true, slotOccupied: true).width, 0
        )
        XCTAssertGreaterThan(
            SidebarRowView.titleColumn(
                inRowOfWidth: Tokens.Metric.sidebarWidth.min, hasUnread: true, slotOccupied: true
            ).width,
            0
        )
    }
}

/// The row at the top of §3.4's list.
///
/// It read `+ Add Tab` and it made a blank tab, which is the one tab nobody
/// wants: the next thing anybody does with one is reach for the address bar.
/// It asks the question instead now — the row opens §9.1 in `.newTab`, so
/// closing the bar without choosing leaves the list exactly as it was rather
/// than one empty page longer.
@MainActor
final class SidebarAddRowTests: XCTestCase {

    func testTheFirstRowIsCalledNewTab() {
        XCTAssertEqual(TabListController().content(for: 0).title, "New Tab")
    }

    /// And it is still a row with a symbol rather than a favicon, which is how
    /// `SidebarRowView` knows to draw its glyph slot.
    func testItStillDrawsItsOwnGlyph() {
        let content = TabListController().content(for: 0)
        XCTAssertEqual(content.symbolName, "plus")
        XCTAssertNil(content.favicon)
    }
}
