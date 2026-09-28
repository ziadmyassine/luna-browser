//
//  FullscreenTabCloseTests.swift
//  LunaTests
//
//  ⌘W on a fullscreen video. WebKit leaves fullscreen over several round trips,
//  and freeing the page partway through stopped the app on an assertion inside
//  WebKit; the closed tab's view has to outlive the exit, and then go.
//
//  Here rather than beside BrowserKit's teardown tests: `swift test` runs with
//  no app in front, and WebKit refuses fullscreen to a page it counts as hidden.
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class FullscreenTabCloseTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
    }

    func testATabClosedInFullscreenKeepsItsViewUntilFullscreenHasEnded() async throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        weak var weakView: WKWebView?
        do {
            let view = try XCTUnwrap(controller.webView)
            weakView = view
            show(view)
            view.loadHTMLString("<body><div id='player'>A player</div></body>", baseURL: URL(string: "https://example.invalid/"))
            try await Task.sleep(for: .milliseconds(100))
            for _ in 0..<100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
            _ = try await view.evaluateJavaScript("document.getElementById('player').requestFullscreen(); 1")
            for _ in 0..<100 where view.fullscreenState != .inFullscreen { try await Task.sleep(for: .milliseconds(50)) }
            try XCTSkipUnless(view.fullscreenState == .inFullscreen, "this machine would not go fullscreen")
        }

        controller.hibernate()
        XCTAssertNil(controller.webView)
        while let view = weakView, view.fullscreenState != .notInFullscreen {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(weakView, "the view was let go before WebKit had finished leaving fullscreen")
        for _ in 0..<150 where weakView != nil { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(weakView, "a closed tab's view was never let go")
    }

    private func show(_ view: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
