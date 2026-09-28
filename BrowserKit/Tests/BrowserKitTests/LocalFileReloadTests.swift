import AppKit
import WebKit
import XCTest
@testable import BrowserKit

/// A local HTML file shows what is on disk after a reload, including in a tab
/// that woke from its saved state.
@MainActor
final class LocalFileReloadTests: XCTestCase {

    private var folder: URL!
    private var window: NSWindow?

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "luna-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        window = nil
    }

    func testAReloadReadsTheFileAgainInAWokenTab() async throws {
        let page = try write("v1")
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        controller.load(page)
        var shown = try await version(in: controller)
        XCTAssertEqual(shown, "v1")

        controller.hibernate()
        try write("v2")
        controller.activate()
        shown = try await version(in: controller)
        XCTAssertEqual(shown, "v2", "the woken tab showed an old copy")

        try write("v3")
        controller.reload()
        shown = try await version(in: controller)
        XCTAssertEqual(shown, "v3", "a reload showed an old copy")
    }

    /// A YAML file is shown as text Luna read itself, which a plain WebKit
    /// reload would show again unchanged.
    func testAReloadReadsATextFileAgain() async throws {
        let file = folder.appending(path: "config.yaml")
        try "version: one".write(to: file, atomically: true, encoding: .utf8)
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        controller.load(file)
        var text = try await bodyText(in: controller)
        XCTAssertEqual(text, "version: one")

        try "version: two".write(to: file, atomically: true, encoding: .utf8)
        controller.reload()
        text = try await bodyText(in: controller)
        XCTAssertEqual(text, "version: two", "the reload showed the text as it was first read")
    }

    func testOnlyPagesOnThisMacSkipTheCache() {
        for local in ["file:///tmp/a.html", "http://localhost:3000/", "http://127.0.0.1:8000/x", "http://app.localhost/",
                      "https://shop.test/", "http://[::1]:8080/"] {
            XCTAssertTrue(NavigationPolicy.isLocalDevelopment(URL(string: local)!), local)
        }
        for remote in ["https://example.com/", "https://localhost.example.com/", "https://test.com/"] {
            XCTAssertFalse(NavigationPolicy.isLocalDevelopment(URL(string: remote)!), remote)
        }
    }

    private func bodyText(in controller: TabController) async throws -> String? {
        let view = try XCTUnwrap(controller.webView)
        if view.window == nil { show(view) }
        try await Task.sleep(for: .milliseconds(200))
        for _ in 0..<50 where view.isLoading { try await Task.sleep(for: .milliseconds(100)) }
        let text = try await view.evaluateJavaScript("document.body.innerText") as? String
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func write(_ version: String) throws -> URL {
        let page = folder.appending(path: "index.html")
        try "<html><head><link rel=stylesheet href=style.css></head><body data-v='\(version)'></body></html>"
            .write(to: page, atomically: true, encoding: .utf8)
        try "body { --v: '\(version)'; }".write(to: folder.appending(path: "style.css"), atomically: true, encoding: .utf8)
        return page
    }

    /// The page's and its stylesheet's versions, which must agree.
    private func version(in controller: TabController) async throws -> String? {
        let view = try XCTUnwrap(controller.webView)
        if view.window == nil { show(view) }
        try await Task.sleep(for: .milliseconds(200))
        for _ in 0..<50 where view.isLoading { try await Task.sleep(for: .milliseconds(100)) }
        let result = try await view.evaluateJavaScript(
            "[document.body?.dataset.v, getComputedStyle(document.body).getPropertyValue('--v').trim().replace(/['\"]/g, '')].join(' ')"
        ) as? String
        guard let parts = result?.split(separator: " ").map(String.init), parts.count == 2 else { return result }
        XCTAssertEqual(parts[0], parts[1], "the page and its stylesheet disagree: \(result ?? "")")
        return parts[0]
    }

    private func show(_ view: WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false
        )
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        self.window = window
    }
}
