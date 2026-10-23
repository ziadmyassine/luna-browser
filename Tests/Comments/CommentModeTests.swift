//
//  CommentModeTests.swift
//  LunaTests
//
//  Comment mode's two commands, View ▸ Comment on Page and Export Comments:
//  when they are offered, that neither reaches the Command Bar, and what an
//  export writes, copies and says.
//
//  The app delegate is a fresh one with a window of its own, never the test
//  host's, and nothing here is put on screen.
//

import AppKit
@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class CommentModeTests: XCTestCase {

    private var directory: URL!
    private var session: BrowserSession!
    private var delegate: AppDelegate!
    private var window: BrowserWindow!

    private let commands = [BrowserCommand.commentOnPage, .exportComments]
    private var pasteboard: NSPasteboard!
    private var bundles: URL { directory.appending(path: "Comments") }
    private var draft: URL { directory.appending(path: "Comment Draft") }

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        session.setKeyWindow(window.id)
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        window.comments?.leave()
        window.controller.close()
        session.tearDown()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Listed

    /// A symbol is what puts a command in the Command Bar; these have none.
    func testNeitherCommandIsInTheCommandBar() {
        for command in commands {
            XCTAssertNil(command.symbolName, command.id)
            XCTAssertFalse(BrowserCommand.commandBarEntries.contains { $0.id == command.id }, command.id)
        }
    }

    func testBothAreInTheViewMenuAfterHideSomething() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let view = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu)
        let hide = try XCTUnwrap(view.items.firstIndex { $0.action == BrowserCommand.hideElements.action })
        XCTAssertEqual(view.items[hide + 1].action, BrowserCommand.commentOnPage.action)
        XCTAssertEqual(view.items[hide + 2].action, BrowserCommand.exportComments.action)
    }

    // MARK: - Offered

    /// The positive case first, so the refusals below are refusals and not a
    /// command that is never offered at all.
    func testBothAreOfferedOnALivePage() async throws {
        try await open(page())
        XCTAssertEqual(offered(), [true, true])
    }

    func testBothDimWithNoLivePage() {
        XCTAssertEqual(offered(), [false, false])
    }

    /// A draft on disk would break the private window's promise.
    func testBothDimInAPrivateWindow() async throws {
        let hidden = try await BrowserSession.restored(
            store: BrowserStore(path: directory.appending(path: "private/luna.sqlite")), isPrivate: true
        )
        let privateWindow = BrowserWindow(session: hidden, controller: BrowserWindowController(remembersFrame: false))
        hidden.setKeyWindow(privateWindow.id)
        delegate.front = privateWindow
        defer {
            privateWindow.controller.close()
            hidden.tearDown()
        }
        try await open(page(), in: hidden)
        XCTAssertEqual(offered(), [false, false])
    }

    /// Reader's markup is Luna's, not the site's.
    func testBothDimInReader() async throws {
        let controller = try await open(page())
        let answer = await withCheckedContinuation { done in controller.toggleReader { done.resume(returning: $0) } }
        XCTAssertEqual(answer, .on)
        XCTAssertEqual(offered(), [false, false])
    }

    /// WebKit's PDF viewer runs no script, so there is nothing to pick.
    func testBothDimOnAPDF() async throws {
        let pdf = directory.appending(path: "one.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let controller = try await open(pdf)
        XCTAssertTrue(controller.state.isPDF)
        XCTAssertEqual(offered(), [false, false])
    }

    // MARK: - Nothing while off

    /// Comment mode costs nothing until ⇧⌘M: no set, no mode, no picker in the
    /// page; and once it ends, no mode and no outline are left behind.
    func testNothingOfCommentModeExistsBeforeEnteringOrAfterLeaving() async throws {
        let controller = try await open(page())
        XCTAssertEqual(offered(), [true, true])
        XCTAssertNil(delegate.commentSet, "the set was made before ⇧⌘M")
        XCTAssertNil(window.comments)
        XCTAssertFalse(controller.isDescribingElements)
        let installed = "typeof window.__lunaPicker"
        let before = try await controller.webView?.evaluateJavaScript(installed, in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(before as? String, "undefined", "the picker script ran before ⇧⌘M")

        delegate.commentSet = CommentSet(folder: draft)
        delegate.toggleCommenting(nil)
        XCTAssertNotNil(window.comments, "comment mode never started, so leaving proves nothing")
        delegate.toggleCommenting(nil)
        XCTAssertNil(window.comments)
        XCTAssertFalse(controller.isDescribingElements)
        let outline = try await controller.webView?.evaluateJavaScript("document.querySelector('luna-picker') === null")
        XCTAssertEqual(outline as? Bool, true, "the picker's outline outlived the mode")
    }

    // MARK: - Export

    /// Only the front page's line, even with another origin's comment first.
    func testExportCopiesTheFrontPagesPromptAndNothingElse() async throws {
        try await open(page())
        let set = try comments(["localhost-3002", "file"])

        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), CommentBundle.prompt(for: bundle("file")))
        XCTAssertTrue(set.comments.isEmpty)
    }

    func testWithNoCommentOnTheFrontPageTheFirstOriginIsCopied() throws {
        try comments(["trego.dk", "localhost-3002"])

        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), CommentBundle.prompt(for: bundle("trego.dk")))
    }

    func testTheToastCountsTheCopiedSiteAndNamesTheOthers() async throws {
        try await open(page())
        try comments(["localhost-3002", "file", "trego.dk", "file"])

        let toast = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        XCTAssertEqual(toast, .commentsExported(2, copied: "file", others: ["localhost-3002", "trego.dk"]) {})
        XCTAssertEqual(toast?.detail, "2 comments on file, also localhost-3002, trego.dk")
        XCTAssertEqual(toast?.actions.map(\.title), ["Reveal"])
        for origin in ["file", "localhost-3002", "trego.dk"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: bundle(origin).path), origin)
        }
    }

    /// ⌘Z is the Edit menu's, which reaches the session's list, not the set's.
    func testCommandZBringsBackWhatTheExportCleared() async throws {
        try await open(page())
        let set = try comments(["file", "file"])
        let before = set.comments

        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)
        XCTAssertTrue(set.comments.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        delegate.undo(nil)

        XCTAssertEqual(set.comments, before)
    }

    func testAFailedWriteKeepsTheSetAndTheDraft() async throws {
        try await open(page())
        let set = try comments(["file"])
        let before = set.comments
        try FileManager.default.createDirectory(at: bundles, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bundles.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundles.path) }
        var reason = ""
        let folder = bundles.appending(path: "file")
        XCTAssertThrowsError(try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) {
            reason = $0.localizedDescription
        }

        let toast = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        XCTAssertEqual(toast, .commentsNotExported(reason))
        XCTAssertEqual(toast?.detail, reason)
        XCTAssertEqual(set.comments, before)
        let saved = try JSONDecoder().decode([Comment].self, from: Data(contentsOf: draft.appending(path: "draft.json")))
        XCTAssertEqual(saved, before)
        XCTAssertNil(pasteboard.string(forType: .string), "a prompt for a bundle that was never written")
    }

    /// Nothing to export says nothing and leaves the clipboard alone.
    func testExportingNoCommentsDoesNothing() async throws {
        try await open(page())
        try comments([])
        pasteboard.clearContents()
        pasteboard.setString("kept", forType: .string)

        XCTAssertNil(delegate.exportComments(to: bundles, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "kept")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundles.path))
    }

    // MARK: - Support

    /// A set of the test's own with one captured comment per origin, in order.
    @discardableResult
    private func comments(_ origins: [String]) throws -> CommentSet {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let set = CommentSet(folder: draft, undoManager: undo)
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)
        for origin in origins {
            let comment = Comment.fixture(origin: origin)
            for name in [comment.image, comment.context].compactMap(\.self) {
                try Data("png".utf8).write(to: draft.appending(path: name))
            }
            set.add(comment)
        }
        delegate.commentSet = set
        return set
    }

    private func bundle(_ origin: String) -> URL {
        bundles.appending(path: origin).appending(path: "COMMENTS.md")
    }

    private func offered() -> [Bool] {
        commands.map { delegate.validateMenuItem(NSMenuItem(title: "", action: $0.action, keyEquivalent: "")) }
    }

    /// An article long enough for Reader to find.
    private func page() throws -> URL {
        let prose = (1...6).map { "<p>Paragraph \($0), long enough to count as prose, with a comma, and another.</p>" }
        let url = directory.appending(path: "page.html")
        try "<html><body><div class=\"story\"><h1>Headline</h1>\(prose.joined())</div></body></html>"
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func open(_ url: URL, in target: BrowserSession? = nil) async throws -> TabController {
        let session = target ?? session!
        let space = try XCTUnwrap(session.spaces.first)
        let tab = Tab(spaceID: space.id, kind: .today, url: url)
        session.persistAll(session.list.insert(tab, at: TabList.openIndex(for: .today)))
        session.activateTab(tab.id)
        _ = session.webView(for: tab.id)
        let controller = try XCTUnwrap(session.controller(for: tab.id))
        controller.load(url)
        for _ in 0..<100 {
            if controller.state.url == url, !controller.state.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(controller.state.isLoading, "the page never finished loading")
        return controller
    }
}
