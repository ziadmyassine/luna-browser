//
//  MouseBackForwardTests.swift
//  LunaTests
//
//  A mouse's thumb buttons over the page (#252): button 3 is Back and button
//  4 is Forward, answered on the way up. A real web view, because the history
//  they move through is WebKit's.
//

import CoreGraphics
import WebKit
import XCTest
@testable import Luna

@MainActor
final class MouseBackForwardTests: XCTestCase {

    private var window: NSWindow?
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["first", "second"] {
            try "<p>\(name)</p>".write(to: page(name), atomically: true, encoding: .utf8)
        }
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func page(_ name: String) -> URL { directory.appending(path: "\(name).html") }

    /// A page in an off-screen window that is never made key.
    private func webView() throws -> LunaWebView {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        self.window = window
        let web = LunaWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let root = try XCTUnwrap(window.contentView)
        web.frame = root.bounds
        root.addSubview(web)
        window.orderFrontRegardless()
        return web
    }

    private func open(_ name: String, in web: WKWebView) async throws {
        web.loadFileURL(page(name), allowingReadAccessTo: directory)
        try await settle(on: name, in: web)
    }

    private func settle(on name: String, in web: WKWebView) async throws {
        for _ in 0..<100 where web.isLoading || web.url?.lastPathComponent != "\(name).html" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(web.url?.lastPathComponent, "\(name).html")
    }

    /// `NSEvent` has no factory that takes a button number, so it is set on the
    /// `CGEvent` underneath.
    private func release(_ button: Int64) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: .zero, mouseButton: .center
        ))
        cg.setIntegerValueField(.mouseEventButtonNumber, value: button)
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(event.buttonNumber, Int(button))
        return event
    }

    func testThumbButtonsGoBackAndForward() async throws {
        let web = try webView()
        try await open("first", in: web)
        try await open("second", in: web)

        web.otherMouseUp(with: try release(3))
        try await settle(on: "first", in: web)

        web.otherMouseUp(with: try release(4))
        try await settle(on: "second", in: web)
    }

    /// The middle button is a link's new tab, not history.
    func testOtherButtonsLeaveHistoryAlone() async throws {
        let web = try webView()
        try await open("first", in: web)
        try await open("second", in: web)

        web.otherMouseUp(with: try release(2))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(web.url?.lastPathComponent, "second.html")
        XCTAssertTrue(web.canGoBack)
    }
}
