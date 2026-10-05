@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §17.2: a consent dialog the annoyances list hides must not leave its page locked,
/// and the list's own per-site exceptions (`#@#`) must reach WebKit.
@Suite("Consent dialogs (§17.2)")
@MainActor
struct ConsentUnlockTests {

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

    // MARK: - The leftover lock

    /// borger.dk's shape, from its own markup and stylesheet: one `dialog-open` class
    /// on the body shows the consent dialog, an empty full-window `#modalboks` above
    /// everything, the backdrop, and switches the scroll off. The list hides the
    /// consent dialog by its class.
    private static func page(cookieHidden: Bool = true, ownDialogOpen: Bool = false) -> String {
        """
        <html><head><style>
        body { margin: 0; }
        main { height: 3000px; }
        .dialog { position: fixed; inset: 0; z-index: 1050; display: none; align-items: center; justify-content: center; }
        .dialog-open .dialog { display: flex; }
        .dialog-backdrop { position: fixed; inset: 0; z-index: 1040; background: #000; opacity: 0; visibility: hidden; }
        .dialog-open .dialog-backdrop { visibility: visible; opacity: 0.5; }
        .dialog-open { width: 100%; overflow: hidden; }
        .cookiebanner { position: fixed; top: 50%; left: 50%; z-index: 1051; transform: translate(-50%, -50%); }
        \(cookieHidden ? "div.cookiebanner { display: none !important; }" : "")
        </style></head>
        <body class="dialog-open">
        <div id="modalboks" role="dialog" aria-modal="true" aria-label="modal dialog" class="dialog js-dialog">\(
            ownDialogOpen ? "<form><button>Log på</button></form>" : "")</div>
        <main><h1>Selvbetjening</h1><a id="go" href="#x">Videre</a></main>
        <div data-nosnippet class="cookiebanner js-cookiebanner" role="dialog" aria-modal="true" tabindex="-1">
          <form method="post"><button id="RejectCookieLawButton">Afvis</button></form>
        </div>
        <div class="dialog-backdrop"></div>
        </body></html>
        """
    }

    private static let state = """
    [document.elementFromPoint(innerWidth / 4, innerHeight / 4).className,
     getComputedStyle(document.body).overflowY].join('|')
    """

    @Test func aHiddenConsentDialogTakesItsBackdropAndScrollLockWithIt() async throws {
        let result = try await Self.evaluate(Self.state, on: Self.page(), at: "https://www.borger.dk/", unlock: true)
        #expect(result as? String == "|auto", "the page under the backdrop answers, and scrolls")
    }

    @Test func aConsentDialogStillShowingKeepsItsLock() async throws {
        let result = try await Self.evaluate(
            Self.state, on: Self.page(cookieHidden: false), at: "https://www.borger.dk/", unlock: true
        )
        #expect(result as? String == "dialog js-dialog|hidden")
    }

    @Test func aPagesOwnOpenDialogKeepsItsLock() async throws {
        let result = try await Self.evaluate(
            Self.state, on: Self.page(ownDialogOpen: true), at: "https://www.borger.dk/", unlock: true
        )
        #expect(result as? String == "dialog js-dialog|hidden")
    }

    @Test func theUnlockFollowsTheAnnoyancesSwitchAndTheSite() {
        let blocker = ContentBlocker(store: Self.ruleStore(), defaults: scratchDefaults())
        let scope = SitePermissions()
        #expect(blocker.unlocksConsent(forHost: "www.borger.dk", in: scope))
        blocker.setDisabled(true, forHost: "www.borger.dk", in: scope)
        #expect(!blocker.unlocksConsent(forHost: "www.borger.dk", in: scope))
        blocker.setEnabled(false, for: .annoyances)
        #expect(!blocker.unlocksConsent(forHost: "news.example", in: scope))
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
        list: WKContentRuleList? = nil, unlock: Bool = false
    ) async throws -> Any? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let list { configuration.userContentController.add(list) }
        if unlock { configuration.userContentController.addUserScript(ContentBlocker.consentUnlockUserScript) }
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: baseURL))
        for _ in 0 ..< 100 where webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        // The script waits out a 150 ms debounce after the last mutation.
        try await Task.sleep(for: .milliseconds(400))
        return try await webView.evaluateJavaScript(script)
    }
}
