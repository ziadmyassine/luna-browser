//
//  BugReportTests.swift
//  LunaTests
//
//  What a bug report gathers: the commands run before it. Actions go to a
//  probe, never to Luna, and nothing takes focus.
//

import AppKit
import XCTest
@testable import Luna

@MainActor
private final class Probe: NSObject {
    @objc func newTab(_ sender: Any?) {}
    @objc func closeTab(_ sender: Any?) {}
    @objc func notACommand(_ sender: Any?) {}
}

@MainActor
final class BugReportTests: XCTestCase {

    private let probe = Probe()

    // MARK: - Recent commands

    func testTheAppIsLunas() {
        XCTAssertTrue(NSApp is LunaApplication)
    }

    func testASentCommandIsRemembered() {
        NSApp.sendAction(#selector(Probe.newTab(_:)), to: probe, from: nil)
        XCTAssertEqual(RecentCommands.titles.last, "New Tab")
    }

    func testAMenuClickIsRemembered() {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Close Tab", action: #selector(Probe.closeTab(_:)), keyEquivalent: "")
        item.target = probe
        menu.performActionForItem(at: 0)
        XCTAssertEqual(RecentCommands.titles.last, "Close Tab")
    }

    func testAKeyEquivalentIsRemembered() throws {
        NSApp.sendAction(#selector(Probe.closeTab(_:)), to: probe, from: nil)
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "New Tab", action: #selector(Probe.newTab(_:)), keyEquivalent: "t")
        item.target = probe
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17
        ))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(RecentCommands.titles.last, "New Tab")
    }

    func testOnlyTheLastTenAreKept() {
        for _ in 0..<12 { NSApp.sendAction(#selector(Probe.newTab(_:)), to: probe, from: nil) }
        XCTAssertEqual(RecentCommands.titles.count, 10)
    }

    func testAnythingElseIsNotRemembered() {
        let before = RecentCommands.titles
        NSApp.sendAction(#selector(Probe.notACommand(_:)), to: probe, from: nil)
        XCTAssertEqual(RecentCommands.titles, before)
    }
}
