//
//  TopBarTabRenameTests.swift
//  LunaTests
//
//  §4's selected tab, end to end: its first click opens the Command Bar, and
//  the second click of a double-click puts the tab's name field up on that
//  same click — no fold to wait out, and the page not given the keyboard on
//  the way. Also the two glyphs at its trailing end, which stand on one line.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarTabRenameTests: XCTestCase {

    private var directory: URL!
    private var window: NSWindow?

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: "luna-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Fixture {
        let bar: CommandBarController
        let row: TopBarTabRow
        let window: NSWindow
    }

    /// A window with a top bar showing one selected tab, and a real Command
    /// Bar behind the tab's click.
    private func selectedTab() async throws -> Fixture {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let windowID = UUID()
        session.openWindow(windowID)
        let space = try XCTUnwrap(session.spaces.first).id
        let tab = Tab(spaceID: space, kind: .today, url: URL(string: "https://example.com/")!, title: "Example", order: 0)
        session.persistAll(session.list.insert(tab))
        session.activateTab(tab.id, inWindow: windowID)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // `close()` in `tearDown` would free it a second time otherwise.
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: window.contentLayoutRect)
        self.window = window
        let bar = CommandBarController(session: session, windowID: windowID, adaptive: AdaptiveHistory(store: store))
        session.setCommandBar({ mode, anchor in bar.present(mode, in: window, from: anchor) }, inWindow: windowID)
        let top = TopBarView(session: session, windowID: windowID)
        top.frame = NSRect(x: 0, y: 700, width: 1400, height: TopBarMetrics.barHeight)
        window.contentView?.addSubview(top)
        window.makeKeyAndOrderFront(nil)
        top.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(find(tab.id, in: top) as? TopBarTabRow)
        return Fixture(bar: bar, row: row, window: window)
    }

    private func press(_ type: NSEvent.EventType, count: Int, on row: TopBarTabRow, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: row.convert(NSPoint(x: row.bounds.width / 4, y: row.bounds.midY), to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: count,
            pressure: 1
        )
    }

    func testADoubleClickRenamesOnTheSecondClick() async throws {
        let tab = try await selectedTab()
        // The press tracks until the button comes up, so the up is queued first.
        tab.window.postEvent(try XCTUnwrap(press(.leftMouseUp, count: 1, on: tab.row, in: tab.window)), atStart: false)
        tab.row.mouseDown(with: try XCTUnwrap(press(.leftMouseDown, count: 1, on: tab.row, in: tab.window)))
        XCTAssertTrue(tab.bar.isPresented, "the first click is the address")
        try await Task.sleep(for: .seconds(0.1))

        tab.window.postEvent(try XCTUnwrap(press(.leftMouseUp, count: 2, on: tab.row, in: tab.window)), atStart: false)
        NSApp.sendEvent(try XCTUnwrap(press(.leftMouseDown, count: 2, on: tab.row, in: tab.window)))
        XCTAssertFalse(tab.bar.isPresented)
        XCTAssertFalse(tab.row.isHidden)
        XCTAssertFalse(tab.row.row.editor.isHidden, "the name field is not up on the second click")
        // And it stays up: nothing takes the keyboard back from it.
        try await Task.sleep(for: .seconds(0.3))
        XCTAssertFalse(tab.row.row.editor.isHidden)
        XCTAssertNotNil(tab.row.row.editor.currentEditor())
    }

    /// The sliders and the close glyph stand on one line by their ink, not by
    /// their boxes. To a device pixel: an edge's anti-aliasing puts a
    /// bounding box a pixel either way, which is what stood between the two
    /// before was 1.5.
    func testTheTwoGlyphsShareALine() async throws {
        let tab = try await selectedTab()
        tab.row.row.layoutSubtreeIfNeeded()
        let site = try XCTUnwrap(inkMidY(of: tab.row.row.siteButton))
        let close = try XCTUnwrap(inkMidY(of: tab.row.row.trailing))
        XCTAssertFalse(tab.row.row.siteButton.isHidden)
        XCTAssertEqual(site, close, accuracy: 0.5)
    }

    // MARK: - Helpers

    /// Where a view's ink is centred top to bottom, in points.
    private func inkMidY(of view: NSView) -> CGFloat? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let inked = (0..<rep.pixelsHigh).filter { y in
            (0..<rep.pixelsWide).contains { x in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 }
        }
        guard let top = inked.first, let bottom = inked.last else { return nil }
        return CGFloat(top + bottom + 1) / 2 * view.bounds.height / CGFloat(rep.pixelsHigh)
    }

    private func find(_ id: UUID, in root: NSView) -> NSView? {
        for sub in root.subviews {
            if sub.identifier?.rawValue == id.uuidString { return sub }
            if let found = find(id, in: sub) { return found }
        }
        return nil
    }
}
