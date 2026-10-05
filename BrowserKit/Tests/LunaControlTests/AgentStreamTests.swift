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

/// `label_tab`: a tab's name and icon, from the agent.
@Suite("Label tab")
struct LabelTabTests {

    @Test func aNameAndAnIconOnAColour() throws {
        let call = try #require(ControlCall.parse(tool: "label_tab", arguments: [
            "tabId": 3, "title": " Flights\n", "symbol": "airplane", "color": "Teal"
        ]))
        #expect(try call.get().command == .labelTab(title: "Flights", symbol: "airplane", colour: "teal"))
        #expect(!ControlCommand.labelTab(title: "x", symbol: nil, colour: nil).acts)
    }

    @Test func itNeedsATabAndSomethingToSay() {
        #expect((try? ControlCall.parse(tool: "label_tab", arguments: ["title": "Flights"])?.get()) == nil)
        #expect((try? ControlCall.parse(tool: "label_tab", arguments: ["tabId": 3])?.get()) == nil)
        #expect((try? ControlCall.parse(tool: "label_tab", arguments: ["tabId": 3, "title": "x", "color": "beige"])?.get()) == nil)
    }

    @Test func agentsAreToldToNameThings() {
        #expect(ControlSession.instructions.contains("name_task"))
        #expect(ControlSession.instructions.contains("label_tab"))
        #expect(ControlTools.all.contains { $0["name"]?.string == "label_tab" })
    }
}
