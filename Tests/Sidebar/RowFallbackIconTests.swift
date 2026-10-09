//
//  RowFallbackIconTests.swift
//  LunaTests
//
//  The icon a tab without a favicon wears, and how high a symbol stands.
//

import XCTest
@testable import Luna

@MainActor
final class RowFallbackIconTests: XCTestCase {

    func testAFileOrALocalServerWearsItsKind() throws {
        let symbol = { (text: String) in SidebarRowContent.fallbackSymbol(for: try XCTUnwrap(URL(string: text))) }
        XCTAssertEqual(try symbol("file:///Users/me/Astro/Lisbon%20trip.md"), "doc.text")
        XCTAssertEqual(try symbol("file:///Users/me/site/index.html"), "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(try symbol("file:///Users/me/Downloads/ticket.pdf"), "doc.richtext")
        XCTAssertEqual(try symbol("http://localhost:3000/"), "server.rack")
        XCTAssertEqual(try symbol("http://127.0.0.1:8080/app"), "server.rack")
        XCTAssertEqual(try symbol("http://[::1]:5173/"), "server.rack")
        XCTAssertEqual(try symbol("https://myapp.test/"), "server.rack")
        XCTAssertEqual(try symbol("https://example.com/"), SidebarRowContent.siteFallbackSymbol)
    }

    /// The globe's ink is centred in its box and `plus`'s is low in it, so
    /// the plus is lifted further — one lift for both stood the globe high.
    func testEachSymbolIsLiftedByWhereItsOwnInkSits() {
        let size = Tokens.Metric.faviconSize
        XCTAssertEqual(SymbolInk.drop("globe", pointSize: size), 0, accuracy: 0.5)
        XCTAssertGreaterThan(SymbolInk.drop("plus", pointSize: size), SymbolInk.drop("globe", pointSize: size))
    }
}
