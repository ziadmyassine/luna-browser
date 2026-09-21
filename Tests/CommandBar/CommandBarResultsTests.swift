//
//  CommandBarResultsTests.swift
//  LunaTests
//
//  §9.2's list, and the one piece of it the user watches move: the highlight.
//
//  UI-SPEC §3.4 draws it as one translucent pill that travels, rather than a
//  fill per row, and §6's `selectedRowMove` is the only thing it is allowed to
//  travel for. Everything else — a re-rank, the history landing, the engine's
//  suggestions — is the list changing under a highlight that has not moved, and
//  a slide there is the pill going somewhere it was never asked to go.
//

import XCTest
@testable import Luna

@MainActor
final class CommandBarSelectionPillTests: XCTestCase {

    private func result(_ name: String) -> CommandBarResult {
        CommandBarResult(
            source: .history,
            title: name,
            subtitle: "\(name).com",
            action: .open(URL(string: "https://\(name).com")!),
            url: URL(string: "https://\(name).com")!,
            symbolName: "clock"
        )
    }

    /// A list at its natural height, laid out the way the panel lays it out.
    private func list(_ names: [String], selecting id: String? = nil) -> CommandBarResultsView {
        let view = CommandBarResultsView(frame: .zero)
        let rows = names.map(result)
        view.setResults(rows, selecting: id)
        view.frame = NSRect(
            x: 0,
            y: 0,
            width: Tokens.Metric.commandBarMinWidth,
            height: Tokens.Metric.rowHeight * CGFloat(rows.count)
        )
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The highlight itself: the one glass backing in the list.
    private func pill(in view: CommandBarResultsView) throws -> NSView {
        try XCTUnwrap(view.subviews.first { NSStringFromClass(type(of: $0)).contains("GlassBacking") })
    }

    /// Where a row of this list is, counted from the top.
    private func row(_ index: Int, in view: CommandBarResultsView) -> NSRect {
        let height = Tokens.Metric.rowHeight
        return NSRect(
            x: view.bounds.minX + Tokens.Metric.rowInset,
            y: view.bounds.maxY - height * CGFloat(index + 1),
            width: view.bounds.width - 2 * Tokens.Metric.rowInset,
            height: height
        )
    }

    /// On the row it says it is on, on the first pass. Nothing else in the
    /// bar tells the user which result `⏎` will take — the row's brighter text
    /// is the same step the pill is drawn in.
    func testTheHighlightLandsOnTheSelectedRow() throws {
        let view = list(["apple", "openai", "github"])
        XCTAssertEqual(try pill(in: view).frame, row(0, in: view))
    }

    /// A rebuilt list does not leave the highlight behind. This is the one
    /// that broke while somebody typed fast: the list is replaced on every
    /// keystroke and again when the history lands, and the pill used to be
    /// moved from `setResults` — against rows that had not been laid out at
    /// their new size yet, so it slid somewhere slightly wrong and the next
    /// layout pass pulled it back.
    func testAReplacedListPutsTheHighlightOnTheNewRowsOwnPlace() throws {
        let view = list(["apple", "openai", "github"])
        let second = result("github")
        view.setResults([result("zed"), result("apple"), second], selecting: second.id)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try pill(in: view).frame, row(2, in: view))
    }

    /// And ↓ moves it to the row below, on a list that has not otherwise
    /// changed — the one case §6's `selectedRowMove` is for.
    func testMovingTheSelectionMovesTheHighlight() throws {
        let view = list(["apple", "openai", "github"])
        view.select(id: result("openai").id)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(try pill(in: view).frame, row(1, in: view))
    }

    /// A query with no answers has nothing to highlight, and a pill left over a
    /// row that is not there any more is worse than no pill.
    func testAnEmptyListShowsNoHighlight() throws {
        let view = list(["apple", "openai"])
        view.setResults([], selecting: nil)
        view.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.commandBarMinWidth, height: 0)
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try pill(in: view).isHidden)
    }
}
