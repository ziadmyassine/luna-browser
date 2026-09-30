import AppKit
@testable import BrowserKit
import WebKit
import XCTest

/// Edit: saving back to the file, the preview following the text, and the
/// moments a pending edit is written without being asked.
@MainActor
final class MarkdownEditTests: XCTestCase {

    private var folder: URL!
    private var host: Host!
    private var controller: TabController!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "luna-edit-\(UUID().uuidString)")
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

    // MARK: - Saving (no page)

    func testCRLFIsWrittenBackAsCRLF() throws {
        let file = try write("# A\r\n\r\nB\r\n")
        let document = try MarkdownDocument.read(from: file)
        XCTAssertEqual(document.lineEnding, .crlf)
        let saved = try document.save("# A\n\nB changed\n")
        XCTAssertEqual(try Data(contentsOf: file), Data("# A\r\n\r\nB changed\r\n".utf8))
        XCTAssertEqual(saved.lineEnding, .crlf)
        XCTAssertEqual(saved.modificationDate, MarkdownDocument.modificationDate(of: file))
    }

    func testAFileChangedOnDiskIsNeverOverwritten() throws {
        let file = try write("# Mine")
        let document = try MarkdownDocument.read(from: file)
        pauseForTheClock()
        try write("# Theirs")
        XCTAssertThrowsError(try document.save("# Mine, edited")) {
            XCTAssertEqual($0 as? MarkdownDocument.SaveError, .changedOnDisk)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Theirs")
        _ = try document.save("# Mine, edited", overwritingChanges: true)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Mine, edited")
    }

    func testANonUTF8OrWebDocumentIsNotEditable() throws {
        let latin1 = MarkdownDocument(url: folder.appending(path: "a.md"), data: Data([0x23, 0x20, 0xE9]), modificationDate: nil)
        let web = MarkdownDocument(url: URL(string: "https://example.com/a.md")!, data: Data("# A".utf8), modificationDate: nil)
        XCTAssertFalse(latin1.isEditable)
        XCTAssertFalse(web.isEditable)
        XCTAssertThrowsError(try web.save("# B"))
    }

    // MARK: - The page

    func testEditIsRefusedForAWebDocument() async throws {
        let webView = try XCTUnwrap(controller.webView)
        controller.fetchText = { _ in Data("# Web".utf8) }
        let response = HTTPURLResponse(url: URL(string: "https://example.com/README.md")!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "text/plain"])
        XCTAssertTrue(controller.interceptMarkdown(try XCTUnwrap(response), in: webView))
        try await settle()
        controller.setReadingView(.edit)
        XCTAssertEqual(controller.readingView, .read)
        let editor = try await page("document.querySelector('.luna-input') === null") as? Bool
        XCTAssertEqual(editor, true)
    }

    func testEditShowsWithoutAReload() async throws {
        controller.load(try write("# Hello"))
        try await settle()
        _ = try await page("window.lunaMarker = 1")
        controller.setReadingView(.edit)
        try await Task.sleep(for: .milliseconds(100))
        let visible = try await page("getComputedStyle(document.querySelector('.luna-edit')).display") as? String
        let marker = try await page("window.lunaMarker") as? Int
        XCTAssertEqual(visible, "grid")
        XCTAssertEqual(marker, 1, "the page reloaded")
    }

    func testTypingUpdatesThePreviewAndMarksTheTabEdited() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type("\n\n## Added")
        try await Task.sleep(for: .milliseconds(400))
        let heading = try await page("document.querySelector('.luna-preview h2').textContent") as? String
        XCTAssertEqual(heading, "Added")
        XCTAssertTrue(controller.state.isEdited)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello", "saved before the pause")
    }

    func testAutosaveWritesAfterThePause() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type(" world")
        try await Task.sleep(for: .milliseconds(1_600))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello world")
        XCTAssertFalse(controller.state.isEdited)
    }

    func testClosingTheTabSavesAPendingEdit() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type("!")
        try await Task.sleep(for: .milliseconds(300))
        // Tab close, window close and quit all hibernate the tab.
        controller.hibernate()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
    }

    func testClosingInsideTheEditorsPauseKeepsTheLastKeystroke() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type("!")
        // Before the editor has posted it.
        controller.hibernate()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
    }

    func testNavigatingAwaySavesAPendingEdit() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type("!")
        try await Task.sleep(for: .milliseconds(300))
        let other = folder.appending(path: "other.html")
        try "<p>other</p>".write(to: other, atomically: true, encoding: .utf8)
        controller.load(other)
        try await settle()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
        XCTAssertFalse(controller.state.isEdited)
    }

    func testLeavingEditSavesAtOnce() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        controller.setReadingView(.edit)
        try await type("!")
        // Inside the 120 ms before the editor posts: leaving must read it.
        controller.setReadingView(.read)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
    }

    func testAChangeOnDiskStopsAutosaveAndKeepsTheText() async throws {
        let file = try write("# Hello")
        controller.load(file)
        try await settle()
        pauseForTheClock()
        try write("# Changed elsewhere")
        controller.setReadingView(.edit)
        try await type(" mine")
        try await Task.sleep(for: .milliseconds(1_600))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Changed elsewhere")
        XCTAssertEqual(host.conflicts, [file])
        XCTAssertTrue(controller.state.isEdited)
        let text = try await page("document.querySelector('.luna-input').value") as? String
        XCTAssertEqual(text, "# Hello mine")

        controller.hibernate()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Changed elsewhere", "closing overwrote it")
    }

    func testTheBackdropIsPlainAboveTheLineLimit() {
        let long = String(repeating: "# h\n", count: TabController.highlightedLineLimit + 1)
        XCTAssertFalse(TabController.editorRows(long).contains("md-mark"))
        XCTAssertTrue(TabController.editorRows("# h\n").contains("md-mark"))
    }

    // MARK: - Support

    @discardableResult
    private func write(_ text: String) throws -> URL {
        let file = folder.appending(path: "README.md")
        try Data(text.utf8).write(to: file)
        return file
    }

    /// File dates are compared exactly; a write in the same instant would match.
    private func pauseForTheClock() {
        Thread.sleep(forTimeInterval: 0.02)
    }

    /// Typing as WebKit's editor sees it, so it lands on the undo list.
    private func type(_ text: String) async throws {
        _ = try await controller.webView?.callAsyncJavaScript(
            """
            var input = document.querySelector('.luna-input');
            input.focus();
            input.setSelectionRange(input.value.length, input.value.length);
            document.execCommand('insertText', false, text);
            """,
            arguments: ["text": text],
            contentWorld: .page
        )
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
        var conflicts: [URL] = []
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(_ controller: TabController, markdownChangedOnDisk url: URL) { conflicts.append(url) }
    }
}
