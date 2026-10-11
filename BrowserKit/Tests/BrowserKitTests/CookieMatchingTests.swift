@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// The cookies a jar sends to a URL are the ones RFC 6265 §5.4 says a browser
/// would: a fetch Luna makes outside a web view (a PDF an agent reads) carries
/// the user's logins, and must carry them only to the sites they belong to.
///
/// The jar is non-persistent, so nothing is written to disk.
@Suite("Cookies for a URL")
@MainActor
struct CookieMatchingTests {

    private let jar = WKWebsiteDataStore.nonPersistent()

    private func names(for url: String) async throws -> [String] {
        await jar.cookies(for: try #require(URL(string: url))).map(\.name).sorted()
    }

    /// Cookies as WebKit stores them from these `Set-Cookie` headers on `https://example.com/`.
    private func setCookies(_ headers: [String]) async throws {
        let origin = try #require(URL(string: "https://example.com/"))
        for header in headers {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: origin)
            for cookie in cookies { await jar.httpCookieStore.setCookie(cookie) }
        }
    }

    @Test func aLookalikeSiteGetsNone() async throws {
        try await setCookies(["domain=1; Domain=example.com; Path=/", "host=1; Path=/"])
        #expect(try await names(for: "https://badexample.com/report.pdf").isEmpty)
    }

    @Test func aSubdomainGetsADomainCookieButNotAHostOnlyOne() async throws {
        try await setCookies(["domain=1; Domain=.example.com; Path=/", "host=1; Path=/"])
        #expect(try await names(for: "https://sub.example.com/report.pdf") == ["domain"])
        #expect(try await names(for: "https://example.com/report.pdf") == ["domain", "host"])
    }

    @Test func aSecureCookieGoesOnlyOverHTTPS() async throws {
        try await setCookies(["plain=1; Path=/", "secure=1; Path=/; Secure"])
        #expect(try await names(for: "http://example.com/report.pdf") == ["plain"])
        #expect(try await names(for: "https://example.com/report.pdf") == ["plain", "secure"])
    }

    @Test func aPathCookieGoesOnlyUnderItsPath() async throws {
        try await setCookies(["docs=1; Path=/docs"])
        #expect(try await names(for: "https://example.com/docs/report.pdf") == ["docs"])
        #expect(try await names(for: "https://example.com/docsx/report.pdf").isEmpty)
        #expect(try await names(for: "https://example.com/report.pdf").isEmpty)
    }
}
