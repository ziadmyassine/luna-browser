//
//  PinHintTests.swift
//  LunaTests
//
//  §3.3a: the two wells a Space with nothing pinned draws, and the three things
//  about them that are not appearance.
//
//  · They are there exactly when the tier they describe is empty and the advice
//    has not been taken.
//  · The block well is the §3.3 grid's height while it is up, and it stays that
//    height when a §6.6 lift comes into the air. The grid used to open from
//    nothing to a tile's height on the first frame of every drag, which is a
//    movement the well is meant to have already made.
//  · §30.9's still draws both, because a picture that leaves them out is a
//    column whose rows stand a hundred points too high — and that correction
//    lands inside the cross-fade that exists to hide one.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class PinHintTests: XCTestCase {

    private var tabDismissed: Bool!
    private var folderDismissed: Bool!

    override func setUp() {
        super.setUp()
        tabDismissed = !Settings.showsPinnedTabHint
        folderDismissed = !Settings.showsPinnedFolderHint
        Settings.showsPinnedTabHint = true
        Settings.showsPinnedFolderHint = true
    }

    override func tearDown() {
        Settings.showsPinnedTabHint = !tabDismissed
        Settings.showsPinnedFolderHint = !folderDismissed
        super.tearDown()
    }

    private func grid(hinting: Bool = true) -> EssentialsGridView {
        let grid = EssentialsGridView()
        grid.frame = NSRect(x: 0, y: 0, width: 280, height: 120)
        grid.showsHint = hinting
        return grid
    }

    private func tab(_ index: Int) -> Tab {
        Tab(spaceID: UUID(), kind: .essential, url: URL(string: "https://example.com/\(index)")!, order: index)
    }

    private var oneTileGrid: CGFloat {
        Tokens.Metric.essentialsTile.height + 2 * Tokens.Metric.essentialsVerticalInset
    }

    private var wellGrid: CGFloat {
        Tokens.Metric.pinHintBlock + 2 * Tokens.Metric.essentialsVerticalInset
    }

    // MARK: - The grid's half

    func testAnEmptyGridStandsAtTheWellsHeight() {
        XCTAssertEqual(grid().intrinsicContentSize.height, wellGrid)
        XCTAssertEqual(grid(hinting: false).intrinsicContentSize.height, 0, "no advice, no room")
    }

    /// The well is the drop target, so nothing moves when a lift comes up.
    func testTheColumnDoesNotJumpWhenALiftComesUp() {
        let grid = grid()
        let atRest = grid.intrinsicContentSize.height
        grid.isAwaitingDrop = true
        XCTAssertEqual(grid.intrinsicContentSize.height, atRest)
    }

    /// Without the well the grid still has to open for a drop, which is the
    /// behaviour this is built on top of rather than instead of.
    func testAGridWithTheAdviceTakenStillOpensForADrop() {
        let grid = grid(hinting: false)
        grid.isAwaitingDrop = true
        XCTAssertEqual(grid.intrinsicContentSize.height, oneTileGrid)
    }

    func testTheWellGoesWhenTheFirstTabIsPinned() {
        let grid = grid()
        grid.show([tab(0)], activeTabID: nil)
        XCTAssertFalse(grid.isHinting)
        XCTAssertEqual(grid.intrinsicContentSize.height, oneTileGrid)
    }

    /// A tile in the air is still a tile. Advice that appeared for the length
    /// of a drag would be a third thing moving in a gesture that already has
    /// the lift and the grid.
    func testCarryingTheLastTileDoesNotBringTheAdviceBack() {
        let grid = grid()
        let only = tab(0)
        grid.show([only], activeTabID: nil)
        grid.draggedID = only.id
        XCTAssertFalse(grid.isHinting)
    }

    // MARK: - Dismissal

    func testEachWellIsDismissedOnItsOwn() {
        Settings.showsPinnedTabHint = false
        XCTAssertFalse(Settings.showsPinnedTabHint)
        XCTAssertTrue(Settings.showsPinnedFolderHint, "one cross ended both pieces of advice")
    }

    /// The default is the advice: a key nobody has written reads as "show it".
    func testAdviceIsWhatAFreshInstallGets() {
        let fresh = UserDefaults(suiteName: "luna.pinhint.\(UUID().uuidString)")!
        XCTAssertFalse(fresh.bool(forKey: "luna.pinHint.tabDismissed"))
    }

    // MARK: - The well itself

    /// Both wells have to survive the §3.7 handle's narrowest column with
    /// their cross still on screen and their line clear of it — which in the
    /// block is a row above the line and in the row is the column beside it.
    func testTheCrossAndTheLineShareTheNarrowestColumn() {
        for width in [Tokens.Metric.sidebarWidth.min, Tokens.Metric.sidebarWidth.default] {
            for shape in [SidebarPinHintView.Shape.block, .row] {
                let well = shape == .block ? SidebarPinHintView.tabGrid() : SidebarPinHintView.folderTier()
                well.frame = NSRect(x: 0, y: 0, width: width - 2 * Tokens.Metric.rowInset, height: shape.height)
                well.layoutSubtreeIfNeeded()
                let cross = well.subviews.compactMap { $0 as? RowGlyphView }.first?.frame ?? .zero
                let line = well.subviews.compactMap { $0 as? NSTextField }.first?.frame ?? .zero
                let place = "\(shape) at \(width)"
                XCTAssertTrue(well.bounds.contains(cross), "\(place) lost its cross off the edge")
                XCTAssertTrue(well.bounds.contains(line), "\(place) lost its line off the edge")
                XCTAssertFalse(line.intersects(cross), "\(place) ran its line under the cross")
            }
        }
    }

    /// The default column is wide enough for the longer of the two lines, so
    /// nobody who has not resized anything is read half a sentence.
    func testTheLongerLineFitsTheColumnAsItComes() {
        let well = SidebarPinHintView.folderTier()
        well.frame = NSRect(
            x: 0,
            y: 0,
            width: Tokens.Metric.sidebarWidth.default - 2 * Tokens.Metric.rowInset,
            height: SidebarPinHintView.Shape.row.height
        )
        well.layoutSubtreeIfNeeded()
        let label = well.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.frame.width, label?.intrinsicContentSize.width, "the line was truncated")
    }

    // MARK: - §30.9's still

    func testTheStillDrawsBothWellsAndStartsItsRowsUnderThem() {
        let still = SpacePreviewView()
        still.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        still.show(column: SidebarList(), gradient: .defaultSpace) { _ in nil }
        still.layoutSubtreeIfNeeded()

        let wells = still.subviews.compactMap { $0 as? SidebarPinHintView }
        XCTAssertEqual(wells.count, 2, "a Space with nothing pinned draws both")
        let block = try? XCTUnwrap(wells.first { $0.frame.height == Tokens.Metric.pinHintBlock })
        let row = try? XCTUnwrap(wells.first { $0.frame.height == Tokens.Metric.pinHintRow })
        XCTAssertLessThan(row?.frame.maxY ?? 0, block?.frame.minY ?? 0, "the folder well is not under the grid's")

        // `SidebarList()` is an empty Space, which still has §30.6's New Tab
        // row — and it belongs under both wells rather than beside them.
        let rows = still.subviews.filter { $0 is SpacePreviewRow }
        XCTAssertFalse(rows.isEmpty)
        for listRow in rows {
            XCTAssertLessThanOrEqual(listRow.frame.maxY, row?.frame.minY ?? 0)
        }
    }

    func testTheStillLeavesOutTheWellTheSpaceHasNoNeedOf() {
        let still = SpacePreviewView()
        still.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
        still.show(column: SidebarList(essentials: [tab(0)]), gradient: .defaultSpace) { _ in nil }
        still.layoutSubtreeIfNeeded()
        let wells = still.subviews.compactMap { $0 as? SidebarPinHintView }
        XCTAssertEqual(wells.count, 1, "a Space with a pinned tab was still told to pin one")
        XCTAssertEqual(wells.first?.frame.height, Tokens.Metric.pinHintRow)
    }
}
