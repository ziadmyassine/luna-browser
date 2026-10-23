//
//  CommandBarAppearanceTests.swift
//  LunaTests
//
//  §9.1's bar wears the appearance of the page under it, as the find field
//  and the toast do. In a dark window over a white site its glass went light
//  and its ink stayed white, and the address could not be read (#238).
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class CommandBarAppearanceTests: XCTestCase {

    private var directory: URL!
    private var session: BrowserSession!
    private var controller: BrowserWindowController!
    private var window: BrowserWindow!
    private var webView: WKWebView!

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
    }

    override func tearDown() async throws {
        window.close()
        controller.close()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The bar opened over a page painted `grey` (0...255, as `#rrggbb`
    /// with all three equal) in a window wearing `app`.
    private func openedBar(over grey: Int, in app: NSAppearance.Name) async throws -> CommandBarPanel {
        let host = try XCTUnwrap(controller.window)
        host.appearance = NSAppearance(named: app)
        webView.loadHTMLString(
            "<body style=\"margin:0;background:rgb(\(grey),\(grey),\(grey))\"><p>moon</p></body>",
            baseURL: URL(string: "https://example.invalid/page")
        )
        let page = try XCTUnwrap(session.activeTabID(inWindow: window.id).flatMap { session.controller(for: $0) })
        // The blank tab reports a colour of its own before this page lands, so
        // wait for this one's rather than for any.
        let painted = { page.state.pageBackground.map { abs($0.r * 255 - Double(grey)) < 2 } == true }
        for _ in 0 ..< 250 where !painted() { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(painted(), "the page never said what colour it is")

        let bar = CommandBarController(
            session: session,
            windowID: window.id,
            adaptive: AdaptiveHistory(store: session.store)
        )
        bar.present(.editCurrentURL, in: host)
        return try XCTUnwrap(bar.panel)
    }

    func testOverAWhitePageInADarkWindowTheBarIsLight() async throws {
        let panel = try await openedBar(over: 255, in: .darkAqua)
        XCTAssertEqual(panel.effectiveAppearance.name, .aqua, "white ink over a white page")
    }

    func testOverADarkPageInALightWindowTheBarIsDark() async throws {
        let panel = try await openedBar(over: 32, in: .aqua)
        XCTAssertEqual(panel.effectiveAppearance.name, .darkAqua, "dark ink over a dark page")
    }
}
