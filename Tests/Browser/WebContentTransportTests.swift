//
//  WebContentTransportTests.swift
//  LunaTests
//
//  App Transport Security applies to a `WKWebView` inside an app unless the
//  app's `Info.plist` exempts web content. Without the exemption every plain
//  `http` page is refused before the request leaves the machine — including
//  the ones whose server would have redirected to `https` a moment later,
//  which is how most shortened links arrive.
//

import XCTest
@testable import Luna

final class WebContentTransportTests: XCTestCase {

    private var transport: [String: Any] {
        Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any] ?? [:]
    }

    func testWebContentMayLoadOverPlainHTTP() {
        XCTAssertEqual(transport["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
    }

    /// The exemption is for pages, not for Luna. Its own requests — favicons,
    /// rule lists, suggestions — still have to be `https`.
    func testLunasOwnRequestsAreNotExempt() {
        XCTAssertNil(transport["NSAllowsArbitraryLoads"])
    }
}
