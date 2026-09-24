//
//  ControlStageTests.swift
//  LunaTests
//
//  Trusted input through the whole service: a click on an agent's tab the
//  user is not looking at reaches the page as a person's, the tab the user
//  is looking at is refused, and nothing of the user's moves. The stage on
//  its own is `BrowserKit/Tests/ControlStageTests`; this is the wiring.
//
//  Run with the user away: it drives a real session in the host app.
//

import AppKit
import BrowserKit
import LunaControl
import WebKit
import XCTest
@testable import Luna

@MainActor
final class ControlStageTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private let client = ControlClient(rawName: "example-agent")
    /// A button that counts only trusted clicks.
    private let page = URL(string: "data:text/html," + """
    <button style="width:200px;height:80px" onclick="if(event.isTrusted)document.title='trusted'">Go</button>
    """.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "luna-control-tests-\(UUID().uuidString)")
        defaults.set(ControlMode.allowAll.rawValue, forKey: ControlService.modeKey)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService() async throws -> (ControlService, BrowserSession) {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let session = try await BrowserSession.restored(store: store)
        let service = ControlService(session: session, defaults: defaults, auditURL: directory.appending(path: "a.jsonl"))
        return (service, session)
    }

    private func text(_ result: ControlResult) -> String {
        result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    func testTrustedClickOnAgentTab() async throws {
        let (service, session) = try await makeService()
        _ = await service.perform(ControlCall(.openTab(page)), client)
        let id = try XCTUnwrap(session.allTabs(includeArchived: false).first { $0.url.scheme == "data" }?.id)
        let webView = try XCTUnwrap(session.controller(for: id)?.webView)
        XCTAssertNil(webView.window, "an agent's new tab should not be on screen")

        let result = await service.perform(ControlCall(.click(.point(x: 100, y: 40), clickCount: 1)), client)
        XCTAssertFalse(result.isError, text(result))
        XCTAssertTrue(text(result).contains("trusted: true"), text(result))
        XCTAssertEqual(webView.title, "trusted")
        XCTAssertNil(webView.window, "the stage kept the tab")
    }

    func testUserViewingTabRefusesInput() async throws {
        let (service, session) = try await makeService()
        _ = await service.perform(ControlCall(.openTab(page)), client)
        let id = try XCTUnwrap(session.allTabs(includeArchived: false).first { $0.url.scheme == "data" }?.id)
        session.activateTab(id)

        let result = await service.perform(ControlCall(.click(.point(x: 100, y: 40), clickCount: 1)), client)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(text(result).contains("taken over"), text(result))
        XCTAssertNotEqual(session.controller(for: id)?.webView?.title, "trusted")
    }

    func testNoFocusOrWindowMoves() async throws {
        let (service, _) = try await makeService()
        let keyWindow = NSApp.keyWindow
        let firstResponder = keyWindow?.firstResponder
        let active = NSApp.isActive
        let pointer = NSEvent.mouseLocation
        var frames: [Int: NSRect] = [:]
        for window in NSApp.windows where window.isVisible { frames[window.windowNumber] = window.frame }

        _ = await service.perform(ControlCall(.openTab(page)), client)
        _ = await service.perform(ControlCall(.click(.point(x: 100, y: 40), clickCount: 1)), client)
        // Cmd+W reaches the page, never the menu that would close the user's tab.
        _ = await service.perform(ControlCall(.key("cmd+a cmd+w")), client)

        XCTAssertEqual(NSApp.keyWindow, keyWindow)
        XCTAssertTrue(NSApp.keyWindow?.firstResponder === firstResponder)
        XCTAssertEqual(NSApp.isActive, active)
        XCTAssertEqual(NSEvent.mouseLocation, pointer)
        for window in NSApp.windows where frames[window.windowNumber] != nil {
            XCTAssertEqual(window.frame, frames[window.windowNumber], "a window of the user's moved")
        }
        XCTAssertFalse(NSApp.windows.contains { $0 is ControlStageWindow && $0.isVisible }, "a stage was left up")
    }
}
