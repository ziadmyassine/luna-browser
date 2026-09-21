//
//  SpaceEditorTests.swift
//  LunaTests
//
//  §6.1's editor, which is laid out by hand in a column the user can drag —
//  so the only thing holding its grid together is arithmetic.
//
//  **The form was reported for its alignment, and alignment is exactly what a
//  hand-laid column loses first.** Every piece of type in it used to start at
//  its own edge — the title at `rowInset`, the name a `pillTextInset` further
//  in because it lived in a pill, the section headings back out at `rowInset`
//  again — and none of that is visible in the code, which reads as three
//  perfectly ordinary calls. It is visible here: `testEveryPieceOfTypeStartsOn
//  TheSameEdge` is the whole complaint, as one assertion.
//

import XCTest
@testable import Luna
@testable import BrowserKit

/// The three cards and the two chip grids, at the widths the §3.7 handle
/// reaches: the sidebar as it ships, squeezed to its minimum, and pulled out.
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
        editor.frame = NSRect(x: 0, y: 0, width: width, height: 760)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    /// Every view of a kind, wherever it has ended up. The chips live inside
    /// their card now rather than loose on the form, which is the point.
    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        var found: [T] = []
        for child in root.subviews {
            if let match = child as? T { found.append(match) }
            found += descendants(of: child, ofType: type)
        }
        return found
    }

    private func swatches(_ editor: SpaceEditorView) -> [NSView] {
        descendants(of: editor, ofType: SpaceSwatchChip.self)
    }

    /// Where a view sits in the form, whatever card it is on.
    private func onForm(_ view: NSView, in editor: SpaceEditorView) -> NSRect {
        view.convert(view.bounds, to: editor)
    }

    private func label(_ text: String, in editor: SpaceEditorView) -> NSTextField? {
        descendants(of: editor, ofType: NSTextField.self).first { $0.stringValue == text }
    }

    /// The complaint, as an assertion. The title, the caption, the name,
    /// both section headings and the first chip of both grids start on one
    /// edge — the card's text inset — and the plates are the only thing that
    /// reaches past it.
    func testEveryPieceOfTypeStartsOnTheSameEdge() {
        for width in [280, 250, 420] as [CGFloat] {
            let editor = laidOutEditor(width: width)
            let edge = Tokens.Metric.rowInset + Tokens.Metric.settingsControlInset
            let texts = ["New Space", "Name it, colour it, and it is yours.", "Space 3", "Colour", "Icon"]
            for text in texts {
                guard let found = label(text, in: editor) else { return XCTFail("no \(text) at \(width) pt") }
                XCTAssertEqual(onForm(found, in: editor).minX, edge, accuracy: 0.5, "\(text) at \(width) pt")
            }
            let chips = swatches(editor).sorted { $0.frame.minY > $1.frame.minY }
            guard let first = chips.first else { return XCTFail("no chips at \(width) pt") }
            XCTAssertEqual(onForm(first, in: editor).minX, edge, accuracy: 0.5, "the palette at \(width) pt")
        }
    }

    /// Three decisions, three plates, and each one holds its own. A card
    /// that has drifted over its neighbour is the failure this catches; a chip
    /// that has escaped its card is the other.
    func testEachGroupIsOnItsOwnPlateAndTheyDoNotTouch() {
        let editor = laidOutEditor(width: 280)
        let cards = descendants(of: editor, ofType: SpaceEditorCard.self)
        XCTAssertEqual(cards.count, 3, "a card for the name, the colour and the icon")
        for (above, below) in zip(cards, cards.dropFirst()) {
            XCTAssertFalse(above.frame.intersects(below.frame), "two cards on the same points")
        }
        for chip in swatches(editor) {
            XCTAssertTrue(chip.superview is SpaceEditorCard, "a chip loose on the form")
            guard let card = chip.superview else { return XCTFail("a chip with no card") }
            XCTAssertTrue(card.bounds.contains(chip.frame), "a chip over its card's edge")
        }
    }

    /// No chip alone on a line of its own. Thirteen colours packed greedily
    /// into six columns leave one on the last row, and that orphan is the first
    /// thing the eye finds in the form.
    func testTheGridSpreadsItsChipsRatherThanLeavingAnOrphan() {
        for width in [280, 250, 220] as [CGFloat] {
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

    /// The columns fill the card, so a row of chips starts and ends where the
    /// heading above it does.
    func testTheColumnsFillTheCard() {
        let width: CGFloat = 280
        let editor = laidOutEditor(width: width)
        let edge = Tokens.Metric.rowInset + Tokens.Metric.settingsControlInset
        let chips = swatches(editor)
        guard let topRow = chips.map(\.frame.minY).max() else { return XCTFail("no chips") }
        let top = chips.filter { $0.frame.minY == topRow }.sorted { $0.frame.minX < $1.frame.minX }
        guard let first = top.first, let last = top.last, top.count > 1 else { return XCTFail("one column") }
        XCTAssertEqual(onForm(first, in: editor).minX, edge, accuracy: 0.5)
        XCTAssertEqual(onForm(last, in: editor).maxX, width - edge, accuracy: 1)
    }

    /// The rows take the columns' spacing — one grid, not a block combed out
    /// sideways — up to the chrome's wide gap and no further. A sidebar
    /// dragged out wide spreads its columns a long way, and rows that followed
    /// them there would leave a card with a hole in it.
    func testTheRowsFollowTheColumnsUpToTheChromesWideGap() {
        for width in [280, 250, 420] as [CGFloat] {
            let chips = swatches(laidOutEditor(width: width)).sorted {
                ($0.frame.minY, $0.frame.minX) > ($1.frame.minY, $1.frame.minX)
            }
            guard let first = chips.first, chips.count > 2 else { return XCTFail("no chips at \(width) pt") }
            let top = chips.filter { $0.frame.minY == first.frame.minY }.sorted { $0.frame.minX < $1.frame.minX }
            guard top.count > 1 else { return XCTFail("one column at \(width) pt") }
            guard let second = chips.first(where: { $0.frame.minY < first.frame.minY }) else {
                return XCTFail("one row at \(width) pt")
            }
            let columns = top[1].frame.minX - top[0].frame.minX
            let rows = first.frame.minY - second.frame.minY
            let expected = min(columns, Tokens.Metric.settingsControl + Tokens.Metric.chromeGapWide)
            XCTAssertEqual(rows, expected, accuracy: 0.5, "the row pitch at \(width) pt")
        }
    }

    /// The chips are the popover's own, at the popover's own size: §6.2's grid
    /// and this one are one picker.
    func testTheChipsAreTheSizeEveryOtherPaletteDrawsThem() {
        for chip in swatches(laidOutEditor(width: 280)) {
            XCTAssertEqual(chip.frame.width, Tokens.Metric.settingsControl, accuracy: 0.001)
            XCTAssertEqual(chip.frame.height, Tokens.Metric.settingsControl, accuracy: 0.001)
        }
    }
}
