//
//  PinHintTests.swift
//  LunaTests
//
//  §3.3a: the two wells a Space with nothing pinned draws, and the three things
//  about them that are not appearance.
//
//  · They are there exactly when the tier they describe is empty and the advice
//    has not been taken.
//  · Each stands in the thing it is standing in for: the block in §3.3's first
//    tile slot, the row in §3.4's own two columns. So the grid is the same
//    height with the well in it as with the first tile in it, and nothing moves
//    when a §6.6 lift comes into the air or when it lands.
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

    // MARK: - The grid's half

    /// The well is the empty tile, so the grid giving advice stands at exactly
    /// the height it will stand at once the advice is taken — pinning the first
    /// tab moves nothing below it.
    func testAnEmptyGridStandsAtOneTile() {
        XCTAssertEqual(grid().intrinsicContentSize.height, oneTileGrid)
        XCTAssertEqual(grid(hinting: false).intrinsicContentSize.height, 0, "no advice, no room")
    }

    func testTheBlockWellStandsInTheSlotTheFirstTileTakes() {
        let grid = grid()
        grid.layoutSubtreeIfNeeded()
        let well = grid.subviews.compactMap { $0 as? SidebarPinHintView }.first
        XCTAssertEqual(well?.frame, grid.slotRect(at: 0))
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

    private func well(_ shape: SidebarPinHintView.Shape, atWidth width: CGFloat) -> SidebarPinHintView {
        let well = shape == .block ? SidebarPinHintView.tabGrid() : SidebarPinHintView.folderTier()
        well.frame = NSRect(x: 0, y: 0, width: width - 2 * Tokens.Metric.rowInset, height: shape.height)
        well.layoutSubtreeIfNeeded()
        return well
    }

    private func glyph(in well: SidebarPinHintView) -> NSRect {
        well.subviews.compactMap { $0 as? NSImageView }.first { !($0 is RowGlyphView) }?.frame ?? .zero
    }

    /// The line's own box, which is the clipping box §3.4's fade ends it in —
    /// and not the label inside it, which is always laid out at its full width.
    private func line(in well: SidebarPinHintView) -> NSRect {
        well.subviews.first { $0.subviews.contains(where: { $0 is NSTextField }) }?.frame ?? .zero
    }

    private func label(in well: SidebarPinHintView) -> NSTextField? {
        well.subviews.compactMap { view in view.subviews.compactMap { $0 as? NSTextField }.first }.first
    }

    /// Both wells have to survive the §3.7 handle's narrowest column with
    /// their cross still on screen and their line clear of it — while the cross
    /// is on screen, which is the only time the slot is the cross's.
    func testTheCrossAndTheLineShareTheNarrowestColumn() {
        for width in [Tokens.Metric.sidebarFootFloor, Tokens.Metric.sidebarWidth.default] {
            for shape in [SidebarPinHintView.Shape.block, .row] {
                let well = well(shape, atWidth: width)
                well.setHovered(true)
                let cross = well.subviews.compactMap { $0 as? RowGlyphView }.first?.frame ?? .zero
                let place = "\(shape) at \(width)"
                XCTAssertTrue(well.bounds.contains(cross), "\(place) lost its cross off the edge")
                XCTAssertTrue(well.bounds.contains(line(in: well)), "\(place) lost its line off the edge")
                XCTAssertFalse(line(in: well).intersects(cross), "\(place) ran its line under the cross")
            }
        }
    }

    /// Both wells stand in §3.4's own two columns: the glyph where a favicon
    /// goes, at a favicon's size, and the line where every title starts. The
    /// block centred its pair and drew it at a folder's 20 pt, so the two wells
    /// and the rows under them put their glyphs in three different places.
    func testBothWellsStandInTheColumnsARowStandsIn() {
        for shape in [SidebarPinHintView.Shape.block, .row] {
            let well = well(shape, atWidth: Tokens.Metric.sidebarWidth.default)
            XCTAssertEqual(glyph(in: well).width, Tokens.Metric.faviconSize, "\(shape) is not a favicon's size")
            XCTAssertEqual(
                glyph(in: well).minX,
                Tokens.Metric.rowFaviconInset - Tokens.Metric.rowInset,
                accuracy: 0.51,
                "\(shape) is off the favicon column"
            )
            XCTAssertEqual(
                line(in: well).minX,
                Tokens.Metric.rowTitleInset - Tokens.Metric.rowInset,
                accuracy: 0.51,
                "\(shape) does not start where a row's title starts"
            )
        }
    }

    /// A line longer than its column is never cut with an ellipsis. It is laid
    /// out at its full width inside a clipping box and dissolves against the
    /// trailing edge, which is what §3.4 does with an over-long title — and
    /// what stops a narrow column reading "Drag a tab here to pi…".
    func testALineTooLongForItsColumnDissolvesRatherThanTruncating() {
        for shape in [SidebarPinHintView.Shape.block, .row] {
            let well = well(shape, atWidth: Tokens.Metric.sidebarFootFloor)
            let label = label(in: well)
            XCTAssertEqual(label?.lineBreakMode, .byClipping, "\(shape) would draw an ellipsis")
            XCTAssertGreaterThanOrEqual(
                label?.frame.width ?? 0,
                label?.intrinsicContentSize.width ?? 0,
                "\(shape) squeezed its own words"
            )
        }
    }

    /// At the column as it comes, neither line needs the fade at all.
    func testNeitherLineNeedsTheFadeAtTheDefaultColumn() {
        for shape in [SidebarPinHintView.Shape.block, .row] {
            let well = well(shape, atWidth: Tokens.Metric.sidebarWidth.default)
            XCTAssertGreaterThanOrEqual(
                line(in: well).width,
                label(in: well)?.intrinsicContentSize.width ?? 0,
                "\(shape) was read half a sentence at the width nobody has changed"
            )
        }
    }

    /// The cross is revealed on hover, exactly as §3.4's close is — and until
    /// it is showing it takes no press, however close the pointer gets to the
    /// corner it will stand in.
    func testTheCrossIsNotThereUntilThePointerIs() {
        let well = well(.row, atWidth: Tokens.Metric.sidebarWidth.default)
        let cross = well.subviews.compactMap { $0 as? RowGlyphView }.first
        XCTAssertEqual(cross?.isHidden, true, "the cross is standing in the well at rest")
        let centre = NSPoint(x: cross?.frame.midX ?? 0, y: cross?.frame.midY ?? 0)
        XCTAssertTrue(
            well.hitTest(well.convert(centre, to: well.superview)) === well,
            "a cross nobody can see took the press"
        )
    }

    /// Neither well carries a fill at rest — nothing else in §3 does — and a
    /// lift arriving over one is what puts a wash under it.
    func testAWellIsEmptyUntilALiftIsOverIt() {
        for shape in [SidebarPinHintView.Shape.block, .row] {
            let well = shape == .block ? SidebarPinHintView.tabGrid() : SidebarPinHintView.folderTier()
            XCTAssertNil(well.layer?.backgroundColor, "\(shape) is a filled box with nothing in it")
            well.isAimedAt = true
            XCTAssertNotNil(well.layer?.backgroundColor, "\(shape) did not answer the lift")
        }
    }

    /// Both wells speak in the column's own face — the row's own token, not a
    /// second one that forwards to it. They were set in a section label's
    /// weight, which would have been the only bold type in §3.
    func testAWellSpeaksInTheColumnsOwnFace() {
        for shape in [SidebarPinHintView.Shape.block, .row] {
            let well = well(shape, atWidth: Tokens.Metric.sidebarWidth.default)
            XCTAssertEqual(label(in: well)?.font, Tokens.TypeScale.sidebarRow, "\(shape) is not in the row's face")
        }
    }

    /// The line keeps the cross's slot only while the cross is in it, which is
    /// §3.4's own rule — and 22 pt, which in a narrow column is the difference
    /// between a sentence and most of one.
    func testTheLineTakesTheCrossesSlotWhileNobodyIsPointingAtIt() {
        let well = well(.row, atWidth: Tokens.Metric.sidebarWidth.default)
        let atRest = line(in: well).maxX
        XCTAssertEqual(atRest, well.bounds.maxX - Tokens.Metric.rowInset, accuracy: 0.51)
        let cross = well.subviews.compactMap { $0 as? RowGlyphView }.first?.frame ?? .zero
        XCTAssertGreaterThan(atRest, cross.minX, "the line never reaches the slot it is meant to borrow")
        well.setHovered(true)
        XCTAssertLessThan(line(in: well).maxX, cross.minX, "the line kept the slot the cross is now in")
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
