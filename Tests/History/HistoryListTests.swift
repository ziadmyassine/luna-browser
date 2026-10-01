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
                title: "A visited page \(index)",
                subtitle: "example.com",
                when: "12:00",
                host: "example.com",
                url: URL(string: "https://example.com/\(index)")!
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

    /// The highlight, not the hover pill parked beside it for marking (§11.3).
    private func pill(in list: HistoryListView) -> RowPillView {
        let pill = list.selection
        XCTAssertTrue(descendants(of: list, ofType: RowPillView.self).contains(pill), "the list has no selection pill")
        return pill
    }

    /// The pill is the list's width less `rowInset` each side — never the
    /// width of whatever the table happened to be when the list was filled.
    func testTheSelectionPillSpansTheRowOnceTheListHasBeenLaidOut() throws {
        let pill = pill(in: list(showing: entries(30)))
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
        let pill = pill(in: list)
        XCTAssertEqual(
            pill.frame,
            table.rect(ofRow: 0).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset),
            "the pill is not on the row it is highlighting"
        )
        XCTAssertEqual(pill.alphaValue, 1, "the pill is placed but not shown")
    }

    /// A day's header is a row of the table but not a page: the pill skips it
    /// and lands on the first page under it (§11.3).
    func testTheSelectionPillSkipsADaysHeader() throws {
        let dated = entries(3).enumerated().map { index, entry in
            HistoryEntry(
                id: entry.id, title: entry.title, subtitle: entry.subtitle, when: entry.when,
                host: entry.host, url: entry.url, day: index == 0 ? "Today" : "Yesterday"
            )
        }
        let list = list(showing: dated)
        let table = try XCTUnwrap(descendants(of: list, ofType: NSTableView.self).first)
        XCTAssertEqual(table.numberOfRows, 5, "two headers and three pages")
        XCTAssertEqual(table.rect(ofRow: 0).height, Tokens.Metric.historyDayHeaderHeight)
        XCTAssertEqual(
            pill(in: list).frame,
            table.rect(ofRow: 1).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        )
    }

    /// The point of the table. A thousand pages is days of ordinary use, and
    /// it must not be a thousand built rows — that was 35 s of frozen app
    /// before the pop-out appeared. See `BudgetTests`.
    func testALongHistoryBuildsOnlyTheRowsThePanelIsTall() {
        let list = list(showing: entries(1000))
        let rows = descendants(of: list, ofType: HistoryRowView.self).count
        XCTAssertGreaterThan(rows, 0, "the list drew nothing at all")
        XCTAssertLessThan(rows, 40, "\(rows) rows built for a panel that shows about ten")
    }
}
