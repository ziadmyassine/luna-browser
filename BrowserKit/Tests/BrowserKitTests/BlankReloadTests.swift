@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// A tab left at `about:blank` under the user — the page's process cut off
/// mid-load — reloads the page it was showing rather than the blank.
@Suite("Reloading a blank tab")
@MainActor
struct BlankReloadTests {

    private func loaded(_ html: String, at base: String) async throws -> (TabController, WKWebView) {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let webView = try #require(controller.webView)
        webView.loadHTMLString(html, baseURL: URL(string: base))
        for _ in 0 ..< 250 where webView.isLoading || webView.url?.absoluteString != base {
            try await Task.sleep(for: .milliseconds(20))
        }
        return (controller, webView)
    }

    private func settle(_ webView: WKWebView, at url: String) async throws {
        for _ in 0 ..< 250 where webView.url?.absoluteString != url {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aPageGoneBlankReloadsWhatItWasShowing() async throws {
        let (controller, webView) = try await loaded("<p>overview</p>", at: "https://app.example/overview")
        _ = try await webView.evaluateJavaScript("location.href = 'about:blank'; 0")
        try await settle(webView, at: "about:blank")
        for _ in 0 ..< 100 where webView.isLoading { try await Task.sleep(for: .milliseconds(20)) }

        controller.reload()

        #expect(webView.url?.absoluteString == "https://app.example/overview", "the reload kept the blank")
    }

    @Test func aTabThatWasOnlyEverBlankReloadsAsItIs() async throws {
        let (controller, webView) = try await loaded("", at: "about:blank")
        controller.reload()
        try await Task.sleep(for: .milliseconds(200))
        #expect(webView.url?.absoluteString == "about:blank")
    }
}
