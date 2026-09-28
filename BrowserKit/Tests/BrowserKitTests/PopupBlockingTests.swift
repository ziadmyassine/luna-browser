@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §17's pop-up blocker, the pure half: which new window each mode lets through,
/// what a page may report across the message boundary, the tab-under guard's
/// window, and the filter lists' own `$popup` rules.
///
/// Its own file rather than more of `BlockingTests`, which is at the file-length
/// limit.
@Suite("Pop-up blocking (§17)")
@MainActor
struct PopupBlockingTests {

    private static let opener = URL(string: "https://news.example.com/story")!

    private func request(
        _ url: String?,
        modified: Bool = false,
        pressed: String? = nil,
        allowed: Bool = false
    ) -> PopupPolicy.Request {
        PopupPolicy.Request(
            url: url.flatMap(URL.init(string:)),
            openerURL: Self.opener,
            isModifiedClick: modified,
            pressedLink: pressed.flatMap(URL.init(string:)),
            siteAllowed: allowed
        )
    }

    // MARK: - The decision

    @Test func offAllowsEverything() {
        for url in ["https://ads.example.net/", "https://news.example.com/a", nil] {
            #expect(PopupPolicy.allows(request(url), mode: .off))
        }
    }

    /// (a)–(d), each on its own, and the pop-up that meets none of them.
    @Test(arguments: [
        // (a) a modified click
        ("https://ads.example.net/", true, nil as String?, true),
        // (b) the same registrable domain, across subdomains
        ("https://video.example.com/watch", false, nil, true),
        // (c) a sign-in provider, by host
        ("https://accounts.google.com/o/oauth2/v2/auth", false, nil, true),
        ("https://appleid.apple.com/auth/authorize", false, nil, true),
        ("https://login.microsoftonline.com/common/oauth2", false, nil, true),
        ("https://login.live.com/oauth20_authorize.srf", false, nil, true),
        ("https://github.com/login/oauth/authorize", false, nil, true),
        ("https://www.facebook.com/v19.0/dialog/oauth", false, nil, true),
        // (c) by its OAuth parameters
        ("https://id.example.org/auth?client_id=a&redirect_uri=b", false, nil, true),
        ("https://id.example.org/auth?client_id=a&response_type=code", false, nil, true),
        // (d) the link the user pressed
        ("https://elsewhere.example.org/page", false, "https://elsewhere.example.org/page", true),
        // None of them
        ("https://ads.example.net/", false, nil, false),
        ("https://github.com/explore", false, nil, false),
        ("https://www.facebook.com/somepage", false, nil, false),
        ("https://id.example.org/auth?client_id=a", false, nil, false),
        ("https://elsewhere.example.org/page", false, "https://elsewhere.example.org/other", false)
    ])
    func smartLetsThroughOnlyWhatARuleVouchesFor(url: String, modified: Bool, pressed: String?, allowed: Bool) {
        #expect(PopupPolicy.allows(request(url, modified: modified, pressed: pressed), mode: .smart) == allowed)
    }

    /// A window opened blank and pointed somewhere once a sign-in call returns is
    /// the shape sign-in buttons use to get past blockers; it inherits the
    /// opener's origin, so it is the opener's own.
    @Test func smartAllowsABlankWindow() {
        #expect(PopupPolicy.allows(request(nil), mode: .smart))
        #expect(PopupPolicy.allows(request("about:blank"), mode: .smart))
        #expect(!PopupPolicy.allows(request("data:text/html,x"), mode: .smart))
    }

    /// Only the blank window that opened for being blank is put on probation.
    @Test func onlyAnUnvouchedBlankWindowIsOnProbation() {
        #expect(PopupPolicy.isBlank(URL(string: "")) && PopupPolicy.isBlank(nil))
        #expect(PopupPolicy.needsProbation(request(nil), mode: .smart))
        #expect(PopupPolicy.needsProbation(request("about:blank"), mode: .smart))
        #expect(!PopupPolicy.needsProbation(request(nil, modified: true), mode: .smart))
        #expect(!PopupPolicy.needsProbation(request(nil, allowed: true), mode: .smart))
        #expect(!PopupPolicy.needsProbation(request("https://news.example.com/a"), mode: .smart))
        #expect(!PopupPolicy.needsProbation(request(nil), mode: .off))
        #expect(!PopupPolicy.needsProbation(request(nil), mode: .blockAll))
    }

