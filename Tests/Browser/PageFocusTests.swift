//
//  PageFocusTests.swift
//  LunaTests
//
//  A page cannot take the keyboard from a field in Luna's chrome — ⌘T's bar
//  went dead when the page behind it finished loading and focused one of its
//  own inputs. Luna's own hand-over still works. The window is off screen.
//

import AppKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class PageFocusTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    private func page() -> (NSTextField, LunaWebView, NSWindow) {
        let window = LunaWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = root
        let web = LunaWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 360), configuration: WKWebViewConfiguration())
        let field = NSTextField(frame: NSRect(x: 10, y: 365, width: 300, height: 24))
        root.addSubview(web)
        root.addSubview(field)
        self.window = window
        return (field, web, window)
    }

    func testAPageCannotTakeTheKeyboardFromAChromeField() {
        let (field, web, window) = page()
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(LunaWebView.chromeFieldIsTyping(in: window))

        XCTAssertFalse(window.makeFirstResponder(web), "the page took the keyboard from the field")
        XCTAssertTrue(LunaWebView.chromeFieldIsTyping(in: window), "the field lost the keyboard")
    }

    func testLunaCanHandTheKeyboardToThePage() {
        let (field, web, window) = page()
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(web.takeFocus())
        XCTAssertTrue(window.firstResponder === web)
    }

    /// With no chrome field typing, a page takes focus as it always has.
    func testAPageTakesTheKeyboardWhenNothingElseHasIt() {
        let (_, web, window) = page()
        XCTAssertTrue(window.makeFirstResponder(web))
    }
}
