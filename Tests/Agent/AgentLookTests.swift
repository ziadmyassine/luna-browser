//
//  AgentLookTests.swift
//  LunaTests
//
//  How Astro's work reads: the agent's Markdown set as type, a run of steps
//  gathered into one card, the thinking line only while there is nothing
//  else to show, and the tiles an agent puts on its tabs.
//

import AppKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class AgentLookTests: XCTestCase {

    func testMarkdownIsSetAsType() {
        let text = AgentMarkdown.render("## Flights\nTwo options:\n\n1. **SAS** first\n2. TAP\n\n- direct").string
        XCTAssertFalse(text.contains("##"), "a heading's hashes are not shown")
        XCTAssertFalse(text.contains("**"), "bold is bold, not asterisks")
        XCTAssertTrue(text.contains("1.\tSAS first"))
        XCTAssertTrue(text.contains("•\tdirect"))
        let heading = AgentMarkdown.render("## Flights").attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(heading?.pointSize ?? 0, Tokens.TypeScale.agentBody.pointSize)
    }

    func testStepsInARowAreOneCard() {
        let user = UUID()
        let blocks = AgentTranscriptView.blocks([
            .user(id: user, text: "go"),
            .step(id: "a", title: "Open sas.dk", symbol: "plus.square", state: .done),
            .step(id: "b", title: "Read the page", symbol: "doc.text", state: .running),
            .text(id: UUID(), text: "Found it.", writing: false),
            .step(id: "c", title: "Click", symbol: "cursorarrow.click", state: .running)
        ])
        XCTAssertEqual(blocks.count, 4)
        guard case let .steps(id, steps) = blocks[1] else { return XCTFail("no card") }
        XCTAssertEqual(id, "steps-a", "the card keeps its first step's id, so it is updated in place")
        XCTAssertEqual(steps.map(\.id), ["a", "b"])
    }

    func testThinkingShowsOnlyWhenNothingElseDoes() {
        let task = AgentTask(id: UUID(), prompt: "x")
        task.beginTurn()
        XCTAssertEqual(AgentThinkingLine.words(for: task), "Getting ready…")
        task.apply(.thinking)
        XCTAssertEqual(AgentThinkingLine.words(for: task), "Thinking…")
        task.apply(.toolStarted(id: "t", name: "mcp__luna__read_page", input: [:]))
        XCTAssertNil(AgentThinkingLine.words(for: task), "the step's own spinner says it")
        task.apply(.finished(failed: false, message: nil))
        XCTAssertNil(AgentThinkingLine.words(for: task))
    }

    func testAstroWavesWhileItAsksTheUser() {
        let task = AgentTask(id: UUID(), prompt: "x")
        task.beginTurn()
        task.apply(.toolStarted(id: "q", name: "mcp__luna__ask_user", input: ["question": "Which nights?", "options": ["a", "b"]]))
        XCTAssertEqual(AgentPanelView.mood(for: task), .waving)
    }

    func testAFolderIconIsAnEmojiOrASymbol() {
        XCTAssertEqual(ControlService.folderIcon("✈️", title: "x", astro: false), "✈️")
        XCTAssertEqual(ControlService.folderIcon("airplane", title: "x", astro: false), "airplane")
        XCTAssertNil(ControlService.folderIcon("not a symbol", title: "x", astro: false))
        XCTAssertNotNil(ControlService.folderIcon(nil, title: "Running shoes", astro: true), "Astro's folder guesses from its name")
        XCTAssertNil(ControlService.folderIcon(nil, title: "Running shoes", astro: false), "another app's folder keeps its face")
    }

    func testTabTilesAndTheIcon() {
        XCTAssertNotNil(TabTile.image(symbol: "airplane", colour: "teal"))
        XCTAssertNil(TabTile.image(symbol: "airplane", colour: "beige"))
        XCTAssertNil(TabTile.image(symbol: "no.such.symbol.anywhere", colour: "teal"))
        XCTAssertEqual(Set(ControlCall.tabColours.compactMap(TabTile.colour(named:)).map(\.description)).count,
                       ControlCall.tabColours.count, "every colour an agent may name is one Luna draws")
        XCTAssertFalse(AgentGlyph.image(pointSize: 16).isTemplate, "Astro is in its own colours")
        XCTAssertTrue(ControlFace(appID: ControlFace.astro).isAstro)
    }
}
