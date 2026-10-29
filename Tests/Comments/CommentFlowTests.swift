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

    var directory: URL!
    private var session: BrowserSession!
    var controller: BrowserWindowController!
    var window: BrowserWindow!
    var delegate: AppDelegate!
    var tab: TabController!

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
        delegate.commentDrafts = directory.appending(path: "drafts")

        let url = directory.appending(path: "page.html")
        try Self.fixture.write(to: url, atomically: true, encoding: .utf8)
        let id = session.newTab(url: nil)
        session.activateTab(id, inWindow: window.id)
        controller.setContent(session.webView(for: id))
        tab = try XCTUnwrap(session.controller(for: id))
        tab.load(url)
        // The page's own location, not the tab's state: a new tab reports
        // the URL and not loading before anything has committed, and on the
        // runner its blank document and then this one committed after comment
        // mode had started, ending it.
        let loaded = try await poll {
            let page = try? await self.tab.webView?.evaluateJavaScript("location.href + ' ' + document.readyState") as? String
            return page == url.absoluteString + " complete" && !self.tab.state.isLoading
        }
        XCTAssertTrue(loaded, "the page never finished loading")
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

    /// A page that moves to another address without a new document has moved
    /// to another page's draft; an anchor in the same page has not.
    func testAnInPageMoveToAnotherAddressLeaves() async throws {
        delegate.toggleCommenting(nil)
        _ = try await tab.webView?.evaluateJavaScript("location.hash = 'notes'; 1")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(window.comments, "an anchor ended comment mode")

        _ = try await tab.webView?.evaluateJavaScript("history.pushState(null, '', location.pathname + '?item=2'); 1")
        try await waitFor { self.window.comments == nil }
        XCTAssertFalse(tab.isDescribingElements)
    }

    /// ⇧⌘M takes the page from Hide's picker rather than doing nothing.
    func testCommentingStopsHidesPicker() async throws {
        delegate.toggleHidingElements(nil)
        XCTAssertTrue(tab.isPickingElements)
        delegate.toggleCommenting(nil)
        XCTAssertNotNil(window.comments)
        XCTAssertFalse(tab.isPickingElements)
        try await pick(x: "90", y: "80")
        XCTAssertNotNil(window.comments, "Hide's picker ending took comment mode with it")
        XCTAssertTrue(tab.isDescribingElements)
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

    /// A menu command is one event, so the note it commits and the export
    /// share the event's undo group; ⌘Z must still bring back the note.
    /// The test's run loop never closes an event's group, so the groups here are explicit.
    func testUndoingAnExportKeepsTheNoteTypedJustBeforeIt() async throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let page = try CommentSet.page(of: XCTUnwrap(session.activeURL).absoluteString)
        delegate.commentSets[page] = CommentSet(folder: CommentSet.folder(for: page, in: delegate.commentDrafts), undoManager: undo)
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        try XCTUnwrap(window.comments?.note).textView.string = "Make it blue"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        undo.beginUndoGrouping()
        _ = delegate.exportComments(to: directory.appending(path: "Comments"), pasteboard: pasteboard)
        undo.endUndoGrouping()
        XCTAssertTrue(set.comments.isEmpty)
        delegate.undo(nil)

        XCTAssertEqual(set.comments.map(\.note), ["Make it blue"])
    }

    /// Words typed while the next pick is still being pictured belong to the note they were typed in.
    func testTypingDuringTheNextCaptureStaysWithTheFirstNote() async throws {
        delegate.toggleCommenting(nil)
        try await pick(x: "90", y: "80")
        let note = try XCTUnwrap(window.comments?.note)
        note.textView.insertText("Make it", replacementRange: NSRange(location: NSNotFound, length: 0))
        window.comments?.frame = { webView, marks in
            note.textView.insertText(" blue", replacementRange: NSRange(location: NSNotFound, length: 0))
            return try await ControlCapture.frame(of: webView, marks: marks)
        }
        try await pick(x: "innerWidth - 58", y: "80")
        XCTAssertEqual(set.comments.map(\.note), ["Make it blue", ""])
    }

    // MARK: - Support

    var set: CommentSet { delegate.commentSet(for: tab.state.url)! }

    /// A press and its release as the picker hears them, then the field it opens.
    private func pick(x: String, y: String) async throws {
        let before = set.comments.count
        try await click(x: x, y: y)
        try await waitFor { self.set.comments.count > before && self.window.comments?.note != nil }
    }

    func click(x: String, y: String) async throws {
        _ = try await tab.webView?.evaluateJavaScript("""
        ['pointerdown', 'pointerup'].forEach(function (kind) {
          document.dispatchEvent(new PointerEvent(kind,
            { bubbles: true, cancelable: true, clientX: \(x), clientY: \(y), button: 0 }));
        });
        1
        """)
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

    func pixels(of name: String) throws -> (width: Int, height: Int) {
        let url = set.folder.appending(path: name)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    private func assertNoCommentViews() async throws {
        let surface = controller.controlSurface
        try await waitFor { !surface.subviews.contains { $0 is CommentNoteView } }
    }
}

// MARK: - Capture

// Outside the class body only for SwiftLint's `type_body_length`.
extension CommentFlowTests {

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
        // The URL is the requested one from the moment the load starts; the
        // page is the one the pick lands on only once the load has finished.
        try await waitFor { self.tab.state.url == answered && !self.tab.state.isLoading }
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

    /// A pick that cannot be pictured says so, and leaves no picture behind.
    func testAFailedCaptureSaysSoAndLeavesNoPicture() async throws {
        delegate.toggleCommenting(nil)
        window.comments?.frame = { _, _ in throw CocoaError(.fileWriteUnknown) }
        try await click(x: "90", y: "80")
        let surface = controller.controlSurface
        try await waitFor { surface.toast?.text == PageToast.commentNotCaptured.text }
        XCTAssertTrue(set.comments.isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: set.folder.path)) ?? []
        XCTAssertEqual(files.filter { $0.hasSuffix(".png") }, [])
    }
}

