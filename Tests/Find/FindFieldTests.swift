//
//  FindFieldTests.swift
//  LunaTests
//
//  §18.1's find field in a real window over a real page: ⌘F opens it with
//  the keyboard in it, typing searches, Return and Shift-Return step, the
//  count follows, and Escape closes it and gives the page the keyboard back.
//

import AppKit
@testable import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class FindFieldTests: XCTestCase {

    private var directory: URL!
    private var session: BrowserSession!
    private var controller: BrowserWindowController!
    private var window: BrowserWindow!
    private var find: FindController!
    private var webView: WKWebView!

    private static let page = """
    <html><body><h1>Moon</h1><p>The moon is up. A moonlit night.</p><p>Moon again.</p></body></html>
    """

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        controller = BrowserWindowController(remembersFrame: false)
        window = BrowserWindow(session: session, controller: controller)
        session.setKeyWindow(window.id)
        let tab = session.newTab(url: nil)
        session.activateTab(tab, inWindow: window.id)
        webView = try XCTUnwrap(session.webView(for: tab) as? WKWebView)
        controller.setContent(webView)
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.invalid/moon"))
        try await settle()
        find = FindController(session: session, windowID: window.id, surface: controller.controlSurface, isPrivate: false)
        find.findPasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() async throws {
        find.findPasteboard.releaseGlobally()
        find = nil
        window.close()
        controller.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testFindOpensTheFieldWithTheKeyboardInIt() throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        XCTAssertTrue(bar.superview === controller.controlSurface, "the field is not over the page")
        XCTAssertTrue(bar.hasFocus, "⌘F left the keyboard where it was")
    }

    func testTypingSearchesAndCountsAndReturnSteps() async throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        try type("moon", into: bar)
        try await waitFor { self.find.result?.match == 1 }
        XCTAssertEqual(find.result?.total, 4)
        XCTAssertEqual(bar.count.stringValue, "1 of 4")

        try editor(of: bar).doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await waitFor { self.find.result?.match == 2 }
        XCTAssertTrue(bar.handle(#selector(NSResponder.insertNewline(_:)), shift: true))
        try await waitFor { self.find.result?.match == 1 }
        // Previous from the first match wraps round to the last.
        find.findPrevious()
        try await waitFor { self.find.result?.match == 4 }
        XCTAssertEqual(bar.count.stringValue, "4 of 4")
    }

    func testAQueryWithNoMatchesSaysSoAndCannotStep() async throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        try type("sunrise", into: bar)
        try await waitFor { self.find.result != nil }
        XCTAssertEqual(bar.count.stringValue, "No matches")
        XCTAssertFalse(bar.next.isEnabled)
        XCTAssertFalse(bar.previous.isEnabled)
    }

    func testEscapeClosesTheFieldAndGivesThePageTheKeyboard() async throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        try type("moon", into: bar)
        try await waitFor { self.find.result != nil }
        try editor(of: bar).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(find.isOpen)
        XCTAssertNil(find.result, "the count outlived the field")
        XCTAssertTrue(controller.window?.firstResponder === webView, "the page did not get the keyboard back")
        // The query did not go with it: ⌘F again starts from it, selected.
        find.open()
        XCTAssertEqual(find.bar?.query, "moon")
        XCTAssertEqual(try editor(of: XCTUnwrap(find.bar)).selectedRange(), NSRange(location: 0, length: 4))
    }

    /// With the keyboard in the page, the Escape that reaches the window closes
    /// the field, and only that: it is not the first of fullscreen's two.
    func testAnEscapeFromThePageClosesItToo() throws {
        find.open()
        controller.window?.makeFirstResponder(webView)
        XCTAssertTrue(LunaWindow.escapeClosesFind(find))
        XCTAssertFalse(find.isOpen)
        XCTAssertTrue(controller.window?.firstResponder === webView)
        XCTAssertFalse(LunaWindow.escapeClosesFind(find), "an Escape with no field to close was swallowed")
    }

    /// ⌘F on an open field puts the keyboard back in it, the query selected.
    func testFindAgainSelectsTheQuery() throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        bar.query = "moon"
        controller.window?.makeFirstResponder(webView)
        find.open()
        XCTAssertTrue(find.bar === bar, "a second ⌘F built a second field")
        XCTAssertTrue(bar.hasFocus)
        XCTAssertEqual(try editor(of: bar).selectedRange(), NSRange(location: 0, length: 4))
    }

    /// The field belongs to the page it was opened over.
    func testSwitchingTabsClosesIt() async throws {
        find.open()
        let other = session.newTab(url: nil)
        session.activateTab(other, inWindow: window.id)
        XCTAssertFalse(find.isOpen)
    }

    /// A new page under the field keeps the query and loses the count, which
    /// was the old page's.
    func testANewPageClearsTheCount() async throws {
        find.open()
        let bar = try XCTUnwrap(find.bar)
        try type("moon", into: bar)
        try await waitFor { self.find.result != nil }
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.invalid/another"))
        try await waitFor { self.find.result == nil }
        XCTAssertTrue(find.isOpen)
        XCTAssertEqual(bar.query, "moon")
        XCTAssertTrue(bar.count.isHidden)
    }

    /// ⌘E: the selection is the query, and the field opens on it without
    /// taking the keyboard.
    func testUseSelectionForFindOpensOnTheSelection() async throws {
        find.useSelection("moonlit")
        let bar = try XCTUnwrap(find.bar)
        XCTAssertEqual(bar.query, "moonlit")
        XCTAssertFalse(bar.hasFocus)
        try await waitFor { self.find.result?.total == 1 }
        XCTAssertEqual(find.findPasteboard.string(forType: .string), "moonlit", "the find pasteboard was not told")
    }

    /// A private window reads the find pasteboard and never writes it.
    func testAPrivateWindowLeavesTheFindPasteboardAlone() {
        let quiet = FindController(session: session, windowID: window.id, surface: controller.controlSurface, isPrivate: true)
        quiet.findPasteboard = NSPasteboard.withUniqueName()
        defer { quiet.findPasteboard.releaseGlobally() }
        quiet.useSelection("moon")
        XCTAssertNil(quiet.findPasteboard.string(forType: .string))
        quiet.close()
    }

    // MARK: - The field on its own

    func testTheCountSaysWhereTheMatchIs() {
        XCTAssertNil(FindBarView.countText(for: nil))
        XCTAssertEqual(FindBarView.countText(for: .notFound), "No matches")
        XCTAssertEqual(FindBarView.countText(for: FindResult(found: true, match: 3, total: 12)), "3 of 12")
        // The figures are the user's locale's: 1000 may be written 1,000 or 1.000.
        let capped = FindBarView.countText(for: FindResult(found: true, match: 3, total: 1000, isCapped: true))
        XCTAssertTrue(capped?.hasPrefix("3 of 1") == true && capped?.hasSuffix("000+") == true, capped ?? "nil")
        XCTAssertNil(FindBarView.countText(for: FindResult(found: true)), "a match the count could not place")
    }

    func testReturnIsNextShiftReturnIsPreviousAndEscapeCloses() {
        let bar = FindBarView()
        var heard: [String] = []
        bar.onNext = { heard.append("next") }
        bar.onPrevious = { heard.append("previous") }
        bar.onClose = { heard.append("close") }
        XCTAssertTrue(bar.handle(#selector(NSResponder.insertNewline(_:)), shift: false))
        XCTAssertTrue(bar.handle(#selector(NSResponder.insertNewline(_:)), shift: true))
        XCTAssertTrue(bar.handle(#selector(NSResponder.cancelOperation(_:)), shift: false))
        XCTAssertFalse(bar.handle(#selector(NSResponder.moveLeft(_:)), shift: false), "the field's own keys were taken")
        XCTAssertEqual(heard, ["next", "previous", "close"])
    }

    /// VoiceOver hears what each control is.
    func testEveryControlIsLabelled() {
        let bar = FindBarView()
        XCTAssertEqual(bar.accessibilityLabel(), "Find on Page")
        XCTAssertEqual(bar.field.accessibilityLabel(), "Find on Page")
        XCTAssertEqual(bar.previous.accessibilityLabel(), "Previous Match")
        XCTAssertEqual(bar.next.accessibilityLabel(), "Next Match")
        XCTAssertEqual(bar.close.accessibilityLabel(), "Close Find")
    }

    /// The capsule never runs off a page narrower than itself.
    func testANarrowPaneSqueezesTheFieldNotTheCapsule() throws {
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let surface = ControlSurfaceView(frame: card.bounds)
        card.addSubview(surface)
        let bar = FindBarView()
        surface.showFindBar(bar)
        card.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(bar.frame.minX, Tokens.Metric.pageBarInset - 0.5)
        XCTAssertEqual(bar.frame.maxX, 300 - Tokens.Metric.pageBarInset, accuracy: 0.5)
        XCTAssertEqual(bar.frame.height, Tokens.Metric.capsuleHeight, accuracy: 0.5)
        let close = bar.close.convert(bar.close.bounds, to: bar)
        XCTAssertLessThanOrEqual(close.maxX, bar.bounds.maxX + 0.5, "the close button was pushed out of the capsule")
        // With no count showing, a full-width capsule gives the field the count's room as well.
        let roomy = Tokens.Metric.findFieldText + Tokens.Metric.findCountWidth + Tokens.Metric.chromeGap
        XCTAssertLessThan(bar.field.frame.width, roomy - 1, "the field did not give way")
    }

    // MARK: - Helpers

    private func editor(of bar: FindBarView) throws -> NSTextView {
        try XCTUnwrap(bar.field.currentEditor() as? NSTextView, "the field has no editor: it never had focus")
    }

    /// Typed into the field editor, so the field hears it the way it hears a
    /// keyboard.
    private func type(_ text: String, into bar: FindBarView) throws {
        let editor = try editor(of: bar)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func waitFor(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0 ..< 100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0 ..< 100 where webView.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
    }
}
