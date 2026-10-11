//
//  TestHostFocusTests.swift
//  LunaTests
//
//  The unit-test host shares the Mac with whoever is using it: it is never
//  the active app, and no window it orders in lands on a screen.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class TestHostFocusTests: XCTestCase {

    func testTheHostIsAnAccessoryAppThatNeverActivated() {
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertFalse(NSApp.isActive)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, getpid())
    }

    /// Every route a test or the app takes onto the screen, through a window
    /// placed squarely on the main one.
    func testNoWindowOfTheHostIsOnAScreen() {
        let windows = (0..<3).map { _ in
            NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
            )
        }
        windows.forEach { $0.isReleasedWhenClosed = false; $0.center() }
        windows[0].makeKeyAndOrderFront(nil)
        windows[1].orderFrontRegardless()
        NSWindowController(window: windows[2]).showWindow(nil)
        defer { windows.forEach { $0.close() } }

        XCTAssertTrue(windows.allSatisfy(\.isVisible))
        for window in NSApp.windows where window.isVisible && window.alphaValue > 0 {
            XCTAssertFalse(
                NSScreen.screens.contains { $0.frame.intersects(window.frame) },
                "\(type(of: window)) is on screen at \(window.frame)"
            )
        }
        XCTAssertFalse(NSApp.isActive)
    }
}
