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

    /// Puts all three back where AppKit would, without telling the manager.
    ///
    /// The silent reset is what the tests using this are about, and it stopped
    /// being the only kind: the manager now listens to the buttons themselves,
    /// so a plain `setFrameOrigin` is answered before a test can look. They
    /// stay muted afterwards, because turning the flag back on replays the move
    /// that happened while it was off — which would be the manager hearing it
    /// after all, one line later.
    private func displaceSilently(_ lights: [NSButton]) {
        for (index, button) in lights.enumerated() {
            button.postsFrameChangedNotifications = false
            button.setFrameOrigin(CGPoint(x: 9 + CGFloat(index) * 23, y: 9))
        }
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

        displaceSilently(lights)
        XCTAssertNotEqual(lights.map(\.frame.origin), placed, "the fixture did not move them")

        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )

        XCTAssertEqual(lights.map(\.frame.origin), placed, "a light was left where AppKit put it")
    }

    /// The one that actually shipped: nothing is posted at all, and the
    /// placement has to come back on its own.
    ///
    /// Moving them behind the manager's back and then waiting is the whole
    /// test — no notification, no chrome change, nothing to react to. Without
    /// `holdPlacement` they stay where they were put.
    func testThePlacementComesBackWithNoNotificationAtAll() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)

        displaceSilently(lights)
        let held = expectation(description: "the hold has had a few passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { held.fulfill() }
        wait(for: [held], timeout: 2)

        XCTAssertEqual(lights.map(\.frame.origin), placed, "nothing put them back")
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

        displaceSilently(lights)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)

        XCTAssertEqual(lights.map(\.frame.origin), placed)
    }

    /// The fullscreen one: a hover at the top of the screen slides AppKit's
    /// titlebar back down and it lays the three out again on the way past,
    /// leaving them at its own origins once it has gone.
    ///
    /// None of the three observers above hears it. There is no resize, no
    /// fullscreen transition, and the titlebar the manager watches does not
    /// move — in fullscreen it is the container around it that travels, and by
    /// then the lights are in neither. The buttons say so themselves, which is
    /// the whole of the warning, so this test moves one and posts nothing.
    func testAButtonThatMovesOnItsOwnComesStraightBack() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)

        // The button AppKit was measured leaving behind, and the origin it
        // leaves it at.
        let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        zoom.setFrameOrigin(CGPoint(x: 55, y: 9))

        XCTAssertEqual(lights.map(\.frame.origin), placed, "nobody answered the button's own notification")
    }

    /// A new title rebuilds AppKit's titlebar and takes the three back into
    /// it. In fullscreen that moves them out of the strip at the same origins,
    /// so no frame changes and the buttons' own notification is silent — the
    /// lights vanished on every tab switch. The title itself has to be heard,
    /// and at once: the assertion runs before the hold's first pass could.
    func testANewTitlePutsEveryLightBack() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)

        displaceSilently(lights)
        window.title = "Another page"

        XCTAssertEqual(lights.map(\.frame.origin), placed, "the title changed and nobody looked")
    }

    /// A theme change rebuilds the titlebar as a new title does; in
    /// fullscreen the lights were gone until the next tab switch.
    func testAThemeChangePutsEveryLightBack() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = buttons(of: window)
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        let placed = lights.map(\.frame.origin)
        let before = NSApp.appearance
        defer { NSApp.appearance = before }

        displaceSilently(lights)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)

        XCTAssertEqual(lights.map(\.frame.origin), placed, "the theme changed and nobody looked")
    }

    /// Fullscreen's lights stay in front of a panel opened after they were
    /// placed, as the titlebar's stand over everything in a window.
    func testTheLightsStayInFrontOfAPanelAddedLater() {
        let root = WindowRootView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let lights = NSView()
        root.addSubview(lights)
        root.frontmost = lights
        let panel = NSView()
        root.addSubview(panel, positioned: .above, relativeTo: nil)
        XCTAssertTrue(root.subviews.last === lights, "a pop-out opened over the lights")
        XCTAssertTrue(root.subviews.contains(panel))
    }

    /// The lights' width comes from their spacing, so a green button AppKit
    /// has put back in its own corner alone does not make them shorter — which
    /// slid §4's plate toward the lights on a click.
    func testTheLightsSpanIgnoresAZoomButtonResetOnItsOwn() {
        func button(at x: CGFloat) -> NSButton {
            let button = NSButton(frame: NSRect(x: x, y: 0, width: 14, height: 14))
            return button
        }
        let close = button(at: 18), minimize = button(at: 41), zoom = button(at: 64)
        XCTAssertEqual(TrafficLightSpace.span(close: close, minimize: minimize, zoom: zoom), 60)
        zoom.setFrameOrigin(NSPoint(x: 55, y: 0))
        XCTAssertEqual(TrafficLightSpace.span(close: close, minimize: minimize, zoom: zoom), 60)
    }
}
