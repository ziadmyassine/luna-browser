//
//  OpenURLTests.swift
//  LunaTests
//
//  A web link handed to Luna by another app. The two halves that are
//  decisions: which links Luna takes, and what happens to one that arrives
//  before there is a window to open it in.
//

import XCTest
@testable import Luna

@MainActor
final class OpenURLTests: XCTestCase {

    private func url(_ text: String) -> URL { URL(string: text)! }

    /// Only the schemes `Info.plist` claims.
    func testTakesWebLinksAndNothingElse() {
        let links = [
            url("https://example.com/"),
            url("HTTP://example.org/page"),
            url("mailto:someone@example.com"),
            url("file:///Users/someone/page.html"),
            url("ftp://example.net/")
        ]
        XCTAssertEqual(
            AppDelegate.webPages(in: links),
            [url("https://example.com/"), url("HTTP://example.org/page")]
        )
    }

    /// A link that launched Luna waits for the window instead of being lost.
    func testALinkBeforeLaunchIsKeptForTheWindow() {
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [url("https://example.com/")])
        delegate.application(NSApplication.shared, open: [url("mailto:someone@example.com")])
        delegate.application(NSApplication.shared, open: [url("https://example.org/")])
        XCTAssertEqual(delegate.linksBeforeLaunch, [url("https://example.com/"), url("https://example.org/")])
    }

    /// Once launch has taken them, nothing is kept back for later: a link
    /// from then on opens straight away.
    func testLaunchTakesTheKeptLinksOnce() {
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, open: [url("https://example.com/")])
        delegate.openLinksFromLaunch()
        XCTAssertNil(delegate.linksBeforeLaunch)
    }
}
