import Foundation

/// The agent panel's conversation with Claude Code, one JSON line each way.
///
/// Luna runs `claude -p --input-format stream-json --output-format stream-json`
/// and this is both halves of that: what one line of its output means, and the
/// lines Luna writes to it. The shapes are the Agent SDK's own
/// (`SDKUserMessage`, `SDKControlRequest`, the `stream_event` partials), read
/// from its type definitions; the output was checked against a live run.
///
/// Pure, so the reading is tested without a process.
public enum AgentStream {

    /// What one output line said.
    public enum Event: Sendable, Equatable {
        /// The session is up.
        case started(session: String)
        /// A new paragraph of the agent's own words is starting.
        case textBegan
        /// More of it, as it is written.
        case text(String)
        /// The paragraph as it ended, which replaces what the pieces built.
        case textEnded(String)
        /// The agent is thinking before it writes or acts.
        case thinking
        /// A tool call, with its input: `name` is the tool's full name
        /// (`mcp__luna__navigate`).
        case toolStarted(id: String, name: String, input: [String: JSONValue])
        case toolFinished(id: String, failed: Bool)
        /// The API is retrying after an error.
        case retrying
        /// The turn is over. `message` is the final answer, or what went
        /// wrong when `failed`.
        case finished(failed: Bool, message: String?)
    }

    /// The events in one line of output. Empty for the many lines that say
    /// nothing the panel shows (hooks, status, usage, control replies).
    public static func events(in line: String) -> [Event] {
        guard let value = JSONValue.parse(Data(line.utf8)) else { return [] }
        switch value["type"]?.string {
        case "system": return system(value)
        case "stream_event": return value["event"].map(partial) ?? []
        case "assistant": return assistant(value)
        case "user": return toolResults(value)
        case "result":
            let failed = value["is_error"]?.bool ?? (value["subtype"]?.string != "success")
            return [.finished(failed: failed, message: value["result"]?.string)]
        default: return []
        }
    }

    private static func system(_ value: JSONValue) -> [Event] {
        switch value["subtype"]?.string {
        case "init": value["session_id"]?.string.map { [.started(session: $0)] } ?? []
        case "api_retry": [.retrying]
        default: []
        }
    }

    /// The partial message stream: only the starts and the text, which is
    /// what makes the panel read as live. Tools are taken from the whole
    /// message, which has their complete input.
    private static func partial(_ event: JSONValue) -> [Event] {
        switch event["type"]?.string {
        case "content_block_start":
            switch event["content_block"]?["type"]?.string {
            case "text": return [.textBegan]
            case "thinking", "redacted_thinking": return [.thinking]
            default: return []
            }
        case "content_block_delta":
            guard event["delta"]?["type"]?.string == "text_delta", let text = event["delta"]?["text"]?.string else { return [] }
            return [.text(text)]
        default:
            return []
        }
    }

    private static func assistant(_ value: JSONValue) -> [Event] {
        guard case let .array(blocks)? = value["message"]?["content"] else { return [] }
        return blocks.compactMap { block in
            switch block["type"]?.string {
            case "text":
                return block["text"]?.string.map(Event.textEnded)
            case "tool_use":
                guard let id = block["id"]?.string, let name = block["name"]?.string else { return nil }
                guard case let .object(input)? = block["input"] else { return .toolStarted(id: id, name: name, input: [:]) }
                return .toolStarted(id: id, name: name, input: input)
            default:
                return nil
            }
        }
    }

    private static func toolResults(_ value: JSONValue) -> [Event] {
        guard case let .array(blocks)? = value["message"]?["content"] else { return [] }
        return blocks.compactMap { block in
            guard block["type"]?.string == "tool_result", let id = block["tool_use_id"]?.string else { return nil }
            return .toolFinished(id: id, failed: block["is_error"]?.bool ?? false)
        }
    }

    // MARK: - What Luna writes

    /// A message from the user. `now` hands it to the agent while it works,
    /// rather than holding it for the end of the turn.
    public static func userMessage(_ text: String, now: Bool) -> String {
        line([
            "type": "user",
            "message": ["role": "user", "content": .string(text)],
            "parent_tool_use_id": .null,
            "session_id": "",
            "priority": .string(now ? "now" : "next")
        ])
    }

    /// Stops the turn that is running.
    public static func interrupt(id: String) -> String {
        line(["type": "control_request", "request_id": .string(id), "request": ["subtype": "interrupt"]])
    }

    private static func line(_ value: JSONValue) -> String {
        (String(data: value.encoded(), encoding: .utf8) ?? "{}") + "\n"
    }

    /// The Luna Control tool behind a tool name, or nil for a tool of the
    /// agent's own (a web search, say).
    public static func lunaTool(_ name: String) -> String? {
        guard name.hasPrefix(serverPrefix) else { return nil }
        return String(name.dropFirst(serverPrefix.count))
    }

    /// Luna's server name in the agent's MCP config, and so the prefix on
    /// every one of its tools there.
    public static let serverName = "luna"
    static var serverPrefix: String { "mcp__\(serverName)__" }
}
