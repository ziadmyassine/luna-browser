//
//  SectionListTests.swift
//  LunaTests
//
//  §2's section list against the browser's sidebar, which is the list it is
//  supposed to be a copy of.
//

import XCTest
@testable import Luna

/// §2's list is the browser's sidebar with sections where the tabs are. These
/// are the four ways that claim can be wrong: a different pitch, a different
/// pill, a different column for the glyph and the title, or a fill that is not
/// the sidebar's glass at all.
@MainActor
final class SettingsSectionListMatchesTheSidebarTests: XCTestCase {

    private func laidOutList(rows: Int = 3) -> SettingsSectionList {
        let list = SettingsSectionList(
            titles: (0..<rows).map { "Section \($0)" },
            symbols: Array(repeating: "gearshape", count: rows)
        )
        list.frame = NSRect(x: 0, y: 0, width: SettingsMetrics.listWidth, height: 400)
        list.layoutSubtreeIfNeeded()
        return list
    }

    private func pills(_ list: SettingsSectionList) -> [RowPillView] {
        list.subviews.compactMap { $0 as? RowPillView }
    }

    private func rowViews(_ list: SettingsSectionList) -> [SettingsSectionRowView] {
        list.subviews.compactMap { $0 as? SettingsSectionRowView }
    }

    /// The sidebar's pitch, and the sidebar's paint inside it.
    func testTheListStandsOnTheSidebarsOwnPitch() {
        let list = laidOutList()
        XCTAssertEqual(SettingsMetrics.sectionRowHeight, Tokens.Metric.rowHeight)
        XCTAssertEqual(SettingsMetrics.sectionPillHeight, Tokens.Metric.rowPillHeight)
        XCTAssertEqual(
            list.intrinsicContentSize.height,
            3 * Tokens.Metric.rowHeight - Tokens.Metric.rowGap,
            accuracy: 0.001,
            "the list asks for its rows' height — the gap comes out of the last row's pitch"
        )
        let rows = rowViews(list)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].frame.height, Tokens.Metric.rowPillHeight, accuracy: 0.001)
        XCTAssertEqual(rows[1].frame.minY - rows[0].frame.minY, Tokens.Metric.rowHeight, accuracy: 0.001)
    }

    /// §3.4's glass, moved — not a wash painted on the row. A row that paints
    /// its own background is the design this replaced.
    func testTheFillsAreTheSidebarsGlassPillsAndTheRowsPaintNothing() {
        let list = laidOutList()
        XCTAssertEqual(pills(list).count, 2, "one selected pill and one hover pill, shared by every row")
        for row in rowViews(list) {
            XCTAssertNil(
                row.layer?.backgroundColor,
                "a section row draws nothing: the fills belong to the list"
            )
            XCTAssertEqual(row.subviews.count, 2, "a glyph and a title — and no tile behind the glyph")
        }
    }

    /// The selected pill lies where a selected tab's does: the row, inset by
    /// `rowInset` at each edge and by nothing at all vertically.
    func testTheSelectedPillIsTheRowInsetLikeATabs() {
        let list = laidOutList()
        list.select(1)
        list.layoutSubtreeIfNeeded()
        guard let selected = pills(list).first else { return XCTFail("no selection pill") }
        let row = rowViews(list)[1].frame
        XCTAssertEqual(selected.frame, row.insetBy(dx: Tokens.Metric.rowInset, dy: 0))
        XCTAssertEqual(selected.alphaValue, 1, accuracy: 0.001)
    }

    /// The hover lift never lands on the row the selection is already on —
    /// two washes on one row is one wash too many.
    func testTheHoverPillStaysOffTheSelectedRow() {
        let list = laidOutList()
        list.select(1)
        let rows = rowViews(list)
        guard let hover = pills(list).last else { return XCTFail("no hover pill") }

        rows[1].onHover?(true)
        XCTAssertEqual(hover.alphaValue, 0, accuracy: 0.001)

        rows[2].onHover?(true)
        XCTAssertEqual(hover.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(hover.frame, rows[2].frame.insetBy(dx: Tokens.Metric.rowInset, dy: 0))

        rows[2].onHover?(false)
        XCTAssertEqual(hover.alphaValue, 0, accuracy: 0.001, "the pointer left the list; so does the lift")
    }

    /// And the two columns inside the row are the tab row's two columns, so a
    /// section's glyph and a tab's favicon stand on the same line.
    func testTheGlyphAndTheTitleUseTheSidebarsColumns() {
        let list = laidOutList()
        let row = rowViews(list)[0]
        row.layoutSubtreeIfNeeded()
        guard let icon = row.subviews.compactMap({ $0 as? NSImageView }).first,
              let title = row.subviews.compactMap({ $0 as? NSTextField }).first else {
            return XCTFail("a section row is a glyph and a title")
        }
        XCTAssertEqual(icon.frame.minX, Tokens.Metric.rowFaviconInset, accuracy: 0.5)
        XCTAssertEqual(icon.frame.width, Tokens.Metric.faviconSize, accuracy: 0.001)
        XCTAssertEqual(title.frame.minX, Tokens.Metric.rowTitleInset, accuracy: 0.5)
        XCTAssertEqual(title.font, Tokens.TypeScale.sidebarRow, "§1: the sidebar's own face")
    }
}
