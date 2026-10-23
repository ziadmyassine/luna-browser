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
    private func screenshot(canRecord: Bool = true, copies: Bool, during: (() async -> Void)? = nil) -> BugScreenshot {
        BugScreenshot(pasteboard: pasteboard, canRecord: { canRecord }, run: { [self] tool, arguments in
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

    func testAWindowShotHidesSecretFields() async throws {
        let webView = try await page()
        let security = "getComputedStyle(card).webkitTextSecurity"
        var during: String?
        let taken = await screenshot(copies: true) {
            during = try? await webView.evaluateJavaScript(security) as? String
        }.take(.window, window: 42, page: webView)
        XCTAssertEqual(taken, .copied)
        XCTAssertEqual(during, "disc", "the card number was in the picture")
        let after = try await webView.evaluateJavaScript(security) as? String
        XCTAssertEqual(after, "none", "the field was not put back")
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
