//
//  ClearCookiesCommandTests.swift
//  LunaTests
//
//  §9.2's Clear Cookies, below the ranking: which site it is offered for, and
//  that what it clears is that site's cookies and storage and nothing else.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class ClearCookiesCommandTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The site is the registrable domain of the page in front, and a page
    /// that is not on the web has none.
    func testTheActiveSiteIsTheFrontPagesRegistrableDomain() async throws {
        let session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        session.newTab(url: URL(string: "https://developer.apple.com/xcode/")!)
        XCTAssertEqual(session.activeSite, "apple.com")
        session.newTab(url: URL(string: "luna://settings")!)
        XCTAssertNil(session.activeSite)
        session.tearDown()
    }

    /// Cookies and storage for the site go; its cache and every other site's
    /// cookies stay. A non-persistent store, so nothing is left in a jar on disk.
    func testOnlyTheSitesCookiesGo() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        for domain in [".apple.com", "example.com"] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: domain, .path: "/", .name: "session", .value: "1", .secure: "TRUE",
                .expires: Date().addingTimeInterval(3600)
            ]))
            await store.httpCookieStore.setCookie(cookie)
        }
        await BrowserSession.removeWebsiteData(ofSite: "apple.com", from: store, types: BrowserSession.cookieDataTypes)
        let left = await store.httpCookieStore.allCookies().map(\.domain)
        XCTAssertEqual(left, ["example.com"])
        XCTAssertFalse(BrowserSession.cookieDataTypes.contains(WKWebsiteDataTypeDiskCache), "Clear Cookies empties the cache")
    }
}
