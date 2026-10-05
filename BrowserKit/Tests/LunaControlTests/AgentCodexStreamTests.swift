import Foundation
@testable import LunaControl
import Testing

/// The agent panel's reading of `codex exec --json`, from lines shaped as
/// Codex's `exec_events.rs` defines them.
@Suite("Agent Codex stream")
struct AgentCodexStreamTests {

    @Test func theThreadStartsAndTheTurnEnds() {
        #expect(AgentCodexStream.events(in: #"{"type":"thread.started","thread_id":"th-1"}"#) == [.started(session: "th-1")])
        #expect(AgentCodexStream.events(in: #"{"type":"turn.started"}"#) == [.thinking])
        #expect(AgentCodexStream.events(in: #"{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":2}}"#)
            == [.finished(failed: false, message: nil)])
        #expect(AgentCodexStream.events(in: #"{"type":"turn.failed","error":{"message":"You've hit your usage limit."}}"#)
            == [.finished(failed: true, message: "You've hit your usage limit.")])
    }

    @Test func theAgentsWordsArriveWhole() {
        let line = #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Found two flights."}}"#
        #expect(AgentCodexStream.events(in: line) == [.textBegan, .textEnded("Found two flights.")])
    }

    @Test func aLunaCallReadsAsClaudeCodesWould() {
        let started = #"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"luna","#
            + #""tool":"navigate","arguments":{"url":"https://sas.se"},"status":"in_progress"}}"#
        let done = #"{"type":"item.completed","item":{"id":"item_1","type":"mcp_tool_call","server":"luna","#
            + #""tool":"navigate","arguments":{"url":"https://sas.se"},"result":{"content":[]},"status":"completed"}}"#
        #expect(AgentCodexStream.events(in: started)
            == [.toolStarted(id: "item_1", name: "mcp__luna__navigate", input: ["url": "https://sas.se"])])
        #expect(AgentCodexStream.events(in: done).last == .toolFinished(id: "item_1", failed: false))
    }

    @Test func aFailedCallAndASearchThatArrivesFinished() {
        let failed = #"{"type":"item.completed","item":{"id":"i2","type":"mcp_tool_call","server":"luna","tool":"click","#
            + #""arguments":{},"error":{"message":"declined"},"status":"failed"}}"#
        #expect(AgentCodexStream.events(in: failed).last == .toolFinished(id: "i2", failed: true))
        let search = #"{"type":"item.completed","item":{"id":"i3","type":"web_search","query":"lisbon flights"}}"#
        #expect(AgentCodexStream.events(in: search)
            == [.toolStarted(id: "i3", name: "WebSearch", input: ["query": "lisbon flights"]), .toolFinished(id: "i3", failed: false)])
    }

    @Test func linesThatSayNothingShownAreSkipped() {
        #expect(AgentCodexStream.events(in: #"{"type":"item.updated","item":{"id":"t","type":"todo_list","items":[]}}"#).isEmpty)
        #expect(AgentCodexStream.events(in: #"{"type":"error","message":"Reconnecting… 1/5"}"#).isEmpty)
        #expect(AgentCodexStream.events(in: "not json").isEmpty)
    }
}
