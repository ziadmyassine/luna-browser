//
//  ControlActivityTests.swift
//  LunaTests
//
//  The activity pill and its list: calls in words, the pill in the page's
//  bottom trailing corner, and one row per call in the list.
//

import AppKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class ControlActivityTests: XCTestCase {

    func testCallsAreSaidInWords() throws {
        let url = try XCTUnwrap(URL(string: "https://www.developer.apple.com/account"))
        XCTAssertEqual(ControlActivity.title(of: .navigate(.url(url))), "Go to developer.apple.com")
        XCTAssertEqual(ControlActivity.title(of: .openTab(url)), "Open developer.apple.com")
        XCTAssertEqual(ControlActivity.title(of: .type("hello", ref: "e2")), "Type 5 characters")
        XCTAssertFalse(ControlActivity.title(of: .click(.ref("e12"), clickCount: 1)).contains("e12"), "a ref reached the words")
        XCTAssertEqual(ControlActivity.state(decision: "declined", outcome: "error"), .declined)
        XCTAssertEqual(ControlActivity.state(decision: "allowed", outcome: "error"), .failed)
        XCTAssertEqual(ControlActivity.state(decision: "approved", outcome: "ok"), .done)
    }

    func testThePillStandsInTheBottomTrailingCornerAndOpensTheList() throws {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        var opened = false
        surface.showActivity(ControlActivity.entry(for: .listTabs, client: "Claude Code", appID: nil)) { _ in opened = true }
        surface.layoutSubtreeIfNeeded()
        let pill = try XCTUnwrap(surface.activityPill)
        let gap = Tokens.Metric.chromeGapWide
        XCTAssertEqual(pill.frame.maxX, surface.bounds.maxX - gap, accuracy: 1, "the pill is not in the trailing corner")
        XCTAssertEqual(pill.frame.maxY, surface.bounds.maxY - gap, accuracy: 1, "the pill is not at the foot")
        // The layer counts down from the top; a view with no superview is
        // asked in window coordinates, which count up.
        let centre = NSPoint(x: pill.frame.midX, y: surface.bounds.height - pill.frame.midY)
        XCTAssertTrue(surface.hitTest(centre) === pill, "the pill does not take its own click")
        pill.performClick(nil)
        XCTAssertTrue(opened, "the pill did not open the list")

        surface.showActivity(nil) { _ in }
        XCTAssertNil(surface.activityPill)
    }

    func testTheListHasARowPerCallNewestFirst() {
        let panel = ControlActivityPanel(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        var done = ControlActivity.entry(for: .pageText, client: "Claude Code", appID: nil)
        done.state = .done
        done.site = "apple.com"
        let running = ControlActivity.entry(for: .listTabs, client: "Claude Code", appID: nil)
        panel.setEntries([running, done])
        XCTAssertEqual(panel.shownEntries.map(\.id), [running.id, done.id])
        XCTAssertTrue(ControlActivityRow.detail(of: running).contains("Running"))
        XCTAssertTrue(ControlActivityRow.detail(of: done).hasPrefix("apple.com"))
    }
}
