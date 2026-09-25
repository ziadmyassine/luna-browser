//
//  TopBarLightsTests.swift
//  LunaTests
//
//  §4's bar stands its back button clear of the traffic lights whichever
//  state the window switched to it from.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class TopBarLightsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Rig {
        let controller: BrowserWindowController
        let host: ChromeHostView
        let bar: TopBarView
    }

    private func rig(from state: ChromeState) async throws -> Rig {
        let store = try BrowserStore(path: directory.appending(path: "\(UUID().uuidString).sqlite"))
        let session = try await BrowserSession.restored(store: store)
        let window = UUID()
        session.openWindow(window)
        let controller = BrowserWindowController()
        let host = ChromeHostView()
        let bar = TopBarView(session: session, windowID: window)
        host.install(sidebar: NSView(), topBar: bar)
        controller.setChrome(host)
        controller.setChromeStateWithoutAnimation(state)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return Rig(controller: controller, host: host, bar: bar)
    }

    private func switchToTopBar(_ rig: Rig, animated: Bool) {
        rig.host.setLayout(.topBar)
        if animated {
            rig.controller.setChromeState(.topBar)
        } else {
            rig.controller.setChromeStateWithoutAnimation(.topBar)
        }
        rig.controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func assertClear(_ rig: Rig, _ message: String, line: UInt = #line) throws {
        let root = try XCTUnwrap(rig.controller.window?.contentView)
        let lights = try XCTUnwrap(TrafficLightSpace.rect(in: root), "no lights showing", line: line)
        let nav = try XCTUnwrap(rig.bar.subviews.first { $0 is NavCluster })
        let navX = root.convert(nav.frame, from: rig.bar).minX
        XCTAssertGreaterThan(navX, lights.maxX, "the back button is under the lights: \(message)", line: line)
    }

    func testFromAShowingSidebar() async throws {
        for animated in [false, true] {
            let rig = try await rig(from: .sidebar(width: 280, edge: .leading))
            switchToTopBar(rig, animated: animated)
            try assertClear(rig, "from a showing sidebar, animated \(animated)")
        }
    }

    func testFromAHiddenSidebar() async throws {
        for animated in [false, true] {
            let rig = try await rig(from: .sidebarCollapsed(edge: .leading))
            switchToTopBar(rig, animated: animated)
            try assertClear(rig, "from a hidden sidebar, animated \(animated)")
        }
    }

    func testFromAPeek() async throws {
        for animated in [false, true] {
            let rig = try await rig(from: .sidebarCollapsed(edge: .leading))
            rig.controller.trafficLights?.isPeeking = true
            rig.controller.window?.contentView?.layoutSubtreeIfNeeded()
            switchToTopBar(rig, animated: animated)
            try assertClear(rig, "from a peek, animated \(animated)")
        }
    }
}
