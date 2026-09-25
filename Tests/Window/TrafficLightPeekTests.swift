//
//  TrafficLightPeekTests.swift
//  LunaTests
//
//  §7.2's peek and the traffic lights: they ride in and out with the sidebar
//  rather than appearing ahead of it. Parked, they stand where the sidebar
//  is parked, transparent and hidden; a peek brings them back from there, and
//  a closing one keeps them up until its fade has run.
//
//  The motion itself is the caller's transaction (`applyPeek`); this asserts
//  the ends it runs between, which is what the manager owns.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
final class TrafficLightPeekTests: XCTestCase {

    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    private func lights(of window: NSWindow) throws -> [NSButton] {
        let lights = [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        try XCTSkipIf(lights.count < 3, "this macOS gave the window fewer than three window buttons")
        return lights
    }

    /// A manager over a hidden sidebar that was 280 pt wide.
    private func parked() throws -> (TrafficLightLayoutManager, [NSButton], [CGPoint]) {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = try lights(of: window)
        let placed = lights.map(\.frame.origin)
        manager.parkedOffset = -280
        manager.apply(.sidebarCollapsed(edge: .leading))
        return (manager, lights, placed)
    }

    func testParkedLightsStandWhereTheSidebarIsParked() throws {
        let (_, lights, placed) = try parked()
        for (light, origin) in zip(lights, placed) {
            XCTAssertTrue(light.isHidden)
            XCTAssertEqual(light.alphaValue, 0, accuracy: 0.001)
            XCTAssertEqual(light.frame.minX, origin.x - 280, accuracy: 0.01, "the lights are not parked with the sidebar")
        }
    }

    func testAPeekBringsThemHome() throws {
        let (manager, lights, placed) = try parked()
        manager.isPeeking = true
        for (light, origin) in zip(lights, placed) {
            XCTAssertFalse(light.isHidden)
            XCTAssertEqual(light.alphaValue, 1, accuracy: 0.001)
            XCTAssertEqual(light.frame.origin, origin)
        }
    }

    /// Hidden at once, they left before the sidebar had.
    func testAClosingPeekHidesThemOnlyOnceItsFadeHasRun() throws {
        let (manager, lights, _) = try parked()
        manager.isPeeking = true
        let token = manager.beginLeaving()
        manager.isPeeking = false
        for light in lights {
            XCTAssertFalse(light.isHidden, "hidden before the fade ran")
            XCTAssertEqual(light.alphaValue, 0, accuracy: 0.001)
        }
        manager.peekDidLeave(token)
        for light in lights { XCTAssertTrue(light.isHidden, "a light at alpha 0 still takes clicks") }
    }

    /// The peek opened and closed again inside the first fade: the first
    /// fade's end is not the second's.
    func testAnEarlierFadesEndLeavesALaterOneRunning() throws {
        let (manager, lights, _) = try parked()
        manager.isPeeking = true
        let first = manager.beginLeaving()
        manager.isPeeking = false
        manager.isPeeking = true
        let second = manager.beginLeaving()
        manager.isPeeking = false
        manager.peekDidLeave(first)
        for light in lights { XCTAssertFalse(light.isHidden) }
        manager.peekDidLeave(second)
        for light in lights { XCTAssertTrue(light.isHidden) }
    }

    /// The first peek after `⌘S`: the park is set after the collapse, as
    /// `applyPeek` sets it, and the lights have to be there before it starts
    /// or they fade in at home while the sidebar slides in from the edge.
    func testSettingTheParkMovesLightsThatAreAlreadyAway() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = try lights(of: window)
        let placed = lights.map(\.frame.origin)
        manager.apply(.sidebarCollapsed(edge: .leading))
        manager.parkedOffset = -280
        for (light, origin) in zip(lights, placed) {
            XCTAssertEqual(light.frame.minX, origin.x - 280, accuracy: 0.01, "the first peek would start from home")
        }
    }

    /// `⌘S` hiding the sidebar: the lights stay up for the slide, and go once
    /// its transaction has ended.
    func testHidingTheSidebarKeepsTheLightsForItsSlide() throws {
        let window = window()
        let manager = TrafficLightLayoutManager(window: window)
        manager.apply(.sidebar(width: 280, edge: .leading))
        let lights = try lights(of: window)
        let placed = lights.map(\.frame.origin)
        manager.parkedOffset = -280
        let token = manager.beginLeaving()
        manager.apply(.sidebarCollapsed(edge: .leading))
        for (light, origin) in zip(lights, placed) {
            XCTAssertFalse(light.isHidden, "gone on the first frame of the slide")
            XCTAssertEqual(light.alphaValue, 0, accuracy: 0.001)
            XCTAssertEqual(light.frame.minX, origin.x - 280, accuracy: 0.01)
        }
        // Covered while they fade, so a press cannot reach a close button on
        // its way out.
        let group = lights.reduce(NSRect.null) { $0.union($1.frame) }
        XCTAssertTrue(manager.shield.superview === lights[0].superview)
        XCTAssertEqual(manager.shield.frame, group)
        XCTAssertTrue(lights[0].superview?.subviews.last === manager.shield, "the lights stand over their shield")
        XCTAssertTrue(manager.shield.hitTest(NSPoint(x: group.midX, y: group.midY)) === manager.shield,
                      "a close button nobody can see still takes the press")
        manager.peekDidLeave(token)
        for light in lights { XCTAssertTrue(light.isHidden) }
        XCTAssertNil(manager.shield.superview)
    }

    /// `⌘S` in the middle of the fade: the sidebar is back, and so are the
    /// lights, whatever the fade's end says when it lands.
    func testShowingTheSidebarMidFadeKeepsTheLights() throws {
        let (manager, lights, placed) = try parked()
        manager.isPeeking = true
        let token = manager.beginLeaving()
        manager.isPeeking = false
        manager.apply(.sidebar(width: 280, edge: .leading))
        manager.peekDidLeave(token)
        for (light, origin) in zip(lights, placed) {
            XCTAssertFalse(light.isHidden)
            XCTAssertEqual(light.alphaValue, 1, accuracy: 0.001)
            XCTAssertEqual(light.frame.origin, origin)
        }
    }
}
