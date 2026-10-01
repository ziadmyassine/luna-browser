//
//  HistoryTimestampTests.swift
//  LunaTests
//
//  §6.4's row is one label too wide for a 320 pt pop-out, and the label that
//  used to lose the argument was the one saying when — the panel's whole
//  point. `HistoryTimestamp` keeps the row's stamp to the clock and names the
//  day in the header over it (§11.3); these assert the branches it picks and
//  that the stamp stays inside the width the row has for it.
//
//  Fixed dates and an injected `now`: the branches are midnights and a year
//  boundary apart, and none is worth waiting for. The dates are built
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

    /// The day is the header's (§11.3), so a row spends its width on the clock
    /// whatever day it is under.
    func testARowIsStampedWithTheTimeAlone() {
        for when in [date(2026, 9, 20), date(2025, 12, 31, 23, 59)] {
            XCTAssertEqual(HistoryTimestamp.string(for: when), clock.string(from: when))
        }
    }

    /// Late last night is yesterday, however few hours ago it was.
    func testTheHeaderNamesTodayAndYesterdayByCalendarDay() {
        let now = date(2026, 9, 20, 0, 30)
        XCTAssertEqual(HistoryTimestamp.day(for: date(2026, 9, 20, 0, 10), now: now, calendar: calendar), String(localized: "Today"))
        XCTAssertEqual(HistoryTimestamp.day(for: date(2026, 9, 19, 23, 30), now: now, calendar: calendar), String(localized: "Yesterday"))
    }

    /// Inside a week a weekday names one day; from seven days back it would
    /// name today's weekday too, so the date takes over.
    func testTheHeaderNamesTheWeekdayForTheRestOfTheWeek() {
        let now = date(2026, 9, 20)
        let weekday = reference(template: "EEEE")
        for back in 2...6 {
            let when = date(2026, 9, 20 - back)
            XCTAssertEqual(HistoryTimestamp.day(for: when, now: now, calendar: calendar), weekday.string(from: when))
        }
        let weekAgo = date(2026, 9, 13)
        XCTAssertEqual(
            HistoryTimestamp.day(for: weekAgo, now: now, calendar: calendar),
            reference(template: "EEEE d MMMM").string(from: weekAgo)
        )
    }

    /// The year is only worth its width once it is not this one.
    func testTheYearAppearsOnlyOnceItIsNotTheCurrentOne() {
        let now = date(2026, 9, 20)
        let thisYear = date(2026, 1, 3)
        let lastYear = date(2025, 12, 31)
        XCTAssertEqual(
            HistoryTimestamp.day(for: thisYear, now: now, calendar: calendar),
            reference(template: "EEEE d MMMM").string(from: thisYear)
        )
        XCTAssertEqual(
            HistoryTimestamp.day(for: lastYear, now: now, calendar: calendar),
            reference(template: "EEEE d MMMM y").string(from: lastYear)
        )
    }

    /// The stamp never gives way in its row, so it has to be a stamp that
    /// fits: §6.4's panel leaves a 244 pt text column shared with a title and
    /// a host. The old `"Sep 20, 2026 at 12:24 PM"` measured 135 pt of it.
    func testEveryStampFitsTheWidthTheRowWillNotTakeBackFromIt() {
        for when in [date(2026, 9, 20), date(2026, 9, 19, 23, 59), date(2025, 11, 11, 10, 0)] {
            let stamp = HistoryTimestamp.string(for: when)
            let width = (stamp as NSString).size(withAttributes: [.font: Tokens.TypeScale.rowTimestamp]).width
            XCTAssertLessThan(width, 80, "\(stamp) is \(width) pt — wider than the row can spare")
        }
    }
}
