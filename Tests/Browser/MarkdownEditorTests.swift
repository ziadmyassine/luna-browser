//
//  MarkdownEditorTests.swift
//  LunaTests
//
//  The Markdown editor inside Luna's web view: ⌘Z and ⌘S reach the editor
//  rather than the window's list and the sidebar toggle, and the pill says
//  when the file is behind the editor.
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class MarkdownEditorTests: XCTestCase {

    private var folder: URL!
    private var controller: TabController!
    private var window: NSWindow!
    private var windowList: SessionUndoManager!
    private var windowDelegate: WindowUndo!
    private var restoredHidden = 0

    /// The window's list, as `BrowserWindowController` hands it out, with a
    /// hidden element waiting behind it.
    private final class WindowUndo: NSObject, NSWindowDelegate {
        let list: UndoManager
        init(_ list: UndoManager) { self.list = list }
        func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { list }
    }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "luna-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        windowList = SessionUndoManager()
        windowList.whenEmpty = { [weak self] in self?.restoredHidden += 1; return true }
        windowList.canUndoWhenEmpty = { true }
        windowDelegate = WindowUndo(windowList)
        // Off-screen and never ordered front: nothing here takes focus.
        window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 1400, height: 800),
                          styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let view = try XCTUnwrap(controller.webView)
        view.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
        window.contentView?.addSubview(view)
    }

    override func tearDown() async throws {
        controller.hibernate()
        controller = nil
        window.close()
        window = nil
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Undo

    func testUndoAndRedoTyping() async throws {
        try await openInEdit("# Hello")
        try await type("!")
        try await undo()
        try await assertEditor("# Hello")
        try await redo()
        try await assertEditor("# Hello!")
    }

    func testUndoStillWorksAfterAnAutosave() async throws {
        let file = try await openInEdit("# Hello")
        try await type("!")
        try await Task.sleep(for: .milliseconds(1_600))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!", "no autosave")
        try await undo()
        try await assertEditor("# Hello")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(controller.state.isEdited, "the undone text is not the file's")
    }

    func testUndoStillWorksAfterCommandS() async throws {
        let file = try await openInEdit("# Hello")
        try await type("!")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(try view().performKeyEquivalent(with: commandS()))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
        try await undo()
        try await assertEditor("# Hello")
    }

    func testUndoStillWorksAfterReadAndBackToEdit() async throws {
        try await openInEdit("# Hello")
        try await type("!")
        controller.setReadingView(.read)
        try await Task.sleep(for: .milliseconds(200))
        controller.setReadingView(.edit)
        try await Task.sleep(for: .milliseconds(200))
        try await undo()
        try await assertEditor("# Hello")
    }

    /// The window's list ends in restoring hidden elements and holds closed
    /// tabs; an empty editor list must not fall through to it.
    func testEditorUndoNeverReachesTheWindowsList() async throws {
        try await openInEdit("# Hello")
        let view = try view()
        XCTAssertTrue(view.undoManager === controller.editorUndoManager)
        XCTAssertFalse(view.undoManager === windowList)
        try await undo()
        XCTAssertEqual(restoredHidden, 0, "⌘Z in the editor restored a hidden element")

        controller.setReadingView(.read)
        XCTAssertFalse(view.responds(to: Selector(("undo:"))))
        XCTAssertTrue(view.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertEqual(restoredHidden, 1, "outside Edit the window's ⌘Z stopped working")
    }

    // MARK: - ⌘S

    /// The web view claims ⌘S before the main menu is asked, so the sidebar
    /// toggle never sees it in Edit — on its default ⌘S or rebound elsewhere.
    func testCommandSSavesInEditWhateverTheSidebarToggleIsBoundTo() async throws {
        XCTAssertEqual(BrowserCommand.toggleSidebar.defaults.first, KeyBinding("s"))
        let file = try await openInEdit("# Hello")
        try await type("!")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(try view().performKeyEquivalent(with: commandS()))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Hello!")
        XCTAssertFalse(controller.state.isEdited)
    }

    func testCommandSIsLeftToTheSidebarOutsideEdit() async throws {
        try await openInEdit("# Hello")
        controller.setReadingView(.read)
        XCTAssertFalse(try view().performKeyEquivalent(with: commandS()))
    }

    // MARK: - Pill

    func testThePillSaysEditedUntilTheWriteLands() {
        let pill = URLPillView()
        pill.show(url: URL(fileURLWithPath: "/tmp/README.md"))
        XCTAssertEqual(pill.field.stringValue, "README.md")
        pill.isEdited = true
        XCTAssertEqual(pill.field.stringValue, "README.md — Edited")
        pill.isEdited = false
        XCTAssertEqual(pill.field.stringValue, "README.md")
    }

    // MARK: - Support

    @discardableResult
    private func openInEdit(_ text: String) async throws -> URL {
        let file = folder.appending(path: "README.md")
        try Data(text.utf8).write(to: file)
        controller.load(file)
        let view = try view()
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0 ..< 100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(150))
        controller.setReadingView(.edit)
        try await Task.sleep(for: .milliseconds(150))
        return file
    }

    private func view() throws -> LunaWebView {
        try XCTUnwrap(controller.webView as? LunaWebView, "pages are not LunaWebViews")
    }

    /// Through WebKit's editor, so the step lands on the undo list.
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
        try await Task.sleep(for: .milliseconds(150))
    }

    /// What ⌘Z and ⇧⌘Z send, from the web view up the responder chain.
    private func undo() async throws {
        _ = try view().tryToPerform(Selector(("undo:")), with: nil)
        try await Task.sleep(for: .milliseconds(200))
    }

    private func redo() async throws {
        _ = try view().tryToPerform(Selector(("redo:")), with: nil)
        try await Task.sleep(for: .milliseconds(200))
    }

    private func editorText() async throws -> String? {
        try await controller.webView?.evaluateJavaScript("document.querySelector('.luna-input').value") as? String
    }

    private func assertEditor(_ expected: String, line: UInt = #line) async throws {
        let shown = try await editorText()
        XCTAssertEqual(shown, expected, line: line)
    }

    private func commandS() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "s",
            charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1
        ))
    }
}
