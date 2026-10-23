//
//  BugReportTests.swift
//  LunaTests
//
//  What a bug report gathers: the commands run before it, and the picture
//  it puts on the pasteboard. Actions go to a probe, never to Luna;
//  `screencapture` is a stand-in and the pasteboard a private one; nothing
//  takes focus.
//

import AppKit
@testable import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
private final class Probe: NSObject {
    @objc func newTab(_ sender: Any?) {}
    @objc func closeTab(_ sender: Any?) {}
    @objc func notACommand(_ sender: Any?) {}
    @objc func reportBugPage(_ sender: Any?) {}
    @objc func suggestIdea(_ sender: Any?) {}
}

@MainActor
final class BugReportTests: XCTestCase {

    private let probe = Probe()

    // MARK: - Recent commands

    func testTheAppIsLunas() {
        XCTAssertTrue(NSApp is LunaApplication)
    }

    func testASentCommandIsRemembered() {
        NSApp.sendAction(#selector(Probe.newTab(_:)), to: probe, from: nil)
        XCTAssertEqual(RecentCommands.titles.last, "New Tab")
    }

    func testAMenuClickIsRemembered() {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Close Tab", action: #selector(Probe.closeTab(_:)), keyEquivalent: "")
        item.target = probe
        menu.performActionForItem(at: 0)
        XCTAssertEqual(RecentCommands.titles.last, "Close Tab")
    }

    func testAKeyEquivalentIsRemembered() throws {
        NSApp.sendAction(#selector(Probe.closeTab(_:)), to: probe, from: nil)
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "New Tab", action: #selector(Probe.newTab(_:)), keyEquivalent: "t")
        item.target = probe
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17
        ))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(RecentCommands.titles.last, "New Tab")
    }

