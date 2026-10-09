//
//  AgentLookTests.swift
//  LunaTests
//
//  How Astro's work reads: the agent's Markdown set as type, a run of steps
//  gathered into one card, the thinking line only while there is nothing
//  else to show, and the icon an agent gives its folder.
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

    func testATableIsAGridNotAColumnOfWords() {
        let segments = AgentMarkdown.segments("""
        **Copenhagen → Sydney:**

        | Airline | Route | Price |
        |---|---|---|
        | THAI | 1 stop, Bangkok | DKK 9,846 |
        | Emirates | 1 stop, Dubai | DKK 10,288 |

        ```
        SK1525 07:40
        ```
        """)
        XCTAssertEqual(segments.count, 3)
        guard case let .table(table) = segments[1] else { return XCTFail("no table") }
        XCTAssertEqual(table.header.map(\.string), ["Airline", "Route", "Price"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[1].map(\.string), ["Emirates", "1 stop, Dubai", "DKK 10,288"])
        guard case let .code(code) = segments[2] else { return XCTFail("no code") }
        XCTAssertEqual(code, "SK1525 07:40")
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

    func testTheActivityLineSaysWhatAstroIsDoing() {
        let task = AgentTask(id: UUID(), prompt: "x")
        task.beginTurn()
        XCTAssertEqual(AgentThinkingLine.activity(for: task)?.words, "Getting ready…")
        task.apply(.thinking)
        XCTAssertEqual(AgentThinkingLine.activity(for: task)?.mood, .thinking)
        task.apply(.toolStarted(id: "t", name: "mcp__luna__read_page", input: [:]))
        XCTAssertEqual(AgentThinkingLine.activity(for: task)?.mood, .working)
        XCTAssertEqual(AgentPanelView.mood(for: task), .working, "the header's Astro does the same")
        task.apply(.toolFinished(id: "t", failed: false))
        task.apply(.text("Found it"))
        XCTAssertEqual(AgentThinkingLine.activity(for: task)?.mood, .writing)
        task.apply(.finished(failed: false, message: nil))
        XCTAssertNil(AgentThinkingLine.activity(for: task), "the turn is over")
    }

    func testNoNotchIsLitBesideADockedInspector() {
        let bounds = CGRect(x: 0, y: 0, width: 356, height: 600)
        let notches = (width: CGFloat(16), onLeading: true)
        let lit = AgentAura.outline(of: bounds, notches: notches)
        XCTAssertTrue(lit.contains(CGPoint(x: 8, y: 592)) && lit.contains(CGPoint(x: 8, y: 8)), "both notches at rest")
        let docked = AgentAura.outline(of: bounds, notches: notches, inspector: 0...240)
        XCTAssertTrue(docked.contains(CGPoint(x: 8, y: 592)), "the page still meets the panel at the top")
        XCTAssertFalse(docked.contains(CGPoint(x: 8, y: 8)), "an inspector docked along the bottom stands in that corner")
        XCTAssertFalse(docked.contains(CGPoint(x: 8, y: 300)), "and the strip between stays dark")
    }

    /// A link knows where it is under the pointer, and a click on it goes to
    /// Luna's own tab rather than the system's browser.
    func testALinkAnswersThePointerAndOpensInLuna() throws {
        let words = AgentTextView()
        words.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        words.text = AgentMarkdown.render("See [the hotel](https://example.com/hotel) for rooms.")
        let storage = try XCTUnwrap(words.textStorage)
        let start = (storage.string as NSString).range(of: "the hotel")
        let layout = try XCTUnwrap(words.layoutManager)
        let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: start, actualCharacterRange: nil),
                                       in: try XCTUnwrap(words.textContainer))
        XCTAssertEqual(words.link(at: NSPoint(x: rect.midX, y: rect.midY)), start)
        XCTAssertNil(words.link(at: NSPoint(x: 2, y: rect.midY)), "the words before it are not the link")
        XCTAssertGreaterThan(words.intrinsicContentSize.height, 10, "it sizes itself to its words")
        var opened: URL?
        words.onOpenLink = { opened = $0 }
        words.clicked(onLink: URL(string: "https://example.com/hotel") as Any, at: start.location)
        XCTAssertEqual(opened?.absoluteString, "https://example.com/hotel")
    }

    /// A client named after Luna is Luna Control, and wears Astro.
    func testLunaControlWearsAstro() throws {
        let face = try XCTUnwrap(ControlAppIcon.image(for: ControlFace.lunaControl))
        XCTAssertFalse(face.isTemplate, "Astro keeps its own colours")
        XCTAssertEqual(ControlClient.displayName(for: "local-agent-mode-luna"), "Luna Control")
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

    func testAstroIsInColour() {
        XCTAssertFalse(AgentGlyph.image(pointSize: 16).isTemplate, "Astro is in its own colours")
        XCTAssertTrue(ControlFace(appID: ControlFace.astro).isAstro)
    }
}
