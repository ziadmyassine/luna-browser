//
//  CommentFlowTests.swift
//  LunaTests
//
//  Comment mode running on a page: entering and leaving, the note field
//  beside what was picked, its keys, and what a pick captures. Apart from
//  `CommentModeTests`, which covers when the two commands are offered.
//
//  A file: fixture in a window that is never put on screen, and a draft
//  folder of the test's own, so nothing reaches the real one.
//

import AppKit
@testable import BrowserKit
import ImageIO
import WebKit
import XCTest
@testable import Luna

@MainActor
final class CommentFlowTests: XCTestCase {

    private var directory: URL!
    private var session: BrowserSession!
    private var controller: BrowserWindowController!
    private var window: BrowserWindow!
    private var delegate: AppDelegate!
    private var tab: TabController!

    /// One button by the leading edge, one against the trailing edge, and a
    /// `div` whose path goes through `foreignObject`, which no selector finds again.
    private static let fixture = """
    <!doctype html><meta charset=utf-8>
    <body style="margin:0">
    <button id="near" style="position:absolute;left:40px;top:60px;width:100px;height:40px">Save</button>
    <button id="far" style="position:absolute;right:8px;top:60px;width:100px;height:40px">Share</button>
    <svg style="position:absolute;left:40px;top:200px" width="300" height="100"><foreignObject width="300" height="100">
    <div style="height:50px">First</div><div style="height:50px">Second</div>
    </foreignObject></svg>
    </body>
    """

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        controller = BrowserWindowController(remembersFrame: false)
        window = BrowserWindow(session: session, controller: controller)
        session.setKeyWindow(window.id)
        session.hostWindow = controller.window
        controller.windowUndoManager = session.undoManager
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
        delegate.commentSet = CommentSet(folder: directory.appending(path: "draft"))

        let url = directory.appending(path: "page.html")
        try Self.fixture.write(to: url, atomically: true, encoding: .utf8)
        let id = session.newTab(url: nil)
        session.activateTab(id, inWindow: window.id)
        controller.setContent(session.webView(for: id))
        tab = try XCTUnwrap(session.controller(for: id))
        tab.load(url)
        for _ in 0 ..< 100 {
            if tab.state.url == url, !tab.state.isLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(tab.state.isLoading, "the page never finished loading")
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    override func tearDown() async throws {
        window.comments?.leave()
        window.close()
        controller.close()
        session.tearDown()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Entering and leaving

    func testEnteringDescribesAndPressingAgainLeaves() throws {
        delegate.toggleCommenting(nil)
        XCTAssertNotNil(window.comments)
        XCTAssertTrue(tab.isDescribingElements)
        XCTAssertFalse(tab.isPickingElements, "comment mode was taken for Hide")
        XCTAssertTrue(session.isDescribingElements)

        delegate.toggleCommenting(nil)
        XCTAssertNil(window.comments)
        XCTAssertFalse(tab.isDescribingElements)
    }

    func testHideSomethingIsUntickedAndDimmedWhileCommenting() {
        delegate.toggleCommenting(nil)
        let item = NSMenuItem(title: "", action: BrowserCommand.hideElements.action, keyEquivalent: "")
        XCTAssertFalse(delegate.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
    }

    /// ⇧⌘H cannot end comment mode, and must not say hiding has started either.
    func testHidingLeavesCommentModeOnAndSaysNothing() {
        delegate.toggleCommenting(nil)
        delegate.toggleHidingElements(nil)
        XCTAssertNotNil(window.comments)
        XCTAssertTrue(tab.isDescribingElements)
        XCTAssertFalse(tab.isPickingElements)
        XCTAssertNil(controller.controlSurface.toast, "the hiding toast went up over comment mode")
    }

    func testEscapeInThePageLeaves() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        _ = try await tab.webView?.evaluateJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); 1"
        )
        try await waitFor { self.window.comments == nil }
        try await assertNoCommentViews()
        XCTAssertFalse(tab.isDescribingElements)
    }

