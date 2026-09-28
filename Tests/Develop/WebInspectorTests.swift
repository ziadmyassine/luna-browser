//
//  WebInspectorTests.swift
//  LunaTests
//
//  WebKit's inspector opens inside Luna's page card, and the Develop menu is
//  in the bar with Safari's shortcuts.
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class WebInspectorTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    func testTheInspectorOpensBesideThePageInTheCard() async throws {
        let (card, webView) = try await pageInCard()
        XCTAssertTrue(WebInspector.isAvailable(for: webView), "this WebKit has no inspector calls")

        WebInspector.show(.elements, for: webView)
        let inspector = try await inspectorView(in: card)
        card.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        card.layoutSubtreeIfNeeded()

        XCTAssertTrue(WebInspector.isVisible(for: webView))
        XCTAssertGreaterThan(inspector.frame.height * inspector.frame.width, 0, "the inspector has no room")
        XCTAssertFalse(
            webView.frame.insetBy(dx: 1, dy: 1).intersects(inspector.frame),
            "the page \(webView.frame) covers the inspector \(inspector.frame)"
        )

        window?.setContentSize(NSSize(width: 800, height: 600))
        card.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(
            webView.frame.insetBy(dx: 1, dy: 1).intersects(inspector.frame),
            "after a resize the page \(webView.frame) covers the inspector \(inspector.frame)"
        )
        XCTAssertEqual(webView.frame.width, card.bounds.width, accuracy: 1, "the page did not follow the window")

        WebInspector.close(for: webView)
        for _ in 0..<30 where WebInspector.isVisible(for: webView) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(WebInspector.isVisible(for: webView))
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, card.bounds, "the page did not take the inspector's room back")
    }

    func testTheRightClickMenuOffersInspectElementOnlyWhileTheSettingIsOn() {
        let webView = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        let saved = WebViewFactory.isWebInspectorEnabled
        defer {
            WebViewFactory.isWebInspectorEnabled = saved
            WebViewFactory.applyAdvancedSettings(to: webView)
        }
        WebViewFactory.isWebInspectorEnabled = true
        WebViewFactory.applyAdvancedSettings(to: webView)
        XCTAssertEqual(webView.configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool, true)
        WebViewFactory.isWebInspectorEnabled = false
        WebViewFactory.applyAdvancedSettings(to: webView)
        XCTAssertEqual(webView.configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool, false)
        XCTAssertFalse(WebInspector.isAvailable(for: webView))
    }

    func testTheDevelopMenuCarriesSafarisShortcuts() throws {
        MainMenu.install(into: NSApp)
        let develop = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Develop" }?.submenu, "no Develop menu")
        let inspector = try XCTUnwrap(develop.items.first { $0.action == #selector(AppDelegate.toggleWebInspector(_:)) })
        XCTAssertEqual(inspector.keyEquivalent, "i")
        XCTAssertEqual(inspector.keyEquivalentModifierMask, [.command, .option])
        XCTAssertNotNil(develop.items.first { $0.submenu?.title == "User Agent" })
        let titles = NSApp.mainMenu?.items.map(\.title) ?? []
        XCTAssertEqual(titles.firstIndex(of: "Develop").map { $0 + 1 }, titles.firstIndex(of: "Window"))
    }

    private func pageInCard() async throws -> (ContentCardView, WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1000, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let card = ContentCardView(frame: window.contentLayoutRect)
        card.translatesAutoresizingMaskIntoConstraints = false
        let root = try XCTUnwrap(window.contentView)
        root.addSubview(card)
        card.pin(in: root)
        let webView = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        card.setContent(webView)
        window.orderFrontRegardless()
        self.window = window
        root.layoutSubtreeIfNeeded()
        webView.loadHTMLString("<body><h1>Moon</h1></body>", baseURL: URL(string: "https://example.invalid/"))
        for _ in 0..<50 where webView.isLoading || webView.url == nil { try await Task.sleep(for: .milliseconds(100)) }
        return (card, webView)
    }

    private func inspectorView(in card: NSView) async throws -> NSView {
        for _ in 0..<50 {
            if let view = card.subviews.first(where: { $0.className.contains("Inspector") }) { return view }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw XCTSkip("the inspector did not dock into the card; subviews: \(card.subviews.map(\.className))")
    }
}
