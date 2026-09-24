//
//  CommandBarDoubleClickTests.swift
//  LunaTests
//
//  §4's tab opens the Command Bar on its first click, so the second click of a
//  double-click lands on the bar. It has to fold the bar and hand the rename
//  back to the tab — `CommandBarAnchor.onDoubleClick`.
//

import AppKit
import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class CommandBarDoubleClickTests: XCTestCase {

    private var directory: URL?
    private var window: NSWindow?

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-doubleclick-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: try XCTUnwrap(directory), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        window?.close()
        window = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func click(_ count: Int, on view: NSView, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
            modifierFlags: [],
            // Zero, as a real event's may as well be for all the watch knows:
            // it is timed on its own clock, not on this.
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: count,
            pressure: 1
        )
    }

    /// Through `sendEvent`, which is where local monitors see an event.
    private func deliver(_ event: NSEvent) {
        NSApp.sendEvent(event)
    }

    private struct Fixture {
        let bar: CommandBarController
        let window: NSWindow
        let tab: NSView
        let renamed: XCTestExpectation
    }

    private func presented() async throws -> Fixture {
        let store = try BrowserStore(path: try XCTUnwrap(directory).appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let bar = CommandBarController(session: session, windowID: session.keyWindowID, adaptive: AdaptiveHistory(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // `close()` in `tearDown` would free it a second time otherwise.
        window.isReleasedWhenClosed = false
        self.window = window
        window.contentView = NSView(frame: window.contentLayoutRect)
        let tab = NSView(frame: NSRect(x: 300, y: 740, width: 140, height: 30))
        window.contentView?.addSubview(tab)
        let renamed = expectation(description: "the tab is handed its rename")
        let anchor = CommandBarAnchor(view: tab, onDoubleClick: { renamed.fulfill() })
        bar.present(.editCurrentURL, in: window, from: anchor)
        return Fixture(bar: bar, window: window, tab: tab, renamed: renamed)
    }

    /// The second click lands on the bar, is kept from it, and the rename
    /// follows once the bar has folded back into the tab.
    func testTheSecondClickFoldsTheBarAndRenames() async throws {
        let open = try await presented()
        deliver(try XCTUnwrap(click(2, on: open.tab, in: open.window)))
        await fulfillment(of: [open.renamed], timeout: 2)
        XCTAssertFalse(open.bar.isPresented)
        XCTAssertFalse(open.tab.isHidden)
    }

    /// A single click after the double-click interval is a click on the bar,
    /// not a rename.
    func testALaterClickIsTheBars() async throws {
        let open = try await presented()
        open.renamed.isInverted = true
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
        deliver(try XCTUnwrap(click(2, on: open.tab, in: open.window)))
        await fulfillment(of: [open.renamed], timeout: 0.5)
        XCTAssertTrue(open.bar.isPresented)
    }
}
