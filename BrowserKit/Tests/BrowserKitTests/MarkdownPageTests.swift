import AppKit
@testable import BrowserKit
import WebKit
import XCTest

/// A Markdown document opened in a tab: rendered in place of its text, under
/// its own address, with the page's scripts kept out of it.
@MainActor
final class MarkdownPageTests: XCTestCase {

    private var folder: URL!
    private var host: Host!
    private var controller: TabController!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "luna-md-\(UUID().uuidString)")
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

    func testALocalFileRendersUnderItsFileURL() async throws {
        let file = try write("# Hello\n\nBody.")
        controller.load(file)
        try await settle()
        let shown = try await page("document.querySelector('.luna-reading h1').textContent") as? String
        XCTAssertEqual(shown, "Hello")
        XCTAssertEqual(controller.webView?.url, file)
        XCTAssertEqual(controller.markdownDocument?.url, file)
    }

    func testASiblingImageLoads() async throws {
        // A 1×1 PNG.
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        try png.write(to: folder.appending(path: "dot.png"))
        controller.load(try write("![dot](dot.png)"))
        try await settle()
        let width = try await page("var i = document.querySelector('img'); i.complete ? i.naturalWidth : -1") as? Int
        XCTAssertEqual(width, 1, "the sibling image did not load")
    }

    func testAReloadReadsTheFileAgain() async throws {
        let file = try write("# One")
        controller.load(file)
        try await settle()
        try write("# Two")
        controller.reload()
        try await settle()
        let shown = try await page("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(shown, "Two")
    }

    func testAScriptInTheDocumentNeverRuns() async throws {
        controller.load(try write("<script>document.title = 'ran'</script>\n\n<img src=x onerror=\"document.title='ran'\">"))
        try await settle()
        let shown = try await page("document.title") as? String
        XCTAssertNotEqual(shown, "ran")
    }

    func testThePageCannotReachTheReadingHandler() async throws {
        controller.load(try write("# Hi"))
        try await settle()
        let seen = try await page("typeof (window.webkit && window.webkit.messageHandlers.lunaReading)") as? String
        XCTAssertEqual(seen, "undefined")
    }

    func testAWebDocumentRendersUnderItsAddress() async throws {
        let address = try XCTUnwrap(URL(string: "https://example.com/README.md"))
        controller.fetchText = { _ in Data("# From the web".utf8) }
        try await showWeb(address)
        let shown = try await page("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(shown, "From the web")
        XCTAssertEqual(controller.webView?.url, address)
        XCTAssertEqual(controller.markdownDocument?.url.isFileURL, false)
    }

    func testBackReturnsToTheRenderedDocument() async throws {
        let address = try XCTUnwrap(URL(string: "https://example.com/README.md"))
        controller.fetchText = { _ in Data("# Rendered".utf8) }
        try await showWeb(address)
        controller.webView?.loadHTMLString("<p>next</p>", baseURL: URL(string: "https://example.com/next"))
        try await settle()
        controller.webView?.goBack()
        try await settle()
        let shown = try await page("document.querySelector('h1') && document.querySelector('h1').textContent") as? String
        XCTAssertEqual(shown,
                       "Rendered", "Back landed on the raw text")
    }

    func testTheOutlineListsTheSections() async throws {
        controller.load(try write("# Title\n\n## First\n\ntext\n\n## Second\n\ntext"))
        try await settle()
        let entries = try await page("Array.from(document.querySelectorAll('.luna-outline a')).map(a => a.textContent).join('|')")
        XCTAssertEqual(entries as? String, "First|Second")
        let current = try await page("document.querySelector('.luna-outline a[aria-current]').textContent") as? String
        XCTAssertEqual(current, "First")
    }

    func testCopyHandsTheCodeToTheHost() async throws {
        controller.load(try write("```swift\nlet x = 1\n```"))
        try await settle()
        _ = try await controller.webView?.evaluateJavaScript(
            "document.querySelector('.luna-copy').click(); true", in: nil, contentWorld: .page
        )
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(host.copied, ["let x = 1\n"])
    }

    // MARK: - Reading pop-out (phase 5)

    func testAMarkdownPageIsPublishedAsReading() async throws {
        controller.load(try write("# Hello"))
        try await settle()
        XCTAssertTrue(controller.state.isReading)
    }

    func testAStoredSizeRestylesTheOpenPageLive() async throws {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: ReadingPreferences.Key.size)
        defer { defaults.set(before, forKey: ReadingPreferences.Key.size) }
        controller.load(try write("# Hello\n\nBody."))
        try await settle()
        var preferences = ReadingPreferences.stored()
        preferences.size = preferences.size == 24 ? 22 : 24
        // Stored only: the tab follows the defaults, as it does for a change
        // synced in from another Mac.
        preferences.store()
        try await Task.sleep(for: .milliseconds(200))
        let size = try await page("getComputedStyle(document.querySelector('.luna-reading')).fontSize") as? String
        XCTAssertEqual(size, "\(preferences.size)px")
    }

    func testTheViewSwitchesWithoutAReload() async throws {
        controller.load(try write("# Hello"))
        try await settle()
        _ = try await page("window.lunaMarker = 1")
        controller.setReadingView(.source)
        try await Task.sleep(for: .milliseconds(100))
        let view = try await page("document.body.getAttribute('data-view')") as? String
        let marker = try await page("window.lunaMarker") as? Int
        XCTAssertEqual(view, "source")
        XCTAssertEqual(marker, 1, "the page reloaded")
        XCTAssertEqual(controller.readingView, .source)
    }

    // MARK: - Support

    @discardableResult
    private func write(_ text: String) throws -> URL {
        let file = folder.appending(path: "README.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Stands in for a `text/plain` response, which a test cannot serve over https.
    private func showWeb(_ address: URL) async throws {
        let webView = try XCTUnwrap(controller.webView)
        let response = HTTPURLResponse(url: address, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/plain"])
        XCTAssertTrue(controller.interceptMarkdown(try XCTUnwrap(response), in: webView))
        try await settle()
    }

    private func settle() async throws {
        let view = try XCTUnwrap(controller.webView)
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0 ..< 100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(150))
    }

    private func page(_ script: String) async throws -> Any? {
        try await controller.webView?.evaluateJavaScript(script)
    }

    private final class Host: TabControllerDelegate {
        var copied: [String] = []
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(_ controller: TabController, didCopyCode code: String) { copied.append(code) }
    }
}
