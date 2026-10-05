import Foundation

/// The agent panel's conversation with Codex: what one line of
/// `codex exec --json` means, in `AgentStream`'s own events, so the panel
/// reads both engines the same way.
///
/// The shapes are Codex's `exec_events.rs` (and the TypeScript SDK's
/// `events.ts`, which mirrors it): `thread.started`, `turn.*`, and `item.*`
/// carrying an `agent_message`, `mcp_tool_call`, `web_search` and so on.
/// Codex sends the agent's words whole, as a completed item, never in pieces.
///
/// Pure, so the reading is tested without a process.
public enum AgentCodexStream {

    public static func events(in line: String) -> [AgentStream.Event] {
        guard let value = JSONValue.parse(Data(line.utf8)) else { return [] }
        switch value["type"]?.string {
        case "thread.started":
            return value["thread_id"]?.string.map { [.started(session: $0)] } ?? []
        case "turn.started":
            return [.thinking]
        case "turn.completed":
            return [.finished(failed: false, message: nil)]
        case "turn.failed":
            return [.finished(failed: true, message: value["error"]?["message"]?.string)]
        case "item.started":
            return value["item"].map { started($0) } ?? []
        case "item.completed":
            return value["item"].map { completed($0) } ?? []
        default:
            // `error` is followed by `turn.failed`, or by the process
            // ending, which say it to the user; `item.updated` is a to-do
            // list ticking over.
            return []
        }
    }

    private static func started(_ item: JSONValue) -> [AgentStream.Event] {
        guard let id = item["id"]?.string, let tool = tool(item) else {
            return item["type"]?.string == "reasoning" ? [.thinking] : []
        }
        return [.toolStarted(id: id, name: tool.name, input: tool.input)]
    }

    private static func completed(_ item: JSONValue) -> [AgentStream.Event] {
        let id = item["id"]?.string ?? UUID().uuidString
        switch item["type"]?.string {
        case "agent_message":
            guard let text = item["text"]?.string else { return [] }
            return [.textBegan, .textEnded(text)]
        case "reasoning":
            return [.thinking]
        default:
            guard let tool = tool(item) else { return [] }
            let failed = item["status"]?.string == "failed" || (item["error"].map { $0 != .null } ?? false)
            // A web search can arrive finished without having been started.
            return [.toolStarted(id: id, name: tool.name, input: tool.input), .toolFinished(id: id, failed: failed)]
        }
    }

    /// An item that is a step, as the name and input Claude Code would have
    /// given it, so `AgentSteps` words it the same: a Luna Control call is
    /// `mcp__luna__<tool>`, a search is `WebSearch`.
    static func tool(_ item: JSONValue) -> (name: String, input: [String: JSONValue])? {
        switch item["type"]?.string {
        case "mcp_tool_call":
            guard let server = item["server"]?.string, let tool = item["tool"]?.string else { return nil }
            var input: [String: JSONValue] = [:]
            if case let .object(arguments)? = item["arguments"] { input = arguments }
            // Some versions send the arguments as a JSON string.
            if let text = item["arguments"]?.string, case let .object(arguments)? = JSONValue.parse(Data(text.utf8)) {
                input = arguments
            }
            return ("mcp__\(server)__\(tool)", input)
        case "web_search":
            return ("WebSearch", item["query"].map { ["query": $0] } ?? [:])
        case "command_execution":
            return ("Bash", item["command"].map { ["command": $0] } ?? [:])
        case "file_change":
            return ("Edit", [:])
        default:
            return nil
        }
    }
}
