//
//  CommentModeTests.swift
//  LunaTests
//
//  Comment mode's two commands, Review ▸ Comment on Page and Export Comments:
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

    var directory: URL!
    var session: BrowserSession!
    var delegate: AppDelegate!
    private var window: BrowserWindow!

    private let commands = [BrowserCommand.commentOnPage, .exportComments]
    var pasteboard: NSPasteboard!
    var bundles: URL { directory.appending(path: "Comments") }
    var drafts: URL { directory.appending(path: "Comment Drafts") }

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        session.setKeyWindow(window.id)
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
        delegate.commentDrafts = drafts
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

    func testBothAreAloneInAReviewMenuAfterView() throws {
        MainMenu.rebuild(in: NSApplication.shared)
        let bar = try XCTUnwrap(NSApp.mainMenu?.items)
        let view = try XCTUnwrap(bar.firstIndex { $0.title == "View" })
        XCTAssertEqual(bar[view + 1].title, "Review")
        let review = try XCTUnwrap(bar[view + 1].submenu)
        XCTAssertEqual(review.items.map(\.action), commands.map(\.action))
        XCTAssertEqual(review.items.first?.keyEquivalent, "m")
        XCTAssertEqual(review.items.first?.keyEquivalentModifierMask, [.shift, .command])
        let viewItems = try XCTUnwrap(bar[view].submenu).items.map(\.action)
        XCTAssertTrue(viewItems.contains(BrowserCommand.hideElements.action), "Hide Something… left View")
        XCTAssertFalse(commands.contains { viewItems.contains($0.action) }, "View still lists a comment command")
        // The menu's own items, not stand-ins: the delegate validates them where they are.
        XCTAssertEqual(review.items.map { delegate.validateMenuItem($0) }, [false, false])
    }

    // MARK: - Offered

    /// The positive case first, so the refusals below are refusals and not a
    /// command that is never offered at all.
    func testBothAreOfferedOnALivePageWithComments() async throws {
        try await open(page())
        try comments(1)
        XCTAssertEqual(offered(), [true, true])
    }

    func testExportDimsWithNoComments() async throws {
        try await open(page())
        try comments(0)
        XCTAssertEqual(offered(), [true, false])
    }

    /// Export is the front page's draft; another page's comments wait for that page.
    func testExportDimsWhenOnlyAnotherPageHasComments() async throws {
        try await open(page())
        try comments(1, on: page("other.html"))
        XCTAssertEqual(offered(), [true, false])
    }

    func testNeitherIsOfferedWithNoLivePage() throws {
        try comments(1, on: page())
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
        try comments(1, on: page())
        XCTAssertEqual(offered(), [false, false])
    }

    /// Reader's markup is Luna's, not the site's; what was said elsewhere still exports.
    func testOnlyExportIsOfferedInReader() async throws {
        let controller = try await open(page())
        try comments(1)
        let answer = await withCheckedContinuation { done in controller.toggleReader { done.resume(returning: $0) } }
        XCTAssertEqual(answer, .on)
        XCTAssertEqual(offered(), [false, true])
    }

    /// WebKit's PDF viewer runs no script, so there is nothing to pick.
    func testOnlyExportIsOfferedOnAPDF() async throws {
        let pdf = directory.appending(path: "one.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let controller = try await open(pdf)
        try comments(1)
        XCTAssertTrue(controller.state.isPDF)
        XCTAssertEqual(offered(), [false, true])
    }

    // MARK: - Nothing while off

    /// Comment mode costs nothing until ⇧⌘M: no set, no mode, no picker in the
    /// page; and once it ends, no mode and no outline are left behind.
    func testNothingOfCommentModeExistsBeforeEnteringOrAfterLeaving() async throws {
        let controller = try await open(page())
        XCTAssertEqual(offered().first, true)
        XCTAssertTrue(delegate.commentSets.isEmpty, "a draft was made before ⇧⌘M")
        XCTAssertNil(window.comments)
        XCTAssertFalse(controller.isDescribingElements)
        let installed = "typeof window.__lunaPicker"
        let before = try await controller.webView?.evaluateJavaScript(installed, in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(before as? String, "undefined", "the picker script ran before ⇧⌘M")

        delegate.toggleCommenting(nil)
        XCTAssertNotNil(window.comments, "comment mode never started, so leaving proves nothing")
        delegate.toggleCommenting(nil)
        XCTAssertNil(window.comments)
        XCTAssertFalse(controller.isDescribingElements)
        let outline = try await controller.webView?.evaluateJavaScript("document.querySelector('luna-picker') === null")
        XCTAssertEqual(outline as? Bool, true, "the picker's outline outlived the mode")
    }

    // MARK: - Export

    /// The front page's comments only, into a folder of their own, and that
    /// folder's prompt; the other page's draft waits for its own export.
    func testExportWritesTheFrontPagesDraftAndCopiesItsPrompt() async throws {
        try await open(page())
        let here = try comments(2)
        let other = try comments(1, on: page("other.html"))

        let toast = delegate.exportComments(to: bundles, pasteboard: pasteboard)

        let written = try exported()
        XCTAssertEqual(written.count, 1)
        let file = try XCTUnwrap(written.first).appending(path: "COMMENTS.md")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), CommentBundle.prompt(for: file))
        XCTAssertEqual(toast, .commentsExported(2, site: "file") {})
        XCTAssertEqual(toast?.detail, "2 comments on file")
        XCTAssertEqual(toast?.actions.map(\.title), ["Reveal"])
        XCTAssertTrue(here.comments.isEmpty)
        XCTAssertEqual(other.comments.count, 1)
    }

    /// ⌘Z is the Edit menu's, which reaches the session's list, not the set's.
    func testCommandZBringsBackWhatTheExportCleared() async throws {
        try await open(page())
        let set = try comments(2)
        let before = set.comments

        _ = delegate.exportComments(to: bundles, pasteboard: pasteboard)
        XCTAssertTrue(set.comments.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        delegate.undo(nil)

        XCTAssertEqual(set.comments, before)
    }

    /// Export A, comment, export B: ⌘Z brings back B's comments, and the next
    /// ⌘Z is the step before A, not A's export eating a keystroke for nothing.
    func testCommandZUndoesOnlyItsOwnExport() async throws {
        try await open(page())
        var earlier = false
        event { session.undoManager.registerUndo(withTarget: self) { _ in earlier = true } }
        let set = try comments(1)
        event { _ = delegate.exportComments(to: bundles, pasteboard: pasteboard) }
        try add(to: set)
        let second = set.comments
        event { _ = delegate.exportComments(to: bundles, pasteboard: pasteboard) }

        delegate.undo(nil)
        XCTAssertEqual(set.comments, second)
        delegate.undo(nil)

        XCTAssertEqual(set.comments, second, "the first export's ⌘Z changed the set")
        XCTAssertTrue(earlier, "the first export's ⌘Z was spent doing nothing")
    }

    func testAFailedWriteKeepsTheSetAndTheDraft() async throws {
        try await open(page())
        let set = try comments(1)
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
        let saved = try JSONDecoder().decode([Comment].self, from: Data(contentsOf: set.folder.appending(path: "draft.json")))
        XCTAssertEqual(saved, before)
        XCTAssertNil(pasteboard.string(forType: .string), "a prompt for a bundle that was never written")
    }

    /// Nothing to export says nothing and leaves the clipboard alone.
    func testExportingNoCommentsDoesNothing() async throws {
        try await open(page())
        try comments(0)
        pasteboard.clearContents()
        pasteboard.setString("kept", forType: .string)

        XCTAssertNil(delegate.exportComments(to: bundles, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "kept")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundles.path))
    }

    // MARK: - Support

    /// The page's draft, with a list the test closes itself, holding `count` captured comments.
    @discardableResult
    func comments(_ count: Int, on url: URL? = nil) throws -> CommentSet {
        let url = try url ?? XCTUnwrap(session.activeURL)
        let page = CommentSet.page(of: url.absoluteString)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let set = CommentSet(folder: CommentSet.folder(for: page, in: drafts), undoManager: undo)
        delegate.commentSets[page] = set
        for _ in 0 ..< count { try add(to: set) }
        return set
    }

    /// One captured comment on the set's page, its pictures already in its draft.
    func add(_ note: String = "Make it taller", to set: CommentSet) throws {
        let page = try XCTUnwrap(delegate.commentSets.first { $0.value === set }?.key)
        let comment = Comment.fixture(origin: "file", url: page, note: note)
        try FileManager.default.createDirectory(at: set.folder, withIntermediateDirectories: true)
        for name in [comment.image, comment.context].compactMap(\.self) {
            try Data("png".utf8).write(to: set.folder.appending(path: name))
        }
        set.add(comment)
    }

    /// One menu command's worth of the session's list, closed as the run loop would close it.
    private func event(_ body: () -> Void) {
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        body()
        session.undoManager.endUndoGrouping()
    }

    func offered() -> [Bool] {
        commands.map { delegate.validateMenuItem(NSMenuItem(title: "", action: $0.action, keyEquivalent: "")) }
    }

    /// An article long enough for Reader to find.
    func page(_ name: String = "page.html") throws -> URL {
        let prose = (1...6).map { "<p>Paragraph \($0), long enough to count as prose, with a comma, and another.</p>" }
        let url = directory.appending(path: name)
        try "<html><body><div class=\"story\"><h1>Headline</h1>\(prose.joined())</div></body></html>"
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func open(_ url: URL, in target: BrowserSession? = nil) async throws -> TabController {
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
