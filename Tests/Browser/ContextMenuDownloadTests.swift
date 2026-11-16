//
//  ContextMenuDownloadTests.swift
//  LunaTests
//
//  The page's right-click menu downloads what it was opened on: each frame
//  reports the image, link and video under the pointer, and Luna's items in
//  place of WebKit's three download them through the tab's own downloads.
//

import AppKit
import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class ContextMenuDownloadTests: XCTestCase {

    private var host: Host!
    private var controller: TabController!

    override func setUp() async throws {
        host = Host()
        controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.delegate = host
        controller.activate()
    }

    override func tearDown() async throws {
        controller.hibernate()
        controller = nil
        host = nil
    }

    /// One red pixel.
    private static let pixel = "data:image/png;base64,"
        + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    private static let page = """
    <body><a id="link" href="/files/report.pdf"><img id="image" src="\(pixel)"></a>
    <video id="video" src="/media/clip.mp4"></video><p id="text">Words</p></body>
    """

    func testTheFrameReportsTheImageLinkAndVideoUnderThePointer() async throws {
        try await load(Self.page)
        try await rightClick("[document.getElementById('image'), document.getElementById('link')]")
        XCTAssertEqual(controller.contextMenuHit?.image?.absoluteString, Self.pixel)
        XCTAssertEqual(controller.contextMenuHit?.link?.absoluteString, "https://example.invalid/files/report.pdf")
        XCTAssertNil(controller.contextMenuHit?.media)

        try await rightClick("[document.getElementById('video')]")
        XCTAssertEqual(controller.contextMenuHit?.media?.absoluteString, "https://example.invalid/media/clip.mp4")
        XCTAssertNil(controller.contextMenuHit?.image, "the image right-clicked before was kept")
    }

    /// The page cannot post the report itself, nor have its own events count.
    func testThePageCannotSayWhatTheMenuDownloads() async throws {
        try await load(Self.page)
        let view = try XCTUnwrap(controller.webView)
        let reachable = try await view.evaluateJavaScript("!!(window.webkit && window.webkit.messageHandlers.lunaContextMenu)")
        XCTAssertEqual(reachable as? Bool, false, "the page can post the menu's hit")
        _ = try await view.evaluateJavaScript(
            "document.getElementById('image').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true })); 1"
        )
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(controller.contextMenuHit, "an event the page made was taken for a right-click")
    }

    func testDownloadImageStartsADownloadOfTheImage() async throws {
        try await load(Self.page)
        XCTAssertFalse(controller.downloadFromContextMenu(.image), "a download started with nothing right-clicked")
        try await rightClick("[document.getElementById('image')]")
        XCTAssertTrue(controller.downloadFromContextMenu(.image))
        for _ in 0..<50 where host.downloads.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(host.downloads.first?.originalRequest?.url?.absoluteString, Self.pixel)
    }

    /// Under WebKit's title and identifier; sent with nothing reported, WebKit's
    /// own item still runs, with its tag.
    func testTheMenusDownloadItemsAreLunasOwn() throws {
        let view = try XCTUnwrap(controller.webView as? LunaWebView, "pages are not LunaWebViews")
        let recorder = Recorder()
        let menu = NSMenu()
        for id in LunaWebView.downloadItems.keys.sorted() {
            let item = NSMenuItem(title: id, action: #selector(Recorder.download(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(id)
            item.target = recorder
            item.tag = 7
            menu.addItem(item)
        }

        view.willOpenMenu(menu, with: NSEvent())
        XCTAssertEqual(menu.items.count, 3)
        for item in menu.items {
            XCTAssertTrue(item.target === view, "\(item.title) is still WebKit's")
            XCTAssertEqual(item.title, item.identifier?.rawValue)
        }

        let item = try XCTUnwrap(menu.items.first)
        NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        XCTAssertEqual(recorder.tags, [7], "with nothing reported, WebKit's own item was not sent")
    }

    // MARK: - Helpers

    private func load(_ html: String) async throws {
        let view = try XCTUnwrap(controller.webView)
        view.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/page"))
        for _ in 0..<50 where view.isLoading || view.url == nil { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(100))
    }

    /// What the browser's own `contextmenu` event reports, with `path` as its
    /// composed path: a page's script cannot make a trusted one.
    private func rightClick(_ path: String) async throws {
        let view = try XCTUnwrap(controller.webView)
        let before = controller.contextMenuHit
        _ = try await view.callAsyncJavaScript(
            "window.__lunaContextMenuNote(\(path)); return 1", contentWorld: .defaultClient
        )
        for _ in 0..<30 where controller.contextMenuHit == before { try await Task.sleep(for: .milliseconds(50)) }
    }

    private final class Recorder: NSObject {
        var tags: [Int] = []
        @objc func download(_ sender: NSMenuItem) { tags.append(sender.tag) }
    }

    private final class Host: TabControllerDelegate {
        var downloads: [WKDownload] = []
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(_ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration)
            -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {
            downloads.append(download)
            download.cancel()
        }
        func tabController(_ controller: TabController, didFailWith error: Error) {}
    }
}
