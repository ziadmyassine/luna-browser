//
//  HistoryListTests.swift
//  LunaTests
//
//  §6.4's list, and the two things that stopped being obvious when it became a
//  recycling table: that there are only as many rows as the panel is tall, and
//  that the one glass pill still lands on the row it belongs to.
//
//  The pill is the part that needed a test. It is measured off
//  `NSTableView.rect(ofRow:)`, and the list is filled from `panelDidAppear` —
//  before the pop-out has been laid out — so the first placement reads a table
//  that has not been given its width yet. That shipped for one build: the pill
//  came up the width of a favicon and stayed there until the pointer moved it.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class HistoryListTests: XCTestCase {

    private static let width: CGFloat = 304
    private static let height: CGFloat = 380

    private func entries(_ count: Int) -> [HistoryEntry] {
        (0..<count).map { index in
            HistoryEntry(
                id: UUID(),
                title: "A closed tab \(index)",
                subtitle: "example.com",
                when: "12:00",
                host: "example.com",
                searchText: "a closed tab \(index) example.com"
            )
        }
    }

    /// In a window and laid out, which is the state the assertions are about —
    /// a list that has never been through `layout` has never placed its pill.
    private func list(showing entries: [HistoryEntry]) -> HistoryListView {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentLayoutRect)
        let list = HistoryListView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        window.contentView?.addSubview(list)
        list.setEntries(entries)
        window.contentView?.layoutSubtreeIfNeeded()
        list.layoutSubtreeIfNeeded()
        return list
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        var found: [T] = []
        for child in root.subviews {
            if let match = child as? T { found.append(match) }
            found += descendants(of: child, ofType: type)
        }
        return found
    }

    private func pill(in list: HistoryListView) throws -> RowPillView {
        try XCTUnwrap(descendants(of: list, ofType: RowPillView.self).first, "the list has no selection pill")
    }

    /// The pill is the list's width less `rowInset` each side — never the
    /// width of whatever the table happened to be when the list was filled.
    func testTheSelectionPillSpansTheRowOnceTheListHasBeenLaidOut() throws {
        let pill = try pill(in: list(showing: entries(30)))
        XCTAssertEqual(
            pill.frame.width,
            Self.width - 2 * Tokens.Metric.rowInset,
            accuracy: 0.5,
            "the pill was measured off a table that had not been given its width"
        )
    }

    /// And it is on the first row, which is the one `setEntries` selects.
    func testTheSelectionPillSitsOnTheSelectedRow() throws {
        let list = list(showing: entries(30))
        let table = try XCTUnwrap(descendants(of: list, ofType: NSTableView.self).first)
        let pill = try pill(in: list)
        XCTAssertEqual(
            pill.frame,
            table.rect(ofRow: 0).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset),
            "the pill is not on the row it is highlighting"
        )
        XCTAssertEqual(pill.alphaValue, 1, "the pill is placed but not shown")
    }

    /// The point of the table. A thousand archived tabs is a fortnight of
    /// ordinary use, and it must not be a thousand built rows — that was 35 s
    /// of frozen app before the pop-out appeared. See `BudgetTests`.
    func testALongArchiveBuildsOnlyTheRowsThePanelIsTall() {
        let list = list(showing: entries(1000))
        let rows = descendants(of: list, ofType: HistoryRowView.self).count
        XCTAssertGreaterThan(rows, 0, "the list drew nothing at all")
        XCTAssertLessThan(rows, 40, "\(rows) rows built for a panel that shows about ten")
    }
}
