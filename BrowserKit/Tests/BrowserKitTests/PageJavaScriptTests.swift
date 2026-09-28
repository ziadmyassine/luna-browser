import AppKit
import BrowserKit
import WebKit
import XCTest

/// Develop ▸ Disable JavaScript stops the page's scripts and only the page's.
@MainActor
final class PageJavaScriptTests: XCTestCase {

    override func tearDown() async throws { WebViewFactory.isPageJavaScriptDisabled = false }

    func testTheSwitchStopsThePagesScriptsAndLeavesLunasOwn() async throws {
        let host = Host()
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        let view = try XCTUnwrap(controller.webView)

        WebViewFactory.isPageJavaScriptDisabled = true
        let disabled = try await ran(in: view)
        XCTAssertEqual(disabled, "no", "the page's script ran with JavaScript disabled")

        WebViewFactory.isPageJavaScriptDisabled = false
        let enabled = try await ran(in: view)
        XCTAssertEqual(enabled, "yes", "the page's script did not run with JavaScript enabled")
    }

    /// Luna reads the page through its own script either way, which is the
    /// half of the switch that must keep working.
    private func ran(in view: WKWebView) async throws -> String? {
        view.loadHTMLString(
            "<body data-ran='no'><script>document.body.dataset.ran = 'yes'</script></body>",
            baseURL: URL(string: "https://example.invalid/\(UUID().uuidString)")
        )
        for _ in 0..<50 where view.isLoading || view.url == nil { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(100))
        return try await view.evaluateJavaScript("document.body.dataset.ran") as? String
    }

    private final class Host: TabControllerDelegate {
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
