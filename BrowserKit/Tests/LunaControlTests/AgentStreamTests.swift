import Foundation
@testable import LunaControl
import Testing

/// The agent panel's reading of Claude Code's stream-json output, from lines
/// shaped as a live run printed them, and the lines Luna writes back.
@Suite("Agent stream")
struct AgentStreamTests {

    @Test func theSessionStartsAndEnds() {
        #expect(AgentStream.events(in: #"{"type":"system","subtype":"init","session_id":"s1","model":"x"}"#)
            == [.started(session: "s1")])
        #expect(AgentStream.events(in: #"{"type":"result","subtype":"success","is_error":false,"result":"Done."}"#)
            == [.finished(failed: false, message: "Done.")])
        #expect(AgentStream.events(in: #"{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate"}"#)
            == [.finished(failed: true, message: "Failed to authenticate")])
    }

    @Test func textArrivesAsItIsWrittenAndThenWhole() {
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}}"#
        let whole = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello."}]}}"#
        #expect(AgentStream.events(in: start) == [.textBegan])
        #expect(AgentStream.events(in: delta) == [.text("Hel")])
        #expect(AgentStream.events(in: whole) == [.textEnded("Hello.")])
    }

    @Test func aToolCallAndItsResult() {
        let use = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","#
            + #""name":"mcp__luna__navigate","input":{"url":"https://sas.se"}}]}}"#
        let result = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true}]}}"#
        #expect(AgentStream.events(in: use) == [.toolStarted(id: "t1", name: "mcp__luna__navigate", input: ["url": "https://sas.se"])])
        #expect(AgentStream.events(in: result) == [.toolFinished(id: "t1", failed: true)])
        #expect(AgentStream.lunaTool("mcp__luna__navigate") == "navigate")
        #expect(AgentStream.lunaTool("WebSearch") == nil)
    }

    @Test func thinkingAndNoise() {
        let thinking = #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"thinking"}}}"#
        #expect(AgentStream.events(in: thinking) == [.thinking])
        #expect(AgentStream.events(in: #"{"type":"system","subtype":"status","status":"x"}"#).isEmpty)
        #expect(AgentStream.events(in: "not json").isEmpty)
    }

    @Test func whatLunaWrites() throws {
        let message = try #require(JSONValue.parse(Data(AgentStream.userMessage("Also a window seat", now: true).utf8)))
        #expect(message["type"]?.string == "user")
        #expect(message["message"]?["content"]?.string == "Also a window seat")
        #expect(message["priority"]?.string == "now")
        let stop = try #require(JSONValue.parse(Data(AgentStream.interrupt(id: "r1").utf8)))
        #expect(stop["request"]?["subtype"]?.string == "interrupt")
        #expect(AgentStream.userMessage("x", now: false).hasSuffix("\n"))
    }

    @Test func nameTaskIsATool() throws {
        let call = try #require(ControlCall.parse(tool: "name_task", arguments: ["title": "  Lisbon trip.\n"]))
        #expect(try call.get().command == .nameTask("Lisbon trip"))
        #expect(!ControlCommand.nameTask("x").acts)
        let iconed = try #require(ControlCall.parse(tool: "name_task", arguments: ["title": "Lisbon trip", "icon": " ✈️ "]))
        #expect(try iconed.get().command == .nameTask("Lisbon trip", icon: "✈️"))
    }
}

/// `label_tab`: a tab's name, from the agent.
@Suite("Label tab")
struct LabelTabTests {

    @Test func aName() throws {
        let call = try #require(ControlCall.parse(tool: "label_tab", arguments: ["tabId": 3, "title": " Flights\n"]))
        #expect(try call.get().command == .labelTab(title: "Flights"))
        #expect(!ControlCommand.labelTab(title: "x").acts)
    }

    @Test func itNeedsATabAndAName() {
        #expect((try? ControlCall.parse(tool: "label_tab", arguments: ["title": "Flights"])?.get()) == nil)
        #expect((try? ControlCall.parse(tool: "label_tab", arguments: ["tabId": 3])?.get()) == nil)
    }

    @Test func agentsAreToldToNameThings() {
        #expect(ControlSession.instructions.contains("name_task"))
        #expect(ControlSession.instructions.contains("label_tab"))
        #expect(ControlTools.all.contains { $0["name"]?.string == "label_tab" })
    }
}

/// `show_document`: a write-up the agent hands the user as a Markdown tab.
@Suite("Show document")
struct ShowDocumentTests {

    @Test func aTitleAndTheDocument() throws {
        let call = try #require(ControlCall.parse(tool: "show_document", arguments: [
            "title": "Rome plan.", "markdown": "# Rome\n\n| Day | What |\n|---|---|\n| 1 | Table Mountain |"
        ]))
        guard case let .showDocument(title, markdown) = try call.get().command else {
            Issue.record("not a document")
            return
        }
        #expect(title == "Rome plan")
        #expect(markdown.hasPrefix("# Rome"))
        #expect(!ControlCommand.showDocument(title: "x", markdown: "y").acts)
    }

    @Test func itNeedsTheDocument() {
        #expect((try? ControlCall.parse(tool: "show_document", arguments: ["title": "x"])?.get()) == nil)
    }
}

/// The calls past the page: history, folders, a PDF, the calendar.
@Suite("Beside the page")
struct BesideThePageTests {

    @Test func historyAndFolders() throws {
        let history = try #require(ControlCall.parse(tool: "history_search", arguments: ["query": "exchange", "limit": 500]))
        #expect(try history.get().command == .searchHistory(query: "exchange", limit: 50))
        let folders = try #require(ControlCall.parse(tool: "folders_list", arguments: [:]))
        #expect(try folders.get().command == .listFolders)
    }

    @Test func aPDFByAddressOrInTheTab() throws {
        let byURL = try #require(ControlCall.parse(tool: "pdf_text", arguments: ["url": "https://fund.dk/form.pdf"]))
        #expect(try byURL.get().command == .readPDF(URL(string: "https://fund.dk/form.pdf")))
        let inTab = try #require(ControlCall.parse(tool: "pdf_text", arguments: [:]))
        #expect(try inTab.get().command == .readPDF(nil))
        #expect((try? ControlCall.parse(tool: "pdf_text", arguments: ["url": "javascript:alert(1)"])?.get()) == nil)
    }

    @Test func aDayOrATime() throws {
        #expect(try ControlCall.date("2027-01-01").allDay)
        #expect(try !ControlCall.date("2027-01-01T09:00").allDay)
        #expect((try? ControlCall.date("next tuesday")) == nil)
        let call = try #require(ControlCall.parse(tool: "add_to_calendar", arguments: ["title": "Book club", "start": "2027-01-01"]))
        guard case let .addToCalendar(title, _, end, allDay, _) = try call.get().command else {
            Issue.record("not an event")
            return
        }
        #expect(title == "Book club" && allDay && end == nil)
    }
}
