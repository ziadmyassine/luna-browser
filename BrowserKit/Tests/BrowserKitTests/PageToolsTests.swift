import AppKit
@testable import BrowserKit
import WebKit
import XCTest

/// Reader and the hiding picker, run against real pages in a real web view.
@MainActor
final class PageToolsTests: XCTestCase {

    private var host: Host!
    private var controller: TabController!

    override func setUp() async throws {
        host = Host()
        controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        // Hit-testing needs a viewport; a web view with no size has no point to test.
        controller.webView?.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    }

    override func tearDown() async throws {
        controller.hibernate()
        controller = nil
        host = nil
    }

    // MARK: - Reader

    private static let prose = "long enough to count as prose, with a comma, and another, and one more."

    private static let article = """
    <html><head><title>Tab title</title><style>p { color: rgb(255, 0, 0) }</style></head><body>
    <nav id="menu">\((1...30).map { "<a href='/s\($0)'>Section \($0)</a>" }.joined(separator: " "))</nav>
    <div class="story">
      <h1>The real headline</h1>
      \((1...6).map { "<p>Paragraph \($0) of the article, \(PageToolsTests.prose)</p>" }.joined())
    </div>
    <aside class="related"><p>Related: something else entirely, which nobody asked to read here.</p></aside>
    <footer><a href="/about">About</a></footer>
    </body></html>
    """

    func testReaderKeepsTheArticleAndDropsWhatWasArrangedAroundIt() async throws {
        try await load(Self.article)
        let answer = await toggleReader()
        XCTAssertEqual(answer, .on)
        XCTAssertTrue(controller.isReaderOn)

        let text = try await page("document.body.innerText") as? String ?? ""
        XCTAssertTrue(text.contains("Paragraph 6 of the article"))
        XCTAssertTrue(text.contains("The real headline"))
        XCTAssertFalse(text.contains("Section 12"), "the menu came along")
        XCTAssertFalse(text.contains("Related:"), "the related rail came along")
        let headlines = try await page("document.querySelectorAll('h1').length") as? Int
        XCTAssertEqual(headlines, 1, "the headline is shown twice")
        // The page's own stylesheet is gone, not merely outranked.
        let colour = try await page("getComputedStyle(document.querySelector('#luna-reader p')).color") as? String
        XCTAssertNotEqual(colour, "rgb(255, 0, 0)")
    }

    /// The page's scripts keep running; what they add afterwards is taken away.
    func testReaderTakesAwayWhatThePageAddsLater() async throws {
        try await load(Self.article)
        _ = await toggleReader()
        _ = try await page("document.body.appendChild(document.createElement('dialog')).id = 'late'; 1")
        try await Task.sleep(for: .milliseconds(50))
        let lateIsGone = try await page("document.getElementById('late') === null") as? Bool
        XCTAssertEqual(lateIsGone, true)
    }

    func testReaderSaysSoWhenThereIsNothingToRead() async throws {
        try await load("<body><nav><a href='/a'>A</a> <a href='/b'>B</a></nav><p>Short.</p></body>")
        let answer = await toggleReader()
        XCTAssertEqual(answer, .nothingToRead)
        XCTAssertFalse(controller.isReaderOn)
    }

    func testLeavingReaderReloadsThePage() async throws {
        try await load(Self.article)
        _ = await toggleReader()
        let answer = await toggleReader()
        XCTAssertEqual(answer, .off)
        XCTAssertFalse(controller.isReaderOn)
        try await settle()
        let readerIsGone = try await page("document.getElementById('luna-reader') === null") as? Bool
        XCTAssertEqual(readerIsGone, true)
    }

    private func article(_ property: String) async throws -> String? {
        try await page("getComputedStyle(document.getElementById('luna-reader'))['\(property)']") as? String
    }

    /// Reader starts from the stored preferences and follows a change without
    /// being turned off and on again.
    func testReaderFollowsTheReadingPreferences() async throws {
        try await load(Self.article)
        _ = await toggleReader()
        let isShared = try await page("document.getElementById('luna-reader').classList.contains('luna-reading')") as? Bool
        XCTAssertEqual(isShared, true)
        let width = try await article("maxWidth")
        XCTAssertEqual(width, "\(ReadingPreferences.stored().width.points)px")

        var preferences = ReadingPreferences()
        preferences.width = .narrow
        preferences.size = 22
        controller.applyReadingPreferences(preferences)
        for _ in 0 ..< 50 where try await article("maxWidth") != "580px" {
            try await Task.sleep(for: .milliseconds(20))
        }
        let narrow = try await article("maxWidth")
        XCTAssertEqual(narrow, "580px")
        let size = try await article("fontSize")
        XCTAssertEqual(size, "22px")
    }

    /// Preferences touch only a reading page; an ordinary one is left alone.
    func testReadingPreferencesLeaveAnOrdinaryPageAlone() async throws {
        try await load(Self.article)
        var preferences = ReadingPreferences()
        preferences.width = .narrow
        controller.applyReadingPreferences(preferences)
        try await Task.sleep(for: .milliseconds(100))
        let marked = try await page("document.documentElement.hasAttribute('data-luna-width')") as? Bool
        XCTAssertEqual(marked, false)
    }