    func testATabSwitchLeaves() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let other = session.newTab(url: nil)
        session.activateTab(other, inWindow: window.id)
        XCTAssertNil(window.comments)
        XCTAssertFalse(tab.isDescribingElements, "the picker kept running on the tab that was left")
        try await assertNoCommentViews()
    }

    // MARK: - The note field

    func testAPickOpensTheFieldBesideTheBox() async throws {
        let (field, box) = try await fieldAndBox(x: "90", y: "80")
        XCTAssertEqual(field.frame.minX, box.maxX + Tokens.Metric.chromeGap, accuracy: 0.5)
        XCTAssertEqual(field.frame.minY, box.minY, accuracy: 0.5)
        XCTAssertEqual(field.frame.width, Tokens.Metric.findBarWidth, accuracy: 0.5)
    }

    func testTheFieldFlipsAtTheTrailingEdge() async throws {
        let (field, box) = try await fieldAndBox(x: "innerWidth - 58", y: "80")
        XCTAssertEqual(field.frame.maxX, box.minX - Tokens.Metric.chromeGap, accuracy: 0.5)
        XCTAssertLessThanOrEqual(field.frame.maxX, controller.controlSurface.bounds.maxX)
    }

    /// `foreignObject`'s path matches nothing, and the pick is kept anyway.
    func testANonUniquePickStillBecomesAComment() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "275")
        let comment = try XCTUnwrap(set.comments.first)
        XCTAssertEqual(comment.element.matches, 0)
        XCTAssertEqual(comment.element.selector, "body > svg > foreignobject > div:nth-of-type(2)")
    }

    func testTypingThenCommandSWritesTheDraft() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let note = try XCTUnwrap(window.comments?.note)
        note.textView.insertText("Make it blue", replacementRange: NSRange(location: NSNotFound, length: 0))
        let save = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0, context: nil,
            characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1
        ))
        XCTAssertTrue(try XCTUnwrap(controller.window).performKeyEquivalent(with: save), "⌘S went past the field")
        let data = try Data(contentsOf: set.folder.appending(path: "draft.json"))
        let saved = try JSONDecoder().decode([Comment].self, from: data)
        XCTAssertEqual(saved.map(\.note), ["Make it blue"])
    }

    /// The window's list holds closed tabs and, once empty, brings back hidden
    /// elements: neither may answer ⌘Z typed in the note.
    func testUndoInTheFieldDoesNotReachTheSessionsList() async throws {
        var sessionUndid = false
        session.undoManager.registerUndo(withTarget: self) { _ in sessionUndid = true }
        try await Task.sleep(for: .milliseconds(50))
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let note = try XCTUnwrap(window.comments?.note)
        note.textView.insertText("Make it blue", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(note.textView.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertFalse(sessionUndid, "⌘Z in the note undid the session's last step")
        XCTAssertFalse(session.undoManager.canRedo, "the typing was filed on the session's list")
        XCTAssertEqual(note.textView.string, "", "⌘Z did not undo the typing")
    }

    /// The field moves to the next pick with an empty note, and ⌘Z walking
    /// back past it into the first note's typing does not raise.
    func testASecondPickStartsAnEmptyNoteThatUndoSurvives() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let first = try XCTUnwrap(window.comments?.note)
        first.textView.insertText("Make it blue", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        try await pick(x: "innerWidth - 58", y: "80")
        let note = try XCTUnwrap(window.comments?.note)
        XCTAssertTrue(note === first, "the field was rebuilt rather than moved")
        XCTAssertEqual(note.text, "")
        XCTAssertEqual(set.comments.map(\.note), ["Make it blue", ""])
        for _ in 0 ..< 4 { set.undoManager.undo() }
    }

    // MARK: - Capture

    func testTheCropIsTheBoxPaddedAtTheDisplayScale() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let comment = try XCTUnwrap(set.comments.first)
        let scale = try XCTUnwrap(controller.window?.backingScaleFactor)
        let size = try pixels(of: comment.image)
        XCTAssertEqual(size.width, Int(((comment.element.box.width + 32) * scale).rounded()))
        XCTAssertEqual(size.height, Int(((comment.element.box.height + 32) * scale).rounded()))
    }

    /// A fragment with `=` in it is an OAuth or magic-link answer, and does not reach the bundle.
    func testThePickKeepsThePagesStateWithoutTheSecretFragment() async throws {
        let page = try XCTUnwrap(tab.state.url)
        let answered = try XCTUnwrap(URL(string: page.absoluteString + "#state=abc&id_token=xyz"))
        tab.load(answered)
        try await waitFor { self.tab.state.url == answered }
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let state = try XCTUnwrap(set.comments.first?.page)
        XCTAssertEqual(state.url, page.absoluteString)
        let width = try await tab.webView?.evaluateJavaScript("innerWidth") as? Double
        XCTAssertEqual(state.viewportWidth, width)
        let dark = try await tab.webView?.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches") as? Bool
        XCTAssertEqual(state.dark, dark)
        XCTAssertEqual([state.scrollX, state.scrollY], [0, 0])
    }

    func testTheContextPictureIsTakenOnALocalOrigin() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let context = try XCTUnwrap(set.comments.first?.context, "a file: page is local")
        XCTAssertGreaterThan(try pixels(of: context).width, 0)
    }

    func testNoContextPictureOffALocalOrigin() async throws {
        delegate.toggleCommenting(nil)
        window.comments?.isLocal = { _ in false }
        try await pick(x: "90", y: "80")
        XCTAssertNil(try XCTUnwrap(set.comments.first).context)
    }

    // MARK: - Support

    private var set: CommentSet { delegate.commentSet! }

    /// A press as the picker hears one, then the field it opens.
    private func pick(x: String, y: String) async throws {
        let before = set.comments.count
        _ = try await tab.webView?.evaluateJavaScript("""
        document.dispatchEvent(new PointerEvent('pointerdown',
          { bubbles: true, cancelable: true, clientX: \(x), clientY: \(y), button: 0 })); 1
        """)
        try await waitFor { self.set.comments.count > before && self.window.comments?.note != nil }
    }

    /// The field, and the picked element's box on the same surface.
    private func fieldAndBox(x: String, y: String) async throws -> (NSView, CGRect) {
        delegate.toggleCommenting(nil)
        try await pick(x: x, y: y)
        let field = try XCTUnwrap(window.comments?.note)
        let box = try XCTUnwrap(set.comments.last?.element.box)
        let webView = try XCTUnwrap(tab.webView)
        let y = webView.isFlipped ? box.y : webView.bounds.height - box.y - box.height
        let rect = controller.controlSurface.convert(
            CGRect(x: box.x, y: y, width: box.width, height: box.height), from: webView
        )
        return (field, rect)
    }

    private func pixels(of name: String) throws -> (width: Int, height: Int) {
        let url = set.folder.appending(path: name)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    private func assertNoCommentViews() async throws {
        let surface = controller.controlSurface
        try await waitFor { !surface.subviews.contains { $0 is CommentNoteView } }
    }

    private func waitFor(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0 ..< 100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }
}
