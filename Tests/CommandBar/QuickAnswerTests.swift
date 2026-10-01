//
//  QuickAnswerTests.swift
//  LunaTests
//
//  §9.2's maths and unit answers, and Clear Cookies: what parses, what does
//  not, and where each lands in the list. The second half matters as much as
//  the first — a query that is not a sum must not lose its top row to one.
//

import XCTest
@testable import Luna

final class QuickAnswerTests: XCTestCase {

    private func value(_ query: String) -> String? {
        QuickAnswer.answer(for: query)?.value
    }

    // MARK: - Sums

    func testArithmeticIsAnswered() {
        let cases = [
            ("5+5", "10"), ("2 * (3 + 4)", "14"), ("10/4", "2.5"), ("6 × 7", "42"), ("7 ÷ 2", "3.5"),
            ("5 − 2", "3"), ("2^10", "1024"), ("2^3^2", "512"), ("-2^2", "-4"), ("(1+2)*-3", "-9")
        ]
        for (query, answer) in cases {
            XCTAssertEqual(value(query), answer, query)
        }
    }

    /// Twelve significant digits, so floating point's leftovers do not show.
    func testAnswersAreRoundedPastFloatingPointNoise() {
        XCTAssertEqual(value("0.1 + 0.2"), "0.3")
        XCTAssertEqual(value("1/3"), "0.333333333333")
    }

    /// A decimal comma is read, and answered in kind.
    func testADecimalCommaIsAnsweredWithOne() {
        XCTAssertEqual(value("3,5 + 1"), "4,5")
        XCTAssertEqual(value("1.5 * 2"), "3")
    }

    /// `%` after a number is per cent; between two numbers it is the remainder.
    func testPercentAndRemainder() {
        XCTAssertEqual(value("15%"), "0.15")
        XCTAssertEqual(value("200 * 15%"), "30")
        XCTAssertEqual(value("10 % 3"), "1")
    }

    /// A number on its own is not a question, a half-typed sum has no answer
    /// yet, and a query that only starts with a digit is a search.
    func testWhatIsNotASumIsNotAnswered() {
        for query in ["42", "-5", "(5)", "5+", "1/0", "2 * (3", "", "iphone 15", "2024 olympics", "1.2.3.4", "3d printer"] {
            XCTAssertNil(QuickAnswer.answer(for: query), query)
        }
    }

    // MARK: - Conversions

    func testUnitsAreConverted() {
        let cases = [
            ("5 km in miles", "3.10686 mi"), ("5km in mi", "3.10686 mi"), ("70 f to c", "21.1111 °C"),
            ("70 °F to °C", "21.1111 °C"), ("2 gb in mb", "2000 MB"), ("100 km/h to mph", "62.1371 mph"),
            ("1 day in hours", "24 hr"), ("2 weeks in days", "14 d"), ("8 fl oz to ml", "236.588 mL"),
            ("3,5 kg in lb", "7,71618 lb"), ("12 in in cm", "30.48 cm"), ("-40 c to f", "-40 °F")
        ]
        for (query, answer) in cases {
            XCTAssertEqual(value(query), answer, query)
        }
    }

    func testDifferentKindsAndUnknownUnitsAreNotConverted() {
        for query in ["5 kg in km", "5 parsecs in km", "5 km in", "10 to 20", "5 km miles"] {
            XCTAssertNil(QuickAnswer.answer(for: query), query)
        }
    }

    func testTheQuestionIsWrittenInTheUnitsSymbols() {
        XCTAssertEqual(QuickAnswer.answer(for: "5 kilometres to miles")?.question, "5 km in mi")
    }

    // MARK: - In the list

    private func merge(_ query: String, site: String? = nil) -> [CommandBarResult] {
        var sources = CommandBarSources()
        sources.activeSite = site
        return CommandBarRanking.merge(query: query, sources: sources, limit: 8)
    }

    /// The answer leads, and the search for the same words comes second.
    func testAnAnswerIsTheTopRowAndCopies() {
        let rows = merge("5 km in miles")
        XCTAssertEqual(rows.first?.source, .answer)
        XCTAssertEqual(rows.first?.action, .copy("3.10686 mi"))
        XCTAssertEqual(rows.dropFirst().first?.source, .search)
        XCTAssertNil(CommandBarRanking.autofill(query: "5+5", results: merge("5+5")), "an answer was autofilled")
    }

    func testClearCookiesIsFoundByNameAndByWhatItDoes() {
        let byName = merge("cookies", site: "github.com")
        let row = byName.first { $0.action == .command(.clearCookies) }
        XCTAssertEqual(row?.subtitle, "github.com")
        XCTAssertEqual(row?.source, .command)
        XCTAssertTrue(merge("clear cookies", site: "github.com").contains { $0.action == .command(.clearCookies) })
        let byKeyword = merge("clear site data", site: "github.com")
        XCTAssertEqual(byKeyword.first { $0.action == .command(.clearCookies) }?.source, .keywordShortcut)
    }

    /// With no site in the active tab there is nothing for it to clear.
    func testClearCookiesNeedsASite() {
        XCTAssertFalse(merge("cookies").contains { $0.action == .command(.clearCookies) })
    }
}
