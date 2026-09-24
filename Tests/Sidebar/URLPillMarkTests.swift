//
//  URLPillMarkTests.swift
//  LunaTests
//
//  §3.2's leading mark: the glyph that says whether what is in the address bar
//  is a place or a question.
//
//  The whole value of it is that it answers before Return does, so the one
//  thing worth asserting is that it and Return cannot disagree: the mark asks
//  `CommandBarURL.direct` exactly as the commit path does. A pill showing a
//  globe that then runs a search is worse than no mark at all, because the user
//  has been told something.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class URLPillMarkTests: XCTestCase {

    private typealias Mark = URLPillView.LeadingMark

    // MARK: - Questions

    func testAPhraseIsASearch() {
        XCTAssertEqual(Mark.reading("app store connect"), .search)
    }

    /// The case the rule exists for: one word, no dot. Sent as an address it is
    /// a doomed DNS lookup, so `CommandBarURL` calls it a search and the mark
    /// has to agree.
    func testABareWordIsASearch() {
        XCTAssertEqual(Mark.reading("colour"), .search)
    }

    func testAnEmptyPillIsASearch() {
        XCTAssertEqual(Mark.reading(""), .search)
        XCTAssertEqual(Mark.reading("   "), .search)
    }

    /// A page Luna serves itself is nowhere on the web, and `luna://` is a
    /// scheme the bar accepts — so without this the archive wore a globe.
    func testLunasOwnPagesAreASearch() {
        XCTAssertEqual(Mark.reading("luna://history"), .search)
    }

    // MARK: - Places

    /// A host Luna has never fetched an icon for, so this is the globe and
    /// nothing else. A real domain would be a flaky assertion: whether
    /// `apple.com` answers `.link` or `.site` depends on what is in the icon
    /// cache on the machine running the test, and both are correct.
    private let unvisited = "\(UUID().uuidString.lowercased()).example"

    func testADomainWithNoIconYetIsAGlobe() {
        XCTAssertEqual(Mark.reading(unvisited), .link)
    }

    func testAFullAddressIsAPlaceToo() {
        XCTAssertNotEqual(Mark.reading("https://apple.com/iphone"), .search)
    }

    /// `localhost:3000` has no dot in it at all, and is the one address a
    /// developer types most often.
    func testLocalhostIsAPlace() {
        XCTAssertNotEqual(Mark.reading("localhost:3000"), .search)
    }

    /// The favicon branch: a site Luna has a mark for wears it rather than the
    /// globe. Skipped rather than failed when the cache has nothing — the
    /// branch is about what happens when there is an icon.
    func testASiteWithAnIconWearsIt() throws {
        guard let icon = SidebarIcons.shared.favicon(for: URL(string: "https://apple.com")!) else {
            throw XCTSkip("no cached icon on this machine — nothing to assert")
        }
        XCTAssertEqual(Mark.reading("apple.com"), .site(icon))
    }

    // MARK: - The agreement

    /// The property the mark is for: whichever glyph it picks, committing the
    /// same string goes the same way. Nothing here asserts a particular
    /// reading — `CommandBarURL` owns that — only that the two never part.
    func testTheMarkNeverDisagreesWithWhatReturnWouldDo() {
        let inputs = [
            "apple.com", "app store connect", "colour", "https://example.com/a?b=1",
            "localhost:3000", "127.0.0.1:8080", "example.com/path with space",
            "", "luna://history", "ftp://example.com", "a.b.c.d.example.co.uk"
        ]
        for input in inputs {
            let isAddress = CommandBarURL.direct(from: input) != nil
                && InternalPages.name(for: CommandBarURL.direct(from: input)!) == nil
            let mark = Mark.reading(input)
            XCTAssertEqual(
                mark != .search, isAddress,
                "\(input.isEmpty ? "«empty»" : input): the mark says \(mark) and Return would not"
            )
        }
    }
}
