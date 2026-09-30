import AppKit
@testable import BrowserKit
import WebKit
import XCTest

/// The probe behind the Aa glyph on a web page: an article is offered
/// Reader, a page without one is not.
@MainActor
final class ArticleProbeTests: XCTestCase {

    private var folder: URL!
    private var controller: TabController!
    private var host: Host!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "luna-article-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        host = Host()
        controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        controller.webView?.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
    }

    override func tearDown() async throws {
        controller.hibernate()
        controller = nil
        host = nil
        try? FileManager.default.removeItem(at: folder)
    }

    func testAnArticleShowsTheGlyph() async throws {
        let paragraph = "<p>A sentence of prose, with a comma, and another, long enough to score as a paragraph "
            + "of an article rather than a caption, which is what the heuristic counts.</p>"
        let html = "<html><body><nav><a href='/'>Home</a></nav><article class='post'>"
            + String(repeating: paragraph, count: 8) + "</article></body></html>"
        controller.load(try write(html))
        try await settle()
        XCTAssertTrue(controller.state.isArticle)
        XCTAssertFalse(controller.state.isReading, "the probe offers Reader; it does not turn it on")
    }

    func testABarePageDoesNot() async throws {
        controller.load(try write("<html><body><a href='/'>Home</a><p>Hi.</p></body></html>"))
        try await settle()
        XCTAssertFalse(controller.state.isArticle)
    }

    private func write(_ html: String) throws -> URL {
        let file = folder.appending(path: "page.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func settle() async throws {
        let view = try XCTUnwrap(controller.webView)
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0 ..< 100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(150))
    }

    private final class Host: TabControllerDelegate {
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