    @Test func blockAllLetsThroughOnlyAModifiedClickOrAnAllowedSite() {
        #expect(!PopupPolicy.allows(request("https://news.example.com/a"), mode: .blockAll))
        #expect(!PopupPolicy.allows(request("https://accounts.google.com/"), mode: .blockAll))
        #expect(!PopupPolicy.allows(
            request("https://x.example.org/", pressed: "https://x.example.org/"), mode: .blockAll
        ))
        #expect(!PopupPolicy.allows(request(nil), mode: .blockAll))
        #expect(PopupPolicy.allows(request("https://ads.example.net/", modified: true), mode: .blockAll))
        #expect(PopupPolicy.allows(request("https://ads.example.net/", allowed: true), mode: .blockAll))
    }

    @Test func anAllowedSiteOverridesSmart() {
        #expect(PopupPolicy.allows(request("https://ads.example.net/", allowed: true), mode: .smart))
    }

    @Test func theModeDefaultsToSmartAndReadsItsOwnKey() throws {
        let defaults = scratchDefaults()
        #expect(PopupPolicy.mode(in: defaults) == .smart)
        PopupPolicy.setMode(.blockAll, in: defaults)
        #expect(defaults.string(forKey: "privacy.popupMode") == "blockAll")
        #expect(PopupPolicy.mode(in: defaults) == .blockAll)
        defaults.set("nonsense", forKey: "privacy.popupMode")
        #expect(PopupPolicy.mode(in: defaults) == .smart)
        #expect(!PopupPolicy.showsAddress(in: defaults))
    }

    // MARK: - The trust boundary

    @Test func aReportIsAnHTTPAddressResolvedAgainstItsFrame() {
        let frame = URL(string: "https://news.example.com/a/b")
        #expect(PopupPolicy.reportedURL("https://ads.example.net/x", relativeTo: frame)?.absoluteString
            == "https://ads.example.net/x")
        #expect(PopupPolicy.reportedURL("/promo?x=1", relativeTo: frame)?.absoluteString
            == "https://news.example.com/promo?x=1")
        for hostile: Any? in ["javascript:alert(1)", "data:text/html,x", "file:///etc/passwd",
                              "luna://settings", "", 42, ["url": "https://x.example/"], nil] {
            #expect(PopupPolicy.reportedURL(hostile, relativeTo: frame) == nil, "\(String(describing: hostile))")
        }
        #expect(PopupPolicy.reportedURL("relative", relativeTo: nil) == nil)
    }

    // MARK: - The tab's record

    @Test func theHistoryIsNewestFirstAndCappedAtTen() {
        let guardState = PopupGuard()
        for index in 0 ..< 12 {
            guardState.record(URL(string: "https://ads.example.net/\(index)")!)
        }
        #expect(guardState.blocked.count == 10)
        #expect(guardState.blocked.first?.url.lastPathComponent == "11")
        #expect(guardState.blocked.last?.url.lastPathComponent == "2")
    }

    /// `createWebViewWith` returning nil is what makes `window.open` return null,
    /// so the page script reports the same pop-up the engine just recorded.
    @Test func theSameReportTwiceInASecondIsOnePopup() {
        let guardState = PopupGuard()
        let url = URL(string: "https://ads.example.net/")!
        let now = Date()
        #expect(guardState.record(url, at: now))
        #expect(!guardState.record(url, at: now.addingTimeInterval(0.2)))
        #expect(guardState.record(url, at: now.addingTimeInterval(3)))
        #expect(guardState.blocked.count == 2)
    }

    @Test func theTabUnderGuardRefusesOnlyScriptedCrossSiteMovesInsideItsWindow() {
        let guardState = PopupGuard()
        let now = Date()
        let away = URL(string: "https://casino.example.net/")!
        let home = URL(string: "https://www.example.com/next")!
        #expect(!guardState.refusesTabUnder(to: away, from: Self.opener, isUserInitiated: false, at: now))

        guardState.arm(exempt: false, at: now)
        #expect(guardState.refusesTabUnder(to: away, from: Self.opener, isUserInitiated: false, at: now))
        #expect(!guardState.refusesTabUnder(to: home, from: Self.opener, isUserInitiated: false, at: now))
        #expect(!guardState.refusesTabUnder(
            to: URL(string: "https://accounts.google.com/")!, from: Self.opener, isUserInitiated: false, at: now
        ))
        #expect(!guardState.refusesTabUnder(
            to: away, from: Self.opener, isUserInitiated: false, at: now.addingTimeInterval(PopupPolicy.tabUnderWindow + 0.1)
        ))

        // A navigation the user asked for ends the window.
        guardState.arm(exempt: false, at: now)
        #expect(!guardState.refusesTabUnder(to: away, from: Self.opener, isUserInitiated: true, at: now))
        #expect(!guardState.refusesTabUnder(to: away, from: Self.opener, isUserInitiated: false, at: now))

        // A sign-in pop-up's opener is expected to move on its own.
        guardState.arm(exempt: true, at: now)
        #expect(!guardState.refusesTabUnder(to: away, from: Self.opener, isUserInitiated: false, at: now))
    }

    // MARK: - The filter lists' own rules

    /// EasyList's `$popup` rules become WebKit's `popup` type and compile. WebKit
    /// applies them only to the URL `window.open` is given, which is why the rest
    /// of this file exists.
    @Test func popupRulesSurviveConversion() async throws {
        let conversion = FilterListConverter.convert("||popads.example^$popup\n||ads.example^$popup,third-party")
        #expect(conversion.blocks.count == 2)
        #expect(conversion.blocks.allSatisfy { $0.trigger.resourceType == ["popup"] })

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try #require(WKContentRuleListStore(url: directory))
        let json = try #require(String(bytes: JSONEncoder().encode(conversion.blocks), encoding: .utf8))
        let list = try await store.compileContentRuleList(forIdentifier: "popups", encodedContentRuleList: json)
        #expect(list != nil)
    }
}
