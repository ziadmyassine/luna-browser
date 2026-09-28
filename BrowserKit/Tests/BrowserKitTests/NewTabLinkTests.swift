import AppKit
import BrowserKit
import WebKit
import XCTest

/// A ⌘-clicked link is a new tab behind this one; a plain click still goes.
@MainActor
final class NewTabLinkTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws { window = nil }

    func testACommandClickedLinkOpensInABackgroundTab() async throws {
        let (controller, view, host) = try await page()
        click(view, modifiers: .command)
        for _ in 0..<50 where host.opened.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(host.opened.first?.url.absoluteString, "https://example.invalid/next")
        XCTAssertEqual(host.opened.first?.inBackground, true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(view.url?.absoluteString, "https://example.invalid/", "the page followed the ⌘-clicked link")
        withExtendedLifetime(controller) {}
    }

    func testCommandShiftBringsTheNewTabForward() async throws {
        let (controller, view, host) = try await page()
        click(view, modifiers: [.command, .shift])
        for _ in 0..<50 where host.opened.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(host.opened.first?.inBackground, false)
        withExtendedLifetime(controller) {}
    }

    func testAPlainClickStillFollowsTheLink() async throws {
        // A link on the same page, which needs no network to arrive.
        let (controller, view, host) = try await page(href: "#next")
        click(view, modifiers: [])
        for _ in 0..<50 where view.url?.fragment != "next" { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(view.url?.fragment, "next")
        XCTAssertTrue(host.opened.isEmpty)
        withExtendedLifetime(controller) {}
    }

    private func page(href: String = "/next") async throws -> (TabController, WKWebView, Host) {
        let host = Host()
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
        let view = try XCTUnwrap(controller.webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false
        )
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        self.window = window
        view.loadHTMLString(
            "<body style='margin:0'><a href='\(href)' style='display:block;width:100vw;height:100vh'>Next</a></body>",
            baseURL: URL(string: "https://example.invalid/")
        )
        for _ in 0..<50 where try await view.evaluateJavaScript("document.readyState") as? String != "complete" {
            try await Task.sleep(for: .milliseconds(100))
        }
        return (controller, view, host)
    }

    private func click(_ view: WKWebView, modifiers: NSEvent.ModifierFlags) {
        guard let window = view.window else { return XCTFail("the view is in no window") }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return XCTFail("no event") }
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

    private final class Host: TabControllerDelegate {
        var opened: [(url: URL, inBackground: Bool)] = []

        func tabController(_ controller: TabController, wantsToOpenInNewTab url: URL, inBackground: Bool) {
            opened.append((url, inBackground))
        }

        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) { download.cancel() }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