    // MARK: - Hiding

    private static let banners = """
    <body style="margin:0">
    <div id="cookie-bar" style="height:100px">We use cookies</div>
    <main style="height:400px"><p>Content</p></main>
    <div class="promo" style="height:100px">Subscribe</div>
    </body>
    """

    private func display(_ selector: String) async throws -> String? {
        try await page("getComputedStyle(document.querySelector('\(selector)')).display") as? String
    }

    /// Before the page draws, from the first document on the site.
    func testAHiddenElementIsHiddenOnTheNextVisit() async throws {
        controller.hiddenElements.hide(.init(selector: "#cookie-bar", label: "Cookie bar"), onHost: "hidden.invalid")
        try await load(Self.banners, host: "www.hidden.invalid")
        let hidden = try await display("#cookie-bar")
        XCTAssertEqual(hidden, "none")
        let shown = try await display(".promo")
        XCTAssertEqual(shown, "block")
    }

    func testTheLivePageFollowsItsSitesList() async throws {
        try await load(Self.banners, host: "live.invalid")
        let promo = HiddenElements.Element(selector: "div.promo", label: "Subscribe")
        controller.hiddenElements.hide(promo, onHost: "live.invalid")
        controller.applyHiddenElements()
        try await Task.sleep(for: .milliseconds(100))
        let hidden = try await display(".promo")
        XCTAssertEqual(hidden, "none")

        controller.hiddenElements.restore(selector: "div.promo", onHost: "live.invalid")
        controller.applyHiddenElements()
        try await Task.sleep(for: .milliseconds(100))
        let shown = try await display(".promo")
        XCTAssertEqual(shown, "block")
    }

    /// A press picks the element under it and the page never hears it; Escape
    /// ends the picking.
    func testThePickerNamesWhatWasPressedAndSwallowsThePress() async throws {
        try await load(
            Self.banners + "<a id='link' href='/x'>A link</a>"
                + "<script>window.pressed = 0; addEventListener('click', () => pressed++)</script>"
        )
        var picked: [HiddenElements.Element] = []
        var ended = false
        controller.startPickingElements { picked.append($0) } onEnd: { ended = true }
        XCTAssertTrue(controller.isPickingElements)
        try await Task.sleep(for: .milliseconds(100))
        // The crosshair everywhere, a link's own pointer included.
        let cursor = try await page("getComputedStyle(document.getElementById('link')).cursor") as? String
        XCTAssertEqual(cursor, "crosshair")

        _ = try await page("""
        var bar = document.getElementById('cookie-bar');
        ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (kind) {
          var make = kind.indexOf('pointer') === 0 ? PointerEvent : MouseEvent;
          bar.dispatchEvent(new make(kind, { bubbles: true, cancelable: true, clientX: 50, clientY: 50, button: 0 }));
        });
        1
        """)
        for _ in 0 ..< 50 where picked.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(picked.map(\.selector), ["#cookie-bar"])
        XCTAssertEqual(picked.first?.label, "We use cookies")
        let pressed = try await page("window.pressed") as? Int
        XCTAssertEqual(pressed, 0, "the page heard the click")

        _ = try await page("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); 1")
        for _ in 0 ..< 50 where !ended { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(ended)
        XCTAssertFalse(controller.isPickingElements)
        let cursorAfter = try await page("getComputedStyle(document.getElementById('link')).cursor") as? String
        XCTAssertNotEqual(cursorAfter, "crosshair", "the crosshair outlived the picker")
        let pickerIsGone = try await page("document.querySelector('luna-picker') === null") as? Bool
        XCTAssertEqual(pickerIsGone, true)
    }

    /// The picker lives where the page cannot reach it.
    func testThePageCannotSeeThePicker() async throws {
        try await load(Self.banners)
        controller.startPickingElements { _ in } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        let seen = try await page("typeof window.__lunaPicker") as? String
        XCTAssertEqual(seen, "undefined")
        controller.stopPickingElements()
        XCTAssertFalse(controller.isPickingElements)
    }

    func testANewDocumentEndsThePicking() async throws {
        try await load(Self.banners)
        var ended = false
        controller.startPickingElements { _ in } onEnd: { ended = true }
        try await load(Self.banners)
        XCTAssertTrue(ended)
        XCTAssertFalse(controller.isPickingElements)
    }

    // MARK: - Support

    private func load(_ html: String, host: String = "example.invalid") async throws {
        let view = try XCTUnwrap(controller.webView)
        view.loadHTMLString(html, baseURL: URL(string: "https://\(host)/\(UUID().uuidString)"))
        try await settle()
    }

    private func settle() async throws {
        let view = try XCTUnwrap(controller.webView)
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0 ..< 100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
    }

    private func toggleReader() async -> ReaderAnswer {
        await withCheckedContinuation { continuation in
            controller.toggleReader { continuation.resume(returning: $0) }
        }
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
