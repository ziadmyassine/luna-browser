//
//  CommandBarURLTests.swift
//  LunaTests
//
//  §9.2's "direct URL / IP / `localhost` detection", and §9.6's local-only
//  guarantee — the second one enforced rather than asserted in prose.
//

import XCTest
@testable import Luna

final class CommandBarURLDetectionTests: XCTestCase {

    private func detected(_ input: String) -> String? {
        CommandBarURL.direct(from: input)?.absoluteString
    }

    /// A bare host gets `https`, because in 2026 assuming otherwise is a downgrade.
    func testPlainDomainsBecomeHTTPS() {
        XCTAssertEqual(detected("example.com"), "https://example.com")
        XCTAssertEqual(detected("sub.example.co.uk/path?q=1"), "https://sub.example.co.uk/path?q=1")
        XCTAssertEqual(detected("example.com:8443/x"), "https://example.com:8443/x")
    }

    /// `localhost` and IP literals get `http`: they are a dev server essentially
    /// every time, and https to one is a certificate error, not a page.
    func testLocalhostAndIPLiteralsGetHTTP() {
        XCTAssertEqual(detected("localhost"), "http://localhost")
        XCTAssertEqual(detected("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(detected("localhost:8080/admin"), "http://localhost:8080/admin")
        XCTAssertEqual(detected("127.0.0.1"), "http://127.0.0.1")
        XCTAssertEqual(detected("192.168.1.40:5173/x"), "http://192.168.1.40:5173/x")
        XCTAssertEqual(detected("[::1]:8080"), "http://[::1]:8080")
    }

    func testExplicitSchemesArePassedThrough() {
        XCTAssertEqual(detected("https://example.com/a"), "https://example.com/a")
        XCTAssertEqual(detected("http://example.com"), "http://example.com")
        XCTAssertEqual(detected("about:blank"), "about:blank")
    }

    /// `javascript:` in an address bar is an XSS vector, not a navigation — the
    /// same judgement `NavigationPolicy.disposition(for:)` makes downstream.
    func testRefusesSchemesNobodyShouldTypeIntoAnAddressBar() {
        XCTAssertNil(detected("javascript:alert(1)"))
        XCTAssertNil(detected("mailto:someone@example.com"))
    }

    /// Everything here is a search. Turning a one-word query into a DNS lookup is
    /// the single most annoying thing an address bar can do.
    func testSearchesAreNotURLs() {
        XCTAssertNil(detected("git"))
        XCTAssertNil(detected("how to cook rice"))
        XCTAssertNil(detected("example .com"))
        XCTAssertNil(detected("1.5"))
        XCTAssertNil(detected("example."))
        XCTAssertNil(detected(".com"))
        XCTAssertNil(detected("999.999.999.999:80"))
        XCTAssertNil(detected(""))
    }

    /// What §9.4 completes and what a row shows: no scheme, no `www.`, no bare
    /// trailing slash — none of which the user typed.
    func testDisplayFormStripsWhatTheUserDidNotType() {
        XCTAssertEqual(CommandBarURL.displayForm(of: URL(string: "https://www.example.com/")!), "example.com")
        XCTAssertEqual(CommandBarURL.displayForm(of: URL(string: "http://example.com/a/b")!), "example.com/a/b")
    }

    /// §9.2's dedupe key: the same page reached three ways is one row.
    func testDedupeKeyFoldsTheHarmlessDifferences() {
        let key = CommandBarURL.dedupeKey(URL(string: "https://example.com/")!)
        XCTAssertEqual(CommandBarURL.dedupeKey(URL(string: "https://www.example.com")!), key)
        XCTAssertEqual(CommandBarURL.dedupeKey(URL(string: "https://EXAMPLE.com/")!), key)
        // …and not the meaningful ones.
        XCTAssertNotEqual(CommandBarURL.dedupeKey(URL(string: "https://example.com/?q=1")!), key)
        XCTAssertNotEqual(CommandBarURL.dedupeKey(URL(string: "http://example.com/")!), key)
    }
}

// §9.6's check that no Command Bar source names a networking type is
// `Tools/check-command-bar-offline.sh`, run by CI and `make check`.