    func testOnlyTheLastTenAreKept() {
        for _ in 0..<12 { NSApp.sendAction(#selector(Probe.newTab(_:)), to: probe, from: nil) }
        XCTAssertEqual(RecentCommands.titles.count, 10)
    }

    /// A command nothing handled did not happen. Search Settings is answered
    /// only by a key Settings window, and the test host has none.
    func testAnUnhandledCommandIsNotRemembered() {
        let before = RecentCommands.titles
        XCTAssertFalse(NSApp.sendAction(BrowserCommand.searchSettings.action, to: nil, from: nil))
        XCTAssertEqual(RecentCommands.titles, before)
    }

    /// A report's "Before this:" is what led to the bug, not earlier reports.
    func testReportsAreNotRemembered() {
        NSApp.sendAction(#selector(Probe.newTab(_:)), to: probe, from: nil)
        let before = RecentCommands.titles
        NSApp.sendAction(#selector(Probe.reportBugPage(_:)), to: probe, from: nil)
        NSApp.sendAction(#selector(Probe.suggestIdea(_:)), to: probe, from: nil)
        XCTAssertEqual(RecentCommands.titles, before)
    }

    func testAnythingElseIsNotRemembered() {
        let before = RecentCommands.titles
        NSApp.sendAction(#selector(Probe.notACommand(_:)), to: probe, from: nil)
        XCTAssertEqual(RecentCommands.titles, before)
    }

    // MARK: - Where it is offered

    /// A private window is signed out of GitHub, and its pages are not to be
    /// pictured.
    func testTheCommandsDimInAPrivateWindow() async throws {
        let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = AppDelegate()
        for isPrivate in [false, true] {
            let store = try BrowserStore(path: directory.appending(path: "\(isPrivate).sqlite"))
            let session = try await BrowserSession.restored(store: store, isPrivate: isPrivate)
            let window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
            delegate.front = window
            for action in AppDelegate.reportActions {
                let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
                XCTAssertEqual(delegate.validateMenuItem(item), !isPrivate, "\(action), private: \(isPrivate)")
            }
            window.controller.close()
            session.tearDown()
        }
    }

    /// The layout is in the first line, the one trimming never drops.
    func testTheFirstContextLineNamesTheLayout() async throws {
        let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await BrowserSession.restored(store: BrowserStore(path: directory.appending(path: "luna.sqlite")))
        let window = BrowserWindow(session: session, controller: BrowserWindowController(remembersFrame: false))
        defer {
            window.controller.close()
            session.tearDown()
        }
        let first = try XCTUnwrap(AppDelegate().reportContext(window, tab: nil).first)
        XCTAssertTrue(first.hasPrefix("Page: window "), first)
        XCTAssertNotNil(first.firstMatch(of: #/, Luna (dark|light), /#), "the appearance is not plainly Luna's: \(first)")
        XCTAssertTrue(first.hasSuffix(", \(Settings.chromeLayout.title) layout"), first)
    }

    /// The colour the find field reads, as a hex a fixer can compare. Left
    /// out while the page loads: until then it is the blank tab's.
    func testThePageBackgroundIsItsHexOnceLoaded() {
        XCTAssertEqual(AppDelegate.pageBackground(RGBA(r: 1, g: 1, b: 1, a: 1), loading: false), "#ffffff")
        XCTAssertEqual(AppDelegate.pageBackground(RGBA(r: 0.118, g: 0.5, b: 0, a: 1), loading: false), "#1e8000")
        XCTAssertNil(AppDelegate.pageBackground(RGBA(r: 0.118, g: 0.118, b: 0.118, a: 1), loading: true))
        XCTAssertNil(AppDelegate.pageBackground(nil, loading: false))
    }

    // MARK: - Which tab

    /// Reporting from an issue on this repo (the form just filed, say) is
    /// about the page before it: the newest other tab with a page, in the
    /// window's Space, that is not an issue page itself.
    func testAReportFromAnIssuePageIsAboutTheTabBefore() {
        let (issue, form, page, elsewhere, asleep) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let urls = [
            issue: URL(string: "https://github.com/ziadmyassine/luna-browser/issues/238"),
            form: URL(string: "https://github.com/ziadmyassine/luna-browser/issues/new?template=bug_report.yml"),
            page: URL(string: "https://example.com/")
        ]
        let url = { (id: UUID) in urls[id] ?? nil }
        XCTAssertEqual(AppDelegate.reportedTab(active: issue, recent: [issue, elsewhere, asleep, form, page], url: url), page)
        XCTAssertEqual(AppDelegate.reportedTab(active: page, recent: [page, issue], url: url), page, "an ordinary page is its own")
        XCTAssertEqual(AppDelegate.reportedTab(active: issue, recent: [issue, form], url: url), issue, "nothing before it")
        XCTAssertNil(AppDelegate.reportedTab(active: nil, recent: [page], url: url))
    }

    func testOnlyThisReposIssuesCount() {
        XCTAssertTrue(ReportLink.isIssuePage(URL(string: "https://github.com/ziadmyassine/luna-browser/issues")))
        XCTAssertTrue(ReportLink.isIssuePage(URL(string: "https://github.com/ziadmyassine/luna-browser/issues/238#top")))
        XCTAssertFalse(ReportLink.isIssuePage(URL(string: "https://github.com/ziadmyassine/luna-browser/pulls")))
        XCTAssertFalse(ReportLink.isIssuePage(URL(string: "https://github.com/someone/else/issues/1")))
        XCTAssertFalse(ReportLink.isIssuePage(nil))
    }

    // MARK: - The screenshot

    private var pasteboard: NSPasteboard!
    private var ran: [[String]] = []

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: .init("luna.report.\(UUID())"))
        ran = []
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    /// `screencapture` never runs: this stands in for it, and copies or not.
    private func screenshot(
        canRecord: Bool = true, copies: Bool, onScreen: [WKWebView] = [], during: (() async -> Void)? = nil
    ) -> BugScreenshot {
        BugScreenshot(pasteboard: pasteboard, canRecord: { canRecord }, onScreen: { onScreen }, run: { [self] tool, arguments in
            XCTAssertEqual(tool.path(), "/usr/sbin/screencapture")
            ran.append(arguments)
            await during?()
            if copies {
                pasteboard.clearContents()
                pasteboard.setData(Data("png".utf8), forType: .png)
            }
        })
    }

    private func page(width: CGFloat = 800, height: CGFloat = 600) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        webView.loadHTMLString("""
        <!doctype html><body style="margin:0;background:#fff">
        <input id=card autocomplete=cc-number value="4111111111111111">
        """, baseURL: URL(string: "https://example.com/"))
        for _ in 0 ..< 100 {
            if try await webView.evaluateJavaScript("!!document.getElementById('card')") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        return webView
    }

    func testAWindowShotCopiesThatWindow() async {
        let taken = await screenshot(copies: true).take(.window, window: 42, page: nil)
        XCTAssertEqual(taken, .copied)
        XCTAssertEqual(ran, [["-l", "42", "-c", "-o", "-x"]])
    }

    /// Every page on screen, not only the one in front: a window or an area
    /// can take in another window's page.
    func testAWindowShotHidesSecretFields() async throws {
        let (front, other) = try await (page(), page())
        let security = "getComputedStyle(card).webkitTextSecurity"
        var during: [String?] = []
        let taken = await screenshot(copies: true, onScreen: [other, front]) {
            for view in [front, other] { during.append(try? await view.evaluateJavaScript(security) as? String) }
        }.take(.window, window: 42, page: front)
        XCTAssertEqual(taken, .copied)
        XCTAssertEqual(during, ["disc", "disc"], "a card number was in the picture")
        for view in [front, other] {
            let after = try await view.evaluateJavaScript(security) as? String
            XCTAssertEqual(after, "none", "a field was not put back")
        }
    }

    /// What `onScreen` walks: every web view under a window's content.
    func testTheWebViewsInAWindowAreFound() {
        let content = NSView()
        let nested = NSView()
        let (first, second) = (WKWebView(), WKWebView())
        content.addSubview(first)
        content.addSubview(nested)
        nested.addSubview(second)
        XCTAssertEqual(BugScreenshot.webViews(in: content), [first, second])
    }

    /// Esc during the pick: nothing opens, and the clipboard keeps what it had.
    func testEscInAnAreaPickCancels() async {
        pasteboard.clearContents()
        pasteboard.setString("keep", forType: .string)
        let count = pasteboard.changeCount
        let taken = await screenshot(copies: false).take(.area, window: 42, page: nil)
        XCTAssertEqual(taken, .cancelled)
        XCTAssertEqual(ran, [["-i", "-c", "-x"]])
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
        XCTAssertEqual(pasteboard.changeCount, count)
    }

    func testAnAreaThatCopiesIsCopied() async {
        let taken = await screenshot(copies: true).take(.area, window: 42, page: nil)
        XCTAssertEqual(taken, .copied)
    }

    func testAWindowShotThatCopiesNothingIsNothing() async {
        let taken = await screenshot(copies: false).take(.window, window: 42, page: nil)
        XCTAssertEqual(taken, .nothing)
    }

    func testWithoutScreenRecordingNothingRuns() async {
        let count = pasteboard.changeCount
        for shot in [BugShot.window, .area] {
            let taken = await screenshot(canRecord: false, copies: true).take(shot, window: 42, page: nil)
            XCTAssertEqual(taken, .needsPermission)
        }
        XCTAssertEqual(ran, [])
        XCTAssertEqual(pasteboard.changeCount, count)
    }

    func testPageOnlyCopiesAPictureAtMost1600Wide() async throws {
        let webView = try await page(width: 2000, height: 500)
        let taken = await screenshot(copies: false).take(.page, window: 42, page: webView)
        XCTAssertEqual(taken, .copied)
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertEqual(NSBitmapImageRep(data: png)?.pixelsWide, 1600)
        XCTAssertEqual(ran, [])
    }

    func testNoPageAndNoScreenshotTakeNothing() async {
        let count = pasteboard.changeCount
        for shot in [BugShot.page, .none] {
            let taken = await screenshot(copies: true).take(shot, window: 42, page: nil)
            XCTAssertEqual(taken, .nothing)
        }
        XCTAssertEqual(ran, [])
        XCTAssertEqual(pasteboard.changeCount, count)
    }
}
