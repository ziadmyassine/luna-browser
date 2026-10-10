//
//  ControlActivityTests.swift
//  LunaTests
//
//  The activity pills and their lists: calls in words, a pill per session
//  stacked up from the page's bottom trailing corner, and one row per call in
//  the list.
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
        var opened: String?
        surface.showActivity([shown("a")]) { agent, _ in opened = agent }
        surface.layoutSubtreeIfNeeded()
        let pill = try XCTUnwrap(surface.activityPills.first)
        let gap = Tokens.Metric.chromeGapWide
        XCTAssertEqual(pill.frame.maxX, surface.bounds.maxX - gap, accuracy: 1, "the pill is not in the trailing corner")
        XCTAssertEqual(pill.frame.maxY, surface.bounds.maxY - gap, accuracy: 1, "the pill is not at the foot")
        // The layer counts down from the top; a view with no superview is
        // asked in window coordinates, which count up.
        let centre = NSPoint(x: pill.frame.midX, y: surface.bounds.height - pill.frame.midY)
        XCTAssertTrue(surface.hitTest(centre) === pill, "the pill does not take its own click")
        XCTAssertEqual(pill.frame.height, Tokens.Agent.capsuleHeight, accuracy: 0.5, "the pill is not the capsule's height")
        XCTAssertGreaterThan(pill.frame.width, 150, "the call was squeezed out of the pill")
        XCTAssertTrue(pill.isWorking, "the pill has no spark while the agent works")
        pill.performClick(nil)
        XCTAssertEqual(opened, "a", "the pill did not open its session's list")

        surface.showActivity([]) { _, _ in }
        XCTAssertTrue(surface.activityPills.isEmpty)
    }

    /// Two sessions at work are two pills, the first to start lowest, and
    /// the upper one comes down when the lower one goes.
    func testTwoSessionsStandOneAboveTheOther() throws {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.showActivity([shown("a"), shown("b")]) { _, _ in }
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(surface.activityPills.compactMap(\.agent), ["a", "b"])
        let (lower, upper) = (surface.activityPills[0], surface.activityPills[1])
        XCTAssertEqual(lower.frame.maxY, surface.bounds.maxY - Tokens.Metric.chromeGapWide, accuracy: 1)
        XCTAssertEqual(lower.frame.minY - upper.frame.maxY, Tokens.Metric.chromeGap, accuracy: 1, "the pills overlap")

        surface.showActivity([shown("b")]) { _, _ in }
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.activityPills == [upper], "the upper pill was replaced rather than kept")
        if !Tokens.Motion.reduceMotion { try? RunLoop.main.run(until: Date() + Tokens.Motion.agentSheet.duration + 0.1) }
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(upper.frame.maxY, surface.bounds.maxY - Tokens.Metric.chromeGapWide, accuracy: 1, "it did not come down")
    }

    private func shown(_ agent: String) -> ControlActivity.Shown {
        ControlActivity.Shown(
            entry: ControlActivity.entry(for: .listTabs, agent: agent, client: "Claude Code", appID: nil),
            name: "Session \(agent)", working: true
        )
    }

    func testTheListHasARowPerCallNewestFirst() {
        let panel = ControlActivityPanel(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        var done = ControlActivity.entry(for: .pageText, agent: "a", client: "Claude Code", appID: nil)
        done.state = .done
        done.site = "apple.com"
        let running = ControlActivity.entry(for: .listTabs, agent: "a", client: "Claude Code", appID: nil)
        panel.setEntries([running, done])
        XCTAssertEqual(panel.shownEntries.map(\.id), [running.id, done.id])
        XCTAssertTrue(ControlActivityRow.detail(of: running).contains("Running"))
        XCTAssertTrue(ControlActivityRow.detail(of: done).hasPrefix("apple.com"))
    }
}

/// The agent's pointer: Astro's face, a ring in the agent's colour where it
/// clicks, and a pill beside it saying it is working.
@MainActor
final class ControlAgentPointerTests: XCTestCase {

    func testThePointerWearsTheAgentsColourAndAPillForItsName() throws {
        let pointer = ControlAgentPointer()
        let tint = Tokens.Agent.tint(forApp: "claude-code")
        pointer.configure(agent: "Claude Code", tint: tint)
        let sublayers = pointer.layer?.sublayers ?? []
        let ring = try XCTUnwrap(sublayers.compactMap { $0 as? CAShapeLayer }.first)
        XCTAssertEqual(ring.strokeColor, tint.cgColor, "the click's ring is not the agent's colour")
        XCTAssertTrue(sublayers.contains { $0.sublayers?.contains { $0.contents != nil } == true }, "the pointer does not show Astro")
        let badge = try XCTUnwrap(pointer.subviews.first, "the name has no tag")
        XCTAssertEqual(badge.layer?.cornerRadius ?? 0, badge.frame.height / 2, accuracy: 0.5, "the name tag is not a pill")
        XCTAssertLessThanOrEqual(badge.frame.maxX, pointer.frame.width, "the name tag runs out of the pointer")
        let label = try XCTUnwrap(badge.subviews.first as? NSTextField)
        XCTAssertEqual(label.stringValue, "Claude Code is working…")
        XCTAssertGreaterThan(badge.frame.minX, ControlAgentPointer.tip.x, "the pill is not beside Astro")
        XCTAssertEqual(badge.frame.midY, ControlAgentPointer.tip.y, accuracy: 0.5, "the pill is not centred on Astro")
    }

    func testTheTipStandsOnThePointAndAClickRipples() throws {
        let surface = ControlSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.point(at: NSPoint(x: 300, y: 200), client: "Claude Code", tint: .orange, clicks: true)
        let pointer = try XCTUnwrap(surface.subviews.first { $0 is ControlAgentPointer })
        XCTAssertEqual(pointer.frame.minX + ControlAgentPointer.tip.x, 300, accuracy: 0.5)
        XCTAssertEqual(pointer.frame.minY + ControlAgentPointer.tip.y, 200, accuracy: 0.5)
        if !Tokens.Motion.reduceMotion {
            let rippled = pointer.layer?.sublayers?.contains { $0.animation(forKey: "pulse") != nil } ?? false
            XCTAssertTrue(rippled, "the click did not ripple")
        }
    }
}
