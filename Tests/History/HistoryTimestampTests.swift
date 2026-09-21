//
//  HistoryTimestampTests.swift
//  LunaTests
//
//  §6.4's row is one label too wide for a 320 pt pop-out, and the label that
//  used to lose the argument was the one saying when — the panel's whole
//  point. `HistoryTimestamp` is what keeps the stamp short enough to survive;
//  these assert that it picks the right branch and stays inside the width the
//  row has for it.
//
//  Fixed dates and an injected `now`: the three branches are a midnight and a
//  year boundary apart, and neither is worth waiting for. The dates are built
//  in `Calendar.current` and checked against locally-built formatters rather
//  than against English strings — the branch is the decision under test, and a
//  machine set to another language still has to take the same one.
//

import AppKit
import XCTest
@testable import Luna

final class HistoryTimestampTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 24) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? Date()
    }

    private func reference(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private var clock: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    /// Today is the panel's business — a tab you closed a minute ago and want
    /// back — so the day is not in question and the stamp spends its width on
    /// the clock.
    func testATabClosedTodayIsStampedWithTheTimeAlone() {
        let when = date(2026, 9, 20)
        let stamp = HistoryTimestamp.string(for: when, now: date(2026, 9, 20, 17, 0), calendar: calendar)
        XCTAssertEqual(stamp, clock.string(from: when))
    }

    /// Late last night is not this morning, however few hours ago it was.
    func testYesterdayIsADateEvenAnHourBeforeMidnight() {
        let when = date(2026, 9, 19, 23, 30)
        let stamp = HistoryTimestamp.string(for: when, now: date(2026, 9, 20, 0, 30), calendar: calendar)
        XCTAssertEqual(stamp, reference(template: "d MMM").string(from: when))
        XCTAssertNotEqual(stamp, clock.string(from: when))
    }

    /// The year is only worth its width once it is not this one.
    func testTheYearAppearsOnlyOnceItIsNotTheCurrentOne() {
        let now = date(2026, 9, 20)
        let thisYear = date(2026, 1, 3)
        let lastYear = date(2025, 12, 31)
        XCTAssertEqual(
            HistoryTimestamp.string(for: thisYear, now: now, calendar: calendar),
            reference(template: "d MMM").string(from: thisYear)
        )
        XCTAssertEqual(
            HistoryTimestamp.string(for: lastYear, now: now, calendar: calendar),
            reference(template: "d MMM y").string(from: lastYear)
        )
    }

    /// The point of all three branches. §6.4's panel is 320 pt wide, which
    /// leaves a 244 pt text column shared with a title and a host; the stamp
    /// never gives way, so it has to be a stamp that fits. The old
    /// `"Sep 20, 2026 at 12:24 PM"` measured 135 pt of it on its own.
    func testEveryStampFitsTheWidthTheRowWillNotTakeBackFromIt() {
        let now = date(2026, 9, 20)
        let sampled = [date(2026, 9, 20), date(2026, 9, 19), date(2025, 12, 31), date(2025, 11, 11, 23, 59)]
        for when in sampled {
            let stamp = HistoryTimestamp.string(for: when, now: now, calendar: calendar)
            let width = (stamp as NSString).size(withAttributes: [.font: Tokens.TypeScale.rowTimestamp]).width
            XCTAssertLessThan(width, 80, "\(stamp) is \(width) pt — wider than the row can spare")
        }
    }
}
