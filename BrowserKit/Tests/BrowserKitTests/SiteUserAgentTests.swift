@testable import BrowserKit
import Foundation
import GRDB
import Testing
import WebKit

/// §4.6: a site can be given its own user agent, the same in every Space, and the
/// request for one of its pages goes out with it.
@Suite("Per-site user agent (§4.6)")
@MainActor
struct SiteUserAgentTests {

    /// Until `check` passes, or two seconds: the saves are detached.
    private func eventually(_ check: () async throws -> Bool) async throws {
        var tries = 0
        while try await !check(), tries < 200 {
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func v15AddsANullableUserAgentColumn() async throws {
        let store = try makeTemporaryStore()
        let column = try await store.pool.read { db in
            try db.columns(in: "siteSettings").first { $0.name == "userAgent" }
        }
        #expect(column?.type == "TEXT")
        #expect(column?.isNotNull == false)
    }

    @Test func aChoiceIsKeptAndDefaultForgetsIt() async throws {
        let store = try makeTemporaryStore()
        try await store.setSitePermission(.savePasswords, allowed: false, host: "shop.example")
        try await store.setSiteUserAgent(.chrome, host: "shop.example")
        #expect(try await store.siteUserAgents() == ["shop.example": .chrome])

        try await store.setSiteUserAgent(nil, host: "shop.example")
        #expect(try await store.siteUserAgents().isEmpty)
        #expect(try await store.sitePermissions()[.savePasswords] == ["shop.example": false])
    }

    /// Not synced: a change to the user agent alone queues nothing.
    @Test func changingOnlyTheUserAgentQueuesNoSync() async throws {
        let store = try makeTemporaryStore()
        try await store.setSiteZoom(1.25, host: "shop.example")
        try await store.setSyncZone(.sites, enabled: true)
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }
        try await store.setSiteUserAgent(.safari, host: "shop.example")
        #expect(try await store.syncOutbox().isEmpty)
    }

    @Test func aChoiceHoldsInEverySpaceAndIsReadAtStart() async throws {
        let (store, spaceID) = try await makeTemporaryStoreWithSpace()
        let app = SitePermissions()
        app.start(browserStore: store)
        app.forSpace(spaceID).setUserAgentMode(.chrome, forHost: "Shop.Example")
        #expect(app.forSpace(UUID()).userAgentMode(forHost: "shop.example") == .chrome)
        try await eventually { try await store.siteUserAgents()["shop.example"] != nil }

        let relaunched = SitePermissions()
        relaunched.start(browserStore: store)
        try await eventually { relaunched.userAgentMode(forHost: "shop.example") != nil }
        #expect(relaunched.userAgentMode(forHost: "shop.example") == .chrome)
    }

    /// §5.6: a private window's Default is its own, and does not let the user's
    /// choice for the site show through.
    @Test func aPrivateWindowsChoiceStaysInTheWindow() {
        let app = SitePermissions()
        app.setUserAgentMode(.chrome, forHost: "shop.example")
        let scoped = SitePermissions(fallback: app)
        #expect(scoped.userAgentMode(forHost: "shop.example") == .chrome)

        scoped.setUserAgentMode(nil, forHost: "shop.example")
        scoped.setUserAgentMode(.safari, forHost: "other.example")
        #expect(scoped.userAgentMode(forHost: "shop.example") == nil)
        #expect(app.userAgentMode(forHost: "shop.example") == .chrome)
        #expect(app.userAgentMode(forHost: "other.example") == nil)
    }

    /// Set in `decidePolicyFor`, so the page's own request is the first to carry it.
    @Test func aPageOfTheSiteLoadsWithItsUserAgent() async throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let webView = try #require(controller.webView)
        controller.sitePermissions.setUserAgentMode(.chrome, forHost: "chrome-only.example")

        webView.loadHTMLString("<p>in</p>", baseURL: URL(string: "https://chrome-only.example/"))
        try await eventually { webView.url?.host() == "chrome-only.example" && !webView.isLoading }
        let seen = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        #expect(seen == WebViewFactory.chromeUserAgent)

        webView.loadHTMLString("<p>other</p>", baseURL: URL(string: "https://elsewhere.example/"))
        try await eventually { webView.url?.host() == "elsewhere.example" && !webView.isLoading }
        // Back to the Settings choice, whatever that is on this Mac.
        #expect(webView.customUserAgent ?? "" == WebViewFactory.customUserAgent(for: WebViewFactory.userAgentMode) ?? "")
    }
}
