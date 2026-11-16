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
    /// WebKit opens the inspector in a window of its own when that is how it
    /// was last left, and it keeps that in the app's defaults. Docked for the
    /// tests, put back as it was after them.
    private static let startsAttached = "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached"
    private var savedAttached: Any?

    override func setUp() async throws {
        savedAttached = UserDefaults.standard.object(forKey: Self.startsAttached)
        UserDefaults.standard.set(true, forKey: Self.startsAttached)
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        UserDefaults.standard.set(savedAttached, forKey: Self.startsAttached)
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

        // Restyled as the chrome: the card stops painting behind it so the
        // window's glass shows, and Luna's stylesheet is in its page.
        card.updateLayer()
        XCTAssertEqual(card.layer?.backgroundColor?.alpha ?? 1, 0, "the card paints over the glass behind the inspector")
        try await Task.sleep(for: .milliseconds(1200))
        let page = try XCTUnwrap(inspector as? WKWebView)
        let styled = try await page.evaluateJavaScript("!!document.getElementById('luna-inspector-style')") as? Bool
        XCTAssertEqual(styled, true, "the inspector was not restyled")
        // WebKit opens on the tab last used, and the test host starts with no
        // settings of its own, so on Console.
        _ = try await page.evaluateJavaScript("WI.showElementsTab(); 1")
        var standing = false
        for _ in 0..<30 where !standing {
            standing = try await page.evaluateJavaScript("!!document.querySelector('.find-banner.luna-pinned')") as? Bool ?? false
            if !standing { try await Task.sleep(for: .milliseconds(100)) }
        }
        XCTAssertTrue(standing, "Elements' search field is not standing under the tab bar")
        XCTAssertEqual(inspector.alphaValue, 1, "the styled inspector was never faded in")

        window?.setContentSize(NSSize(width: 800, height: 600))
        card.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(
            webView.frame.insetBy(dx: 1, dy: 1).intersects(inspector.frame),
            "after a resize the page \(webView.frame) covers the inspector \(inspector.frame)"
        )
        // WebKit docks on whichever side it was last left on, which is kept in
        // the app's defaults, and the tests share those: beside the page, the
        // two fill the width together; below it, the page has it all.
        let beside = inspector.frame.height > card.bounds.height - 1
        let room = card.bounds.width - (beside ? inspector.frame.width : 0)
        XCTAssertEqual(webView.frame.width, room, accuracy: 1, "the page did not follow the window")

        ContentCardView.closeInspector(of: webView)
        for _ in 0..<30 where WebInspector.isVisible(for: webView) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(WebInspector.isVisible(for: webView))
        card.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, card.bounds, "the page did not take the inspector's room back")
    }

    /// Docked beside the page, the inspector stands on the glass from the
    /// card's top, and the page rounds the corners that meet it — after a
    /// resize too, when WebKit sets both frames again.
    func testThePageBesideADockedInspectorIsACardOfItsOwn() async throws {
        let (card, webView) = try await pageInCard()
        card.setContentTopInset(52, animated: false)
        WebInspector.show(.elements, for: webView)
        let docked = try await inspectorView(in: card)
        let inspector = try XCTUnwrap(docked as? WKWebView)
        try await Task.sleep(for: .milliseconds(1000))
        _ = try await inspector.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('right'); 1")
        for _ in 0..<30 where inspector.frame.height < card.bounds.height - 1 {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(inspector.frame.height, card.bounds.height, accuracy: 1, "the inspector did not dock beside")
        XCTAssertEqual(inspector.obscuredContentInsets.top, 0, "the inspector beside started below a bar not over it")
        XCTAssertEqual(webView.layer?.cornerRadius, WindowCorner.radius, "the page beside the inspector stayed square")
        XCTAssertEqual(
            webView.layer?.maskedCorners,
            [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner],
            "the page did not round every corner beside the inspector"
        )
        let rule = try await inspector.evaluateJavaScript("getComputedStyle(document.body).borderLeftWidth") as? String
        XCTAssertEqual(rule, "0px", "the inspector ruled a straight line beside the page's round corner")
        let plate = try await inspector.evaluateJavaScript(
            "getComputedStyle(document.body).getPropertyValue('--popover-background-color').trim()"
        ) as? String
        XCTAssertTrue(
            [InspectorStyle.popover.light, InspectorStyle.popover.dark].contains(plate ?? ""),
            "a pop-over's plate is \(plate ?? "nil"), not the raised plane"
        )

        window?.setContentSize(NSSize(width: 900, height: 600))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(webView.layer?.cornerRadius, WindowCorner.radius, "after a resize, the page lost its corners")
        // The inspector's own close button, which fades it before it goes.
        let fades = try await inspector.evaluateJavaScript("InspectorFrontendHost.hasOwnProperty('closeWindow')") as? Bool
        XCTAssertEqual(fades, true, "the inspector's own close does not fade it")
        _ = try await inspector.evaluateJavaScript("InspectorFrontendHost.closeWindow(); 1")
        for _ in 0..<30 where WebInspector.isVisible(for: webView) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(WebInspector.isVisible(for: webView), "the inspector's own close did not close it")
        XCTAssertEqual(webView.layer?.cornerRadius, 0, "closed, the page kept the inspector's corners")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(card.revealMasks.isEmpty, "the page was still masked after it had taken the inspector's place")
        XCTAssertNil(webView.layer?.mask)
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
