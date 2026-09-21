//
//  CommandBarModeTests.swift
//  LunaTests
//
//  §9.1: which tab a chosen result lands in, and what the field starts with.
//
//  These two used to be one thing, and the New Tab page paid for it: its pill
//  presented the bar as `.newTab`, so committing opened a second tab and left
//  the empty page behind the one you were reading.
//

import XCTest
@testable import Luna

final class CommandBarModeTests: XCTestCase {

    func testOnlyNewTabOpensANewTab() {
        XCTAssertTrue(CommandBarMode.newTab.opensNewTab)
        XCTAssertFalse(CommandBarMode.editCurrentURL.opensNewTab)
        XCTAssertFalse(CommandBarMode.search("").opensNewTab)
        XCTAssertFalse(CommandBarMode.search("apple.com").opensNewTab)
    }

    func testPrefillComesFromTheModeThatAskedForIt() {
        XCTAssertEqual(CommandBarMode.newTab.prefill { "https://current" }, "")
        XCTAssertEqual(CommandBarMode.editCurrentURL.prefill { "https://current" }, "https://current")
        XCTAssertEqual(CommandBarMode.search("half typed").prefill { "https://current" }, "half typed")
    }

    /// The New Tab page hands off an empty string, and that must not be
    /// mistaken for `⌘T` — it is the one case the old code got wrong.
    func testTheNewTabPagePillIsEmptyButStaysOnItsTab() {
        let fromPill = CommandBarMode.search("")
        XCTAssertEqual(fromPill.prefill { "luna://newtab" }, "")
        XCTAssertFalse(fromPill.opensNewTab)
    }

    func testCurrentURLIsNotReadWhenTheModeDoesNotWantIt() {
        var reads = 0
        _ = CommandBarMode.newTab.prefill { reads += 1; return "" }
        _ = CommandBarMode.search("x").prefill { reads += 1; return "" }
        XCTAssertEqual(reads, 0)
    }
}
