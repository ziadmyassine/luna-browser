@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §17.2: what the converter makes of element hiding — the cookie sections it
/// leaves out, the per-site exceptions (`#@#`) it must carry to WebKit, and the
/// cosmetic syntaxes it cannot.
@Suite("Cosmetic filters (§17.2)")
@MainActor
struct CosmeticFilterTests {

    // MARK: - Cookie sections

    /// The list's cookie sections are dropped whole: a consent screen is the page's
    /// to show, and Planday's sign-in stays disabled until its banner is answered.
    @Test func theCookieSectionsAreDroppedAndTheRestKept() {
        let conversion = FilterListConverter.convert("""
        ! *** easylist:fanboy-addon/fanboy_social_general_hide.txt ***
        ##.share-bar
        ! *** easylist:easylist_cookie/easylist_cookie_general_hide.txt ***
        ###cookie-banner
        ||consent.example^$third-party
        @@||consent.example/allowed.js
        keep.example#@#.newsletter-popup
        ! *** easylist:fanboy-addon/fanboy_annoyance_general_hide.txt ***
        ##.newsletter-popup
        """)
        #expect(conversion.hides.map(\.action.selector) == [".share-bar", ".newsletter-popup"])
        #expect(conversion.blocks.isEmpty)
        #expect(conversion.exceptions.isEmpty)
        #expect(conversion.hides.allSatisfy { $0.trigger.unlessDomain == nil }, "nor do its `#@#` exceptions reach the rest")
        #expect(conversion.skipped == 0, "a dropped cookie rule is not a rule we failed to express")
    }

    // MARK: - `#@#` exceptions

    @Test func aSiteExceptionKeepsAGenericHideOffThatSite() {
        let conversion = FilterListConverter.convert("""
        bafin.de#@##cookiebanner
        ###cookiebanner
        ##.ad
        """)
        let hide = conversion.hides.first { $0.action.selector == "#cookiebanner" }
        #expect(hide?.trigger.unlessDomain == ["*bafin.de"], "the exception comes first in the list and still applies")
        #expect(hide?.trigger.ifDomain == nil)
        #expect(conversion.hides.first { $0.action.selector == ".ad" }?.trigger.unlessDomain == nil)
    }

    @Test func aSiteExceptionTakesItsSiteOutOfASiteHide() {
        let conversion = FilterListConverter.convert("""
        one.example,two.example##.promo
        two.example#@#.promo
        solo.example##.promo-solo
        solo.example#@#.promo-solo
        #@#.gone
        ##.gone
        """)
        #expect(conversion.hides.map(\.action.selector) == [".promo"])
        #expect(conversion.hides.first?.trigger.ifDomain == ["*one.example"])
    }

    /// Fed to the network path, these were block rules for addresses no request has.
    @Test func extendedCosmeticSyntaxIsSkippedRatherThanBlocked() {
        let conversion = FilterListConverter.convert("""
        example.com#?#div:has-text(Ad)
        example.com#$#.banner { display: none }
        example.com#@?#div:has-text(Ad)
        example.com#%#window.x = 1
        """)
        #expect(conversion.count == 0)
        #expect(conversion.skipped == 4)
    }

    /// The `unless-domain` really reaches WebKit, subdomains included.
    @Test func webKitHonoursTheException() async throws {
        let conversion = FilterListConverter.convert("##.ad\nkeep.example#@#.ad")
        let json = try #require(String(bytes: try JSONEncoder().encode(conversion.rules), encoding: .utf8))
        let list = try #require(try await Self.ruleStore().compileContentRuleList(
            forIdentifier: "unhide", encodedContentRuleList: json
        ))
        let page = "<div class='ad'>x</div>"
        #expect(try await Self.evaluate("getComputedStyle(document.querySelector('.ad')).display",
                                        on: page, at: "https://news.example/", list: list) as? String == "none")
        #expect(try await Self.evaluate("getComputedStyle(document.querySelector('.ad')).display",
                                        on: page, at: "https://www.keep.example/", list: list) as? String == "block")
    }

    // MARK: - Helpers

    private static func ruleStore() -> WKContentRuleListStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WKContentRuleListStore(url: directory)!
    }

    /// Off screen: the web view is never put in a window.
    private static func evaluate(
        _ script: String, on html: String, at baseURL: String,
        list: WKContentRuleList
    ) async throws -> Any? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(list)
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: baseURL))
        for _ in 0 ..< 100 where webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await webView.evaluateJavaScript(script)
    }
}
