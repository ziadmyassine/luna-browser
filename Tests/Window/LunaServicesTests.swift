//
//  LunaServicesTests.swift
//  LunaTests
//
//  Open in Luna and Search with Luna, from the Services menu: what each
//  reads off the pasteboard another app hands over, and that `Info.plist`
//  names messages the provider answers.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class LunaServicesTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func put(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Open in Luna

    func testALinkHandedOverAsAURLOpens() {
        pasteboard.clearContents()
        pasteboard.writeObjects([url("https://example.com/a") as NSURL])
        XCTAssertEqual(LunaServices.links(on: pasteboard), [url("https://example.com/a")])
    }

    /// Selected text that is an address, typed the way people type them.
    func testSelectedTextThatIsAnAddressOpens() {
        put("https://example.com/page?q=1")
        XCTAssertEqual(LunaServices.links(on: pasteboard), [url("https://example.com/page?q=1")])
        put("  example.org/docs \n")
        XCTAssertEqual(LunaServices.links(on: pasteboard), [url("https://example.org/docs")])
    }

    /// A sentence with links in it opens each link, in order.
    func testTheLinksInASentenceOpen() {
        put("Read https://a.example.com/x first, then http://b.example.org/.")
        XCTAssertEqual(LunaServices.links(on: pasteboard), [url("https://a.example.com/x"), url("http://b.example.org/")])
    }

    func testNothingOffTheWebOpens() {
        for text in ["hello world", "javascript:alert(1)", "file:///etc/hosts", "mailto:someone@example.com", ""] {
            put(text)
            XCTAssertEqual(LunaServices.links(on: pasteboard), [], text)
        }
    }

    // MARK: - Search with Luna

    /// The user's engine, as the Command Bar's search row would send it.
    func testSelectedTextIsSearchedWithTheUsersEngine() {
        put("swift concurrency")
        XCTAssertEqual(LunaServices.search(on: pasteboard), CommandBarURL.search(for: "swift concurrency"))
        XCTAssertNotNil(LunaServices.search(on: pasteboard))
    }

    /// Text selected across lines is one query, not a query with line breaks.
    func testTextAcrossLinesIsOneQuery() {
        put("  first line\nsecond line\r\n")
        XCTAssertEqual(LunaServices.search(on: pasteboard), CommandBarURL.search(for: "first line second line"))
    }

    func testOnlyWhitespaceSearchesNothing() {
        put(" \n\t ")
        XCTAssertNil(LunaServices.search(on: pasteboard))
    }

    // MARK: - The provider

    /// Each service opens its page through the provider's one door, and an
    /// empty selection answers with an error instead of opening a blank tab.
    func testTheServicesOpenThroughTheProvider() {
        var opened: [[URL]] = []
        let services = LunaServices { opened.append($0) }
        var error: NSString?

        put("example.com")
        services.openURL(pasteboard, userData: nil, error: &error)
        XCTAssertNil(error)
        put("luna browser")
        services.search(pasteboard, userData: nil, error: &error)
        XCTAssertNil(error)
        XCTAssertEqual(opened, [[url("https://example.com")], [CommandBarURL.search(for: "luna browser")!]])

        put("no link here")
        services.openURL(pasteboard, userData: nil, error: &error)
        XCTAssertNotNil(error)
        XCTAssertEqual(opened.count, 2)
    }

    /// AppKit calls `<NSMessage>:userData:error:` on the provider; a message
    /// the provider does not answer is a menu item that does nothing.
    func testInfoPlistNamesMessagesTheProviderAnswers() throws {
        let services = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]])
        let messages = services.compactMap { $0["NSMessage"] as? String }
        XCTAssertEqual(messages, ["openURL", "search"])
        let provider = LunaServices { _ in }
        for message in messages {
            XCTAssertTrue(provider.responds(to: Selector("\(message):userData:error:")), message)
        }
        XCTAssertTrue(NSApp.servicesProvider is LunaServices)
    }
}
