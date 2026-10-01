import AppKit
@testable import BrowserKit
import WebKit
import XCTest

/// §18.1: WebKit's find, and the count beside it, on real pages in a real web view.
@MainActor
final class FindInPageTests: XCTestCase {

    private var host: Host!
    private var controller: TabController!

    override func setUp() async throws {
        host = Host()
        controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        controller.webView?.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    }

    override func tearDown() async throws {
        controller.hibernate()
        controller = nil
        host = nil
    }

    private static let page = """
    <html><body>
    <h1>Moon notes</h1>
    <p>The moon is bright. A <b>moon</b>lit night.</p>
    <p style="display:none">moon hidden from view</p>
    <div>Last: MOON</div>
    </body></html>
    """

    func testFindingWalksTheMatchesInOrderAndCountsThem() async throws {
        try await load(Self.page)
        var seen: [FindResult] = []
        for step in 0 ..< 5 {
            seen.append(await controller.find("moon", fromMatchStart: step == 0))
        }
        XCTAssertTrue(seen.allSatisfy(\.found))
        XCTAssertEqual(seen.map(\.total), Array(repeating: 4, count: 5), "the hidden paragraph was counted, or a match was missed")
        XCTAssertEqual(seen.map(\.match), [1, 2, 3, 4, 1], "next did not walk the matches and wrap")
        let selected = try await page("window.getSelection().toString()") as? String
        XCTAssertEqual(selected?.lowercased(), "moon")
    }

    func testPreviousGoesBackAndWraps() async throws {
        try await load(Self.page)
        let first = await controller.find("moon", fromMatchStart: true)
        let back = await controller.find("moon", backwards: true)
        XCTAssertEqual(first.match, 1)
        XCTAssertEqual(back.match, 4, "previous from the first match did not wrap to the last")
    }

    /// Typing on: "moo" found the first match, and "moon" has to find the same
    /// one rather than the next.
    func testALongerQueryKeepsTheMatchAShorterOneFound() async throws {
        try await load(Self.page)
        _ = await controller.find("moon", fromMatchStart: true)
        let second = await controller.find("moon")
        XCTAssertEqual(second.match, 2)
        let longer = await controller.find("moonlit", fromMatchStart: true)
        XCTAssertEqual(longer.total, 1)
        XCTAssertEqual(longer.match, 1)
        let selected = try await page("window.getSelection().toString()") as? String
        XCTAssertEqual(selected, "moonlit", "find did not cross the bold element's edge")
    }

    func testNoMatchesSaysSo() async throws {
        try await load(Self.page)
        let result = await controller.find("sunlight", fromMatchStart: true)
        XCTAssertEqual(result, .notFound)
    }

    /// Accents and case are folded the same way WebKit folds them, or the count
    /// and the selection would disagree.
    func testTheCountFoldsCaseAndAccentsAsWebKitDoes() async throws {
        try await load("<body><p>Café cafe CAFE</p></body>")
        let result = await controller.find("cafe", fromMatchStart: true)
        XCTAssertTrue(result.found)
        let selected = try await page("window.getSelection().toString()") as? String
        XCTAssertEqual(selected, "Café", "WebKit's find is accent-sensitive after all; the count script must follow")
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.match, 1)
    }

    /// Two blocks are not one run of text: find does not match across them, and
    /// neither does the count.
    func testTheCountDoesNotMatchAcrossBlocks() async throws {
        try await load("<body><p>left</p><p>right</p><p>left right</p></body>")
        let result = await controller.find("left right", fromMatchStart: true)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.match, 1)
    }

    /// Source line breaks and indentation are one space on screen, and find
    /// matches them as one.
    func testTheCountCollapsesWhiteSpaceAsTheLayoutDoes() async throws {
        try await load("<body><p>full\n      moon</p><pre>full    moon</pre></body>")
        let result = await controller.find("full moon", fromMatchStart: true)
        XCTAssertEqual(result.total, 1, "a <pre> keeps its spaces, so only the paragraph matches")
        XCTAssertEqual(result.match, 1)
    }

    /// A match the script cannot see — here, inside a text field — gets no
    /// count rather than a wrong one.
    func testAMatchTheCountCannotPlaceHasNoCount() async throws {
        try await load("<body><p>nothing here</p><input value='zebra'></body>")
        let result = await controller.find("zebra", fromMatchStart: true)
        XCTAssertTrue(result.found, "PROBE")
        XCTAssertNil(result.total)
        XCTAssertNil(result.match)
    }

    func testTheSelectionIsWhatUseSelectionForFindReads() async throws {
        try await load(Self.page)
        _ = try await page("""
        const range = document.createRange();
        range.selectNodeContents(document.querySelector('h1'));
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        1
        """)
        let text = await controller.selectedText()
        XCTAssertEqual(text, "Moon notes")
    }

    // MARK: - Helpers

    private func load(_ html: String) async throws {
        let view = try XCTUnwrap(controller.webView)
        view.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/\(UUID().uuidString)"))
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0 ..< 100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
    }

    private func page(_ script: String) async throws -> Any? {
        try await controller.webView?.evaluateJavaScript(script)
    }

    private final class Host: TabControllerDelegate {
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
