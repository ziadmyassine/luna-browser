@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §17. Every test here is offline: the network half of the pipeline is a `URLSession`
/// download, and the parts worth protecting are the conversion, the cache key and the
/// engine limits.
@Suite("Content blocking (§17)")
@MainActor
struct BlockingTests {

    // MARK: - Helpers

    private static func temporaryRuleStore() -> WKContentRuleListStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WKContentRuleListStore(url: directory)!
    }

    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "luna.blocking.tests.\(UUID().uuidString)")!
    }

    /// Loads a page carrying one `.ad` element at `baseURL` with `list` attached, and
    /// reports whether the rule hid it. No network: `loadHTMLString` sets the document's
    /// origin from `baseURL`, which is exactly what `if-domain` matches against.
    private static func adIsHidden(by list: WKContentRuleList, at baseURL: String) async throws -> Bool {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(list)
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
        webView.loadHTMLString("<html><body><div class='ad'>x</div></body></html>", baseURL: URL(string: baseURL))
        for _ in 0 ..< 100 where webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        let display = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('.ad')).display")
        return display as? String == "none"
    }

    // MARK: - §17.1 domains: lowercase, punycoded, and actually matching

    /// RFC 3492's own vectors plus the two shapes filter lists really contain.
    /// Foundation cannot do this — `URL.host()` percent-encodes and `URLComponents.host`
    /// decodes punycode back to Unicode — so this is the thing that would rot silently.
    @Test func punycodesAndLowercasesDomains() {
        #expect(Punycode.asciiDomain("BÜCHER.de") == "xn--bcher-kva.de")
        #expect(Punycode.asciiDomain("日本.JP") == "xn--wgv71a.jp")
        #expect(Punycode.asciiDomain("Ads.Example.COM") == "ads.example.com")
        // Already-encoded input must survive untouched.
        #expect(Punycode.asciiDomain("xn--wgv71a.jp") == "xn--wgv71a.jp")
        // WebKit's own subdomain marker and a filter list's leading dot are not labels.
        #expect(Punycode.asciiDomain("*Example.com") == "*example.com")
        #expect(Punycode.asciiDomain(".example.com") == "example.com")
        #expect(Punycode.asciiDomain("example.com.") == "example.com")
        #expect(Punycode.asciiDomain("") == nil)
        #expect(Punycode.asciiDomain("a//b.com") == nil)
    }

    @Test func converterEmitsOnlyLowercaseASCIIDomains() {
        let conversion = FilterListConverter.convert("""
        ||tracker.example^$domain=EXAMPLE.COM|~Sub.日本.JP
        Bücher.DE##.promo
        """)
        let domains = conversion.rules.flatMap { ($0.trigger.ifDomain ?? []) + ($0.trigger.unlessDomain ?? []) }
        #expect(!domains.isEmpty)
        for domain in domains {
            let isLowercaseASCII = domain == domain.lowercased() && domain.allSatisfy { $0.isASCII }
            #expect(isLowercaseASCII, "\(domain) is not lowercase ASCII")
        }
        // EasyList's `domain=` means the domain *and* its subdomains; WebKit only widens
        // an entry when it starts with `*`. Dropping the star is a rule that compiles
        // fine and never fires — the silent failure §17.1 warns about.
        #expect(domains.contains("*example.com"))
        #expect(domains.contains("*xn--bcher-kva.de"))

        // Measured: "A trigger cannot have more than one condition (if-domain,
        // unless-domain, if-top-url, or unless-top-url)". So a rule carrying both keeps
        // `if-domain` and loses the `~` exclusion — slightly over-blocking on that one
        // subdomain, which beats dropping the rule and not blocking at all.
        #expect(conversion.blocks.allSatisfy { $0.trigger.ifDomain == nil || $0.trigger.unlessDomain == nil })

        // A rule with only exclusions still gets them.
        let exclusionOnly = FilterListConverter.convert("||t.example^$domain=~Safe.example.com")
        #expect(exclusionOnly.blocks.first?.trigger.unlessDomain == ["*safe.example.com"])
        #expect(exclusionOnly.blocks.first?.trigger.ifDomain == nil)
    }

    /// The one that proves the rule is not silently dead: a punycoded `if-domain` really
    /// does match a document served from the Unicode host.
    @Test func punycodedDomainMatchesAUnicodeDocument() async throws {
        let store = Self.temporaryRuleStore()
        let rule = ContentRule(
            trigger: .init(urlFilter: ".*", ifDomain: [Punycode.asciiDomain("日本.jp")!]),
            action: .hide(".ad")
        )
        let json = try #require(String(bytes: JSONEncoder().encode([rule]), encoding: .utf8))
        let list = try #require(try await store.compileContentRuleList(forIdentifier: "t", encodedContentRuleList: json))

        #expect(try await Self.adIsHidden(by: list, at: "https://日本.jp/page"))
        #expect(try await Self.adIsHidden(by: list, at: "https://example.com/page") == false)
    }

    /// Why the normalisation above is not optional: WebKit refuses the whole list, so one
    /// stray uppercase domain costs every other rule in it.
    @Test func webKitRefusesUnnormalisedDomains() async throws {
        let store = Self.temporaryRuleStore()
        for domain in ["EXAMPLE.com", "日本.jp"] {
            let json = #"[{"trigger":{"url-filter":".*","if-domain":["\#(domain)"]},"action":{"type":"block"}}]"#
            await #expect(throws: (any Error).self) {
                try await store.compileContentRuleList(forIdentifier: "bad", encodedContentRuleList: json)
            }
        }
    }

    // MARK: - §17.1 the url-filter dialect

    /// WebKit's regex has no alternation, no `{n,m}` and no `\d` (all measured). A
    /// converter that emits one fails the entire list, so the output is checked for them.
    @Test func urlFilterStaysInsideWebKitsDialect() async throws {
        let patterns = ["||ads.example.com^", "|http://tracker.example.com/a?b=1|", "/banner/*.gif", "||a.b.c^$third-party"]
        var rules: [ContentRule] = []
        for pattern in patterns {
            let filter = try #require(FilterListConverter.urlFilter(for: pattern.replacingOccurrences(of: "$third-party", with: "")))
            #expect(!filter.contains("{"))
            #expect(!filter.contains("\\d"))
            // The only backslashes may be escapes of a literal metacharacter.
            #expect(filter.range(of: "(?<!\\\\)\\|", options: .regularExpression) == nil, "bare alternation in \(filter)")
            rules.append(ContentRule(trigger: .init(urlFilter: filter), action: .block))
        }
        // And it has to survive the real compiler, not just the assertions above.
        let json = try #require(String(bytes: JSONEncoder().encode(rules), encoding: .utf8))
        _ = try #require(try await Self.temporaryRuleStore()
            .compileContentRuleList(forIdentifier: "dialect", encodedContentRuleList: json))
    }

    @Test func mapsFilterOptionsOntoTypesWebKitAccepts() {
        let conversion = FilterListConverter.convert("""
        ||a.example^$xmlhttprequest
        ||b.example^$subdocument
        ||c.example^$script,third-party
        ||d.example^$redirect=noop.js
        """)
        let types = conversion.blocks.flatMap { $0.trigger.resourceType ?? [] }
        for type in types {
            #expect(ContentRuleLimits.resourceTypes.contains(type), "\(type) is not a WebKit resource-type")
        }
        // ABP's `xmlhttprequest` has no WebKit spelling; `fetch` is the accepted one.
        #expect(types.contains("fetch"))
        // `$subdocument` must not become a bare `document`, or it blocks the page itself.
        #expect(conversion.blocks.contains { $0.trigger.loadContext == ["child-frame"] })
        #expect(conversion.blocks.contains { $0.trigger.loadType == ["third-party"] })
        // `$redirect` has no equivalent and is dropped rather than downgraded to a block.
        #expect(conversion.blocks.allSatisfy { !$0.trigger.urlFilter.contains("d\\.example") })
        #expect(conversion.skipped >= 1)
    }

    /// §17.3: element hiding ships *in the rule list*, so there is no flicker, and the
    /// procedural pseudo-classes WebKit would reject never reach it.
    @Test func convertsElementHidingAndDropsProceduralSelectors() {
        let conversion = FilterListConverter.convert("""
        ##.ad-banner
        example.com##.sponsored
        example.com#@#.sponsored
        example.com##div:has-text(Ad)
        example.com##div:has(> .ad)
        """)
        #expect(conversion.hides.count == 3)
        #expect(conversion.hides.allSatisfy { $0.action.type == "css-display-none" })
        #expect(conversion.hides.contains { $0.action.selector == "div:has(> .ad)" })
        #expect(conversion.hides.allSatisfy { $0.action.selector?.contains(":has-text") != true })
    }

    // MARK: - §17.1 the ~150k cap

    /// Measured exactly: 150,000 compiles, 150,001 does not. The split has to keep every
    /// exception in every chunk — `ignore-previous-rules` cannot reach into another list,
    /// so an exception left behind is a whitelisted site that breaks.
    @Test func splitsAtTheMeasuredRuleCap() {
        #expect(ContentRuleLimits.maxRulesPerList == 150_000)
        var conversion = FilterListConverter.Conversion()
        conversion.blocks = (0 ..< 200_000).map {
            ContentRule(trigger: .init(urlFilter: "^https://h\($0)\\.example\\.com/"), action: .block)
        }
        conversion.exceptions = (0 ..< 3).map {
            ContentRule(trigger: .init(urlFilter: ".*", ifDomain: ["*ok\($0).example"]), action: .ignorePrevious)
        }

        let chunks = conversion.chunked()
        #expect(chunks.count == 2)
        for chunk in chunks {
            #expect(chunk.count <= ContentRuleLimits.maxRulesPerList)
            #expect(chunk.suffix(3).allSatisfy { $0.action.type == "ignore-previous-rules" })
        }
        #expect(chunks.reduce(0) { $0 + $1.count } == 200_000 + 3 * chunks.count)
    }

    // MARK: - §17.1 the content-hash cache

    /// The reason a hash is in the identifier at all: 2.9 s of compile for EasyList
    /// against 0.000 s for a lookup of the same content.
    @Test func unchangedContentIsFoundRatherThanRecompiled() async throws {
        let store = Self.temporaryRuleStore()
        let rules = [ContentRule(trigger: .init(urlFilter: "^https://ads\\.example\\.com/"), action: .block)]
        let json = try #require(String(bytes: JSONEncoder().encode(rules), encoding: .utf8))
        let hash = ContentBlocker.hash(Data(json.utf8))

        #expect(hash == ContentBlocker.hash(Data(json.utf8)), "the hash is not stable")
        #expect(hash != ContentBlocker.hash(Data((json + " ").utf8)), "changed content hashed the same")

        let identifier = ContentBlocker.identifier(.ads, hash: hash, chunk: 0)
        _ = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)

        // Same content → same identifier → already in the store, so no compile is due.
        #expect(try await store.contentRuleList(forIdentifier: identifier) != nil)

        // A missing identifier **throws** rather than returning nil, which is the branch
        // "we have never compiled this" hangs off.
        let next = ContentBlocker.identifier(.ads, hash: ContentBlocker.hash(Data((json + " ").utf8)), chunk: 0)
        await #expect(throws: (any Error).self) { try await store.contentRuleList(forIdentifier: next) }
    }

    // MARK: - §17.1 the offline first run (D14)

    /// Lists are never bundled, so a first run with no network genuinely has nothing to
    /// block with. It has to say so rather than look like it is working.
    @Test func offlineFirstRunReportsNotReady() async throws {
        let blocker = ContentBlocker(store: Self.temporaryRuleStore(), defaults: Self.defaults())
        blocker.start(browserStore: nil)
        // `start` looks lists up; nothing has ever been compiled into this store.
        try await Task.sleep(for: .milliseconds(200))
        #expect(blocker.status == .notReady)

        // `WKUserContentController` cannot be asked what it holds — it has `add`,
        // `remove` and `removeAll` and no getter — so the blocker reports it instead.
        let controller = WKUserContentController()
        blocker.apply(to: controller, host: "example.com")
        #expect(blocker.attachedListCount == 0)
    }

    // MARK: - §17.2 per-site, §17.6 HTTPS-only

    @Test func perSiteDisableIsHostNormalised() async throws {
        let blocker = ContentBlocker(store: Self.temporaryRuleStore(), defaults: Self.defaults())
        blocker.setDisabled(true, forHost: "Example.COM.")
        #expect(blocker.isDisabled(forHost: "example.com"))
        #expect(blocker.isDisabled(forHost: "EXAMPLE.com"))
        #expect(blocker.isDisabled(forHost: "other.com") == false)
    }

    @Test func perSiteDisableRoundTripsThroughSiteSettings() async throws {
        let store = try makeTemporaryStore()
        try await store.setBlockingDisabled(true, host: "example.com")
        try await store.setInsecureAllowed(true, host: "old.example.net")
        var exemptions = try await store.blockingExemptions()
        #expect(exemptions.blockingDisabled == ["example.com"])
        #expect(exemptions.insecureAllowed == ["old.example.net"])

        try await store.setBlockingDisabled(false, host: "example.com")
        exemptions = try await store.blockingExemptions()
        #expect(exemptions.blockingDisabled.isEmpty)
        #expect(exemptions.insecureAllowed == ["old.example.net"])
    }

    @Test func httpsOnlyUpgradesExceptWhereItCannotWork() throws {
        let blocker = ContentBlocker(store: Self.temporaryRuleStore(), defaults: Self.defaults())
        #expect(blocker.httpsDecision(for: URL(string: "http://example.com/a")!) == .proceed)

        blocker.isHTTPSOnlyEnabled = true
        let upgraded = URL(string: "https://example.com/a?b=1")!
        #expect(blocker.httpsDecision(for: URL(string: "http://example.com/a?b=1")!) == .upgrade(upgraded))
        // The interstitial needs to know we are the reason the URL is https (§17.6).
        #expect(blocker.downgradeOrigin(for: upgraded)?.scheme == "http")

        // Nothing on these can present a certificate, so upgrading only breaks them.
        #expect(blocker.httpsDecision(for: URL(string: "http://localhost:8080/")!) == .proceed)
        #expect(blocker.httpsDecision(for: URL(string: "http://127.0.0.1/")!) == .proceed)
        #expect(blocker.httpsDecision(for: URL(string: "http://printer.local/")!) == .proceed)
        #expect(blocker.httpsDecision(for: URL(string: "https://example.com/")!) == .proceed)

        blocker.allowInsecure(host: "Legacy.example.org")
        #expect(blocker.httpsDecision(for: URL(string: "http://legacy.example.org/x")!) == .proceed)
    }
}