// MARK: - Keys

// ↑, ↓ and Return reach the picker from wherever the window's keyboard is,
// so they are sent the way AppKit sends a key, not dispatched in the page.
extension CommentFlowTests {

    /// `elementFromPoint` only ever gives the innermost leaf, so a container is
    /// reached by walking up from it. The page records every key it hears.
    private static let sidebar = """
    <!doctype html><meta charset=utf-8>
    <body style="margin:0">
    <aside style="width:400px">
      <div class="sub-sidebar" style="padding:20px">
        <nav style="padding:10px">
          <a href="/a" style="display:block;height:30px">Alpha</a>
          <a href="/b" style="display:block;height:30px">Beta</a>
        </nav>
      </div>
    </aside>
    <p id="other" style="height:50px">Elsewhere</p>
    <script>window.keys = []; addEventListener('keydown', e => keys.push(e.key))</script>
    </body>
    """

    func testEnteringGivesThePageTheKeyboard() async throws {
        try await loadSidebar()
        delegate.toggleCommenting(nil)
        XCTAssertTrue(controller.window?.firstResponder === tab.webView, "\(String(describing: controller.window?.firstResponder))")
    }

    /// While a note is open the picker rests: ↑ goes to the note, not the outline.
    func testUpInAnOpenNoteWalksNothing() async throws {
        try await loadSidebar()
        delegate.toggleCommenting(nil)
        try await pick(x: "50", y: "45")
        let note = try XCTUnwrap(window.comments?.note)
        XCTAssertTrue(note.hasFocus)
        try await hover(x: 50, y: 45)
        try await send(126)
        try await Task.sleep(for: .milliseconds(200))
        let outlined = try await outline()
        XCTAssertEqual(outlined, [], "↑ in an open note walked the outline")
        let keys = try await tab.webView?.evaluateJavaScript("window.keys") as? [String]
        XCTAssertEqual(keys, [], "the page heard the key")
    }

    func testUpWalksFromTheChrome() async throws {
        try await loadSidebar()
        delegate.toggleCommenting(nil)
        // The test window builds no sidebar, so a view standing for its list takes the keyboard.
        let chrome = Focusable()
        controller.window?.contentView?.addSubview(chrome)
        XCTAssertTrue(try XCTUnwrap(controller.window).makeFirstResponder(chrome))
        try await hover(x: 50, y: 45)
        try await send(126)
        try await assertOutline(on: "nav", "↑ from the sidebar did not walk")
    }

    func testATypedNoteKeepsItsArrows() async throws {
        try await loadSidebar()
        delegate.toggleCommenting(nil)
        try await pick(x: "50", y: "45")
        let note = try XCTUnwrap(window.comments?.note)
        note.textView.insertText("Make it blue", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await hover(x: 50, y: 45)
        try await send(126)
        try await Task.sleep(for: .milliseconds(200))
        let outlined = try await outline()
        XCTAssertEqual(outlined, [], "↑ in a typed note walked the outline")
        XCTAssertEqual(note.textView.selectedRange().location, 0, "the caret did not move up")
    }

    // MARK: Support

    private func loadSidebar() async throws {
        let url = directory.appending(path: "sidebar.html")
        try Self.sidebar.write(to: url, atomically: true, encoding: .utf8)
        tab.load(url)
        try await waitFor { self.tab.state.url == url && !self.tab.state.isLoading }
        try await Task.sleep(for: .milliseconds(100))
    }

    /// A key as AppKit hands one to the key window. Through the window rather
    /// than `NSApp`, which gives it to the key window, and this one never is.
    private func send(_ keyCode: UInt16) async throws {
        let characters = [126: "\u{F700}", 125: "\u{F701}", 36: "\r"][Int(keyCode)] ?? ""
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: keyCode == 36 ? [] : [.numericPad, .function],
            timestamp: 0, windowNumber: controller.window?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
        controller.window?.sendEvent(event)
        try await Task.sleep(for: .milliseconds(50))
    }

    private func hover(x: Double, y: Double) async throws {
        _ = try await tab.webView?.evaluateJavaScript("dispatchEvent(new MouseEvent('mousemove', { clientX: \(x), clientY: \(y) })); 1")
    }

    /// The outline settles on `selector`'s box; the walk is answered asynchronously.
    private func assertOutline(on selector: String, _ message: String, line: UInt = #line) async throws {
        var outlined: [Double]?, wanted: [Double]?
        _ = try await poll {
            outlined = try await self.outline()
            wanted = try await self.rect(of: selector)
            return outlined == wanted
        }
        XCTAssertEqual(outlined, wanted, message, line: line)
    }

    private func outline() async throws -> [Double]? {
        try await tab.webView?.evaluateJavaScript("window.__lunaPicker.outline()", in: nil, contentWorld: .defaultClient) as? [Double]
    }

    private func rect(of selector: String) async throws -> [Double]? {
        try await tab.webView?.evaluateJavaScript("""
        var r = document.querySelector("\(selector)").getBoundingClientRect(); [r.x, r.y, r.width, r.height]
        """) as? [Double]
    }

    private final class Focusable: NSView {
        override var acceptsFirstResponder: Bool { true }
    }
}
