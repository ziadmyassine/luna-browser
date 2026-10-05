//
//  AgentPanelTests.swift
//  LunaTests
//
//  The agent panel: a task built from Claude Code's events, the Command Bar
//  offering the agent only for a request, and the panel and its parts drawn
//  off screen in both appearances.
//

import AppKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class AgentPanelTests: XCTestCase {

    func testATaskReadsTheStream() {
        let task = AgentTask(id: UUID(), prompt: "find the best direct flight to Lisbon on my dates")
        XCTAssertEqual(task.title, "find the best direct flight…")
        task.beginTurn()
        task.apply(.textBegan)
        task.apply(.text("Let me "))
        task.apply(.text("look."))
        task.apply(.toolStarted(id: "n", name: "mcp__luna__name_task", input: ["title": "Lisbon trip"]))
        task.apply(.toolStarted(id: "t1", name: "mcp__luna__navigate", input: ["url": "https://sas.se"]))
        XCTAssertEqual(task.title, "Lisbon trip", "name_task names the task")
        XCTAssertEqual(task.status, .working)
        task.apply(.textEnded("Let me look."))
        task.apply(.toolFinished(id: "t1", failed: false))
        task.apply(.finished(failed: false, message: "Found it."))
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.items.count, 3, "the request, the words and one step — naming is not a step")
        guard case let .step(_, title, _, state) = task.items[2] else { return XCTFail("no step") }
        XCTAssertEqual(title, "Go to sas.se")
        XCTAssertEqual(state, .done)
    }

    func testStopHoldsAgainstLateOutput() {
        let task = AgentTask(id: UUID(), prompt: "x")
        task.beginTurn()
        task.apply(.toolStarted(id: "t1", name: "WebSearch", input: ["query": "lisbon"]))
        task.stopped()
        task.apply(.finished(failed: true, message: "interrupted"))
        XCTAssertEqual(task.status, .stopped, "the stopped turn's result does not turn into a failure")
        task.userWrote("try again")
        XCTAssertEqual(task.status, .starting)
    }

    func testASignInFailureSaysWhatToDo() {
        XCTAssertTrue(AgentSteps.explain("Failed to authenticate: OAuth session expired").contains("sign in"))
    }

    func testOnlyARequestAsksTheAgent() {
        XCTAssertTrue(AgentPrompt.reads("Catch me up on my pull requests"))
        XCTAssertTrue(AgentPrompt.reads("find cheap flights"))
        XCTAssertTrue(AgentPrompt.reads("is it raining in Paris?"))
        XCTAssertFalse(AgentPrompt.reads("running shoes"))
        XCTAssertFalse(AgentPrompt.reads("best pizza paris"))
        XCTAssertFalse(AgentPrompt.reads("github.com"))
    }

    func testTheAgentRowLeadsWhenItShows() {
        var sources = CommandBarSources()
        sources.offersAgent = true
        let asked = CommandBarRanking.merge(query: "Catch me up on my pull requests", sources: sources, limit: 8)
        XCTAssertEqual(asked.first?.source, .agent)
        XCTAssertEqual(asked.first?.action, .askAgent("Catch me up on my pull requests"))
        let searched = CommandBarRanking.merge(query: "running shoes", sources: sources, limit: 8)
        XCTAssertFalse(searched.contains { $0.source == .agent })
        sources.offersAgent = false
        XCTAssertFalse(CommandBarRanking.merge(query: "Catch me up on my pull requests", sources: sources, limit: 8)
            .contains { $0.source == .agent }, "not in a private window")
    }

    /// Off screen, in both appearances: the empty panel and one mid-task.
    func testThePanelDraws() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let panel = AgentPanelView()
            panel.appearance = NSAppearance(named: name)
            panel.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.agentPanelWidth, height: 640)
            panel.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(panel.bitmapImageRepForCachingDisplay(in: panel.bounds))
            panel.cacheDisplay(in: panel.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        }
        let rover = AgentRoverView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        for mood in [AgentRoverView.Mood.idle, .thinking, .working, .happy, .sad, .stopped] { rover.mood = mood }
        XCTAssertEqual(rover.mood, .stopped)
        XCTAssertTrue(AgentGlyph.image(pointSize: 14).isTemplate)
    }
}
