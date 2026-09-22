//
//  TrafficLightReapplyTests.swift
//  LunaTests
//
//  `TrafficLightLayoutManager` owns the three buttons' origins *against* AppKit,
//  which puts them back at its own whenever it re-lays the titlebar. Where
//  `ChromeLayoutTests` asserts what the geometry is, this asserts that it is
//  re-applied — which is the half that breaks, because it breaks silently and
//  only sometimes.
//
//  The case here is the one that shipped: AppKit resets the buttons as the
//  window arrives on screen, without a resize and without touching the
//  titlebar's frame, so nothing the manager was listening to fired. Only the
//  zoom button was left behind, which is why it read as three lights that were
//  not quite in a row rather than as chrome in the wrong place.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class TrafficLightReapplyTests: XCTestCase {

    /// A window shaped like Luna's, so it has all three buttons to place.
    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    private func buttons(of window: NSWindow) -> [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    /// Move all three behind the manager's back, tell it the window appeared,
    /// and every one of them comes home — the zoom button included.
    func testTheWindowAppearingPutsEveryLightBack() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)

        for (index, button) in lights.enumerated() {
            button.setFrameOrigin(CGPoint(x: 9 + CGFloat(index) * 23, y: 9))
        }
        XCTAssertNotEqual(lights.map(\.frame.origin), placed, "the fixture did not move them")

        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        XCTAssertEqual(lights.map(\.frame.origin), placed, "a light was left where AppKit put it")
    }

    /// The same for a resize, which is the path that already worked — here so
    /// that the observer list cannot be trimmed back to nothing by accident.
    func testAResizePutsEveryLightBack() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)

        for button in lights { button.setFrameOrigin(CGPoint(x: 9, y: 9)) }
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)

        XCTAssertEqual(lights.map(\.frame.origin), placed)
    }
}
