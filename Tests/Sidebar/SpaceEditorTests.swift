//
//  SpaceEditorTests.swift
//  LunaTests
//
//  §6.1's editor, which is laid out by hand in a column the user can drag —
//  so the only thing holding its grid together is arithmetic.
//

import XCTest
@testable import Luna
@testable import BrowserKit

/// The two chip grids, at the two widths the §3.7 handle reaches: the sidebar
/// as it ships and the sidebar squeezed to its minimum.
@MainActor
final class SpaceEditorGridTests: XCTestCase {

    private func laidOutEditor(width: CGFloat) -> SpaceEditorView {
        let space = Space(
            name: "Space 3",
            symbolName: BrowserSession.defaultSpaceSymbol,
            gradient: .defaultSpace,
            profileID: UUID()
        )
        let editor = SpaceEditorView(space: space)
        editor.frame = NSRect(x: 0, y: 0, width: width, height: 640)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    private func swatches(_ editor: SpaceEditorView) -> [NSView] {
        editor.subviews.filter { $0 is SpaceSwatchChip }
    }

    /// **No chip alone on a line of its own.** Thirteen colours packed greedily
    /// into six columns leave one on the last row, and that orphan is the first
    /// thing the eye finds in the form.
    func testTheGridSpreadsItsChipsRatherThanLeavingAnOrphan() {
        for width in [264, 229, 200] as [CGFloat] {
            let chips = swatches(laidOutEditor(width: width))
            XCTAssertEqual(chips.count, SpaceAppearanceView.gradients.count)
            let rows = Dictionary(grouping: chips) { $0.frame.minY.rounded() }
            let counts = rows.values.map(\.count).sorted()
            guard let fullest = counts.last, let shortest = counts.first else { return XCTFail("no rows") }
            XCTAssertGreaterThan(shortest, 1, "a row of one at \(width) pt wide")
            XCTAssertGreaterThanOrEqual(
                Double(shortest),
                Double(fullest) / 2,
                "the last row is a short row, not a leftover: \(counts) at \(width) pt wide"
            )
        }
    }

    /// The columns fill the width, and the rows are spaced by whatever the
    /// columns ended up with — one grid, not a block combed out sideways.
    func testTheGridIsSquareAndFillsTheColumn() {
        let editor = laidOutEditor(width: 264)
        let chips = swatches(editor).sorted { ($0.frame.minY, $0.frame.minX) > ($1.frame.minY, $1.frame.minX) }
        guard chips.count > 2 else { return XCTFail("no chips") }
        let top = chips.filter { $0.frame.minY == chips[0].frame.minY }.sorted { $0.frame.minX < $1.frame.minX }
        guard top.count > 1, let first = top.first, let last = top.last else { return XCTFail("one column") }
        XCTAssertEqual(first.frame.minX, Tokens.Metric.rowInset, accuracy: 0.5)
        XCTAssertEqual(last.frame.maxX, editor.bounds.width - Tokens.Metric.rowInset, accuracy: 1)
        let columnPitch = top[1].frame.minX - top[0].frame.minX
        let second = chips.first { $0.frame.minY < chips[0].frame.minY }
        guard let second else { return XCTFail("one row") }
        XCTAssertEqual(chips[0].frame.minY - second.frame.minY, columnPitch, accuracy: 0.5)
    }

    /// The chips are the popover's own, at the popover's own size: §6.2's grid
    /// and this one are one picker.
    func testTheChipsAreTheSizeEveryOtherPaletteDrawsThem() {
        for chip in swatches(laidOutEditor(width: 264)) {
            XCTAssertEqual(chip.frame.width, Tokens.Metric.settingsControl, accuracy: 0.001)
            XCTAssertEqual(chip.frame.height, Tokens.Metric.settingsControl, accuracy: 0.001)
        }
    }
}
