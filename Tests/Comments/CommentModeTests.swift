//
//  CommentModeTests.swift
//  LunaTests
//
//  Comment mode's two commands, View ▸ Comment on Page and Export Comments:
//  when they are offered, and that neither reaches the Command Bar.
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

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        session.setKeyWindow(window.id)
        delegate = AppDelegate()
        delegate.windows = [window]
        delegate.front = window
    }

    override func tearDown() async throws {
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

    // MARK: - Support

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
