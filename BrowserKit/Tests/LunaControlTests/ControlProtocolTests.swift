import Foundation
import LunaControl
import Synchronization
import Testing

/// MCP as `ControlSession` speaks it, and the calls it decodes, with a
/// performer that records what it was asked instead of driving a browser.
@Suite("Luna Control protocol")
struct ControlProtocolTests {

    /// Everything the performer was handed, in order.
    final class Calls: Sendable {
        let seen = Mutex<[(ControlCall, ControlClient)]>([])
        var all: [(ControlCall, ControlClient)] { seen.withLock { $0 } }
    }

    private func session(_ calls: Calls = Calls()) -> ControlSession {
        ControlSession { call, client in
            calls.seen.withLock { $0.append((call, client)) }
            return .text("done")
        }
    }

    private func send(_ session: ControlSession, _ message: JSONValue) async -> JSONValue? {
        await session.handle(message.encoded()).flatMap(JSONValue.parse)
    }

    private func request(_ id: Int, _ method: String, _ params: JSONValue = [:]) -> JSONValue {
        ["jsonrpc": "2.0", "id": .int(id), "method": .string(method), "params": params]
    }

    @Test func initializeNamesTheClientAndAgreesAVersion() async {
        let session = session()
        let reply = await send(session, request(1, "initialize", [
            "protocolVersion": "2025-03-26",
            "clientInfo": ["name": "claude-code", "version": "2.0"]
        ]))
        #expect(reply?["id"] == 1)
        #expect(reply?["result"]?["protocolVersion"] == "2025-03-26")
        #expect(reply?["result"]?["capabilities"]?["tools"] != nil)
        #expect(await session.client.displayName == "Claude Code")

        let future = await send(session, request(2, "initialize", ["protocolVersion": "2099-01-01"]))
        #expect(future?["result"]?["protocolVersion"]?.string == ControlSession.protocolVersions[0])
    }

    @Test func notificationsGetNoReply() async {
        let reply = await session().handle((["jsonrpc": "2.0", "method": "notifications/initialized"] as JSONValue).encoded())
        #expect(reply == nil)
    }

    @Test func garbageIsAParseErrorAndUnknownMethodsAreRefused() async {
        let garbage = await session().handle(Data("{not json".utf8)).flatMap(JSONValue.parse)
        #expect(garbage?["error"]?["code"] == -32700)
        let unknown = await send(session(), request(4, "resources/list"))
        #expect(unknown?["error"]?["code"] == -32601)
        #expect(unknown?["id"] == 4)
    }

    @Test func toolsListMatchesWhatParseAccepts() async {
        let reply = await send(session(), request(1, "tools/list"))
        guard case let .array(tools)? = reply?["result"]?["tools"] else {
            Issue.record("no tools")
            return
        }
        let names = Set(tools.compactMap { $0["name"]?.string })
        #expect(names == ControlTools.names)
        #expect(names.isSuperset(of: ["tabs_list", "tab_open", "navigate", "read_page", "find", "click", "type",
                                      "key", "scroll", "form_input", "screenshot", "javascript", "console_read",
                                      "tab_close", "wait", "page_text"]))
        for tool in tools {
            #expect(tool["inputSchema"]?["type"] == "object")
            #expect(tool["description"]?.string?.isEmpty == false)
        }
    }

    @Test func toolsCallDispatchesTheDecodedCallWithTheClient() async {
        let calls = Calls()
        let session = session(calls)
        _ = await send(session, request(1, "initialize", ["clientInfo": ["name": "codex-mcp-client"]]))
        let reply = await send(session, request(2, "tools/call", [
            "name": "click", "arguments": ["tabId": 3, "ref": "e12"]
        ]))
        #expect(reply?["result"]?["content"]?.debugText == "done")
        #expect(reply?["result"]?["isError"] == false)
        #expect(calls.all.count == 1)
        #expect(calls.all.first?.0 == ControlCall(tab: 3, .click(.ref("e12"), clickCount: 1)))
        #expect(calls.all.first?.1.displayName == "Codex")
    }

    @Test func aBadArgumentIsAToolErrorTheModelCanRead() async {
        let calls = Calls()
        let reply = await send(session(calls), request(1, "tools/call", ["name": "navigate", "arguments": [:]]))
        #expect(reply?["result"]?["isError"] == true)
        #expect(reply?["result"]?["content"]?.debugText?.contains("url") == true)
        #expect(calls.all.isEmpty)
        let unknown = await send(session(calls), request(2, "tools/call", ["name": "format_disk"]))
        #expect(unknown?["error"]?["code"] == -32602)
    }

    @Test func parsesEveryTool() throws {
        func parse(_ tool: String, _ args: [String: JSONValue]) -> ControlCall? {
            try? ControlCall.parse(tool: tool, arguments: args)?.get()
        }
        #expect(parse("navigate", ["url": "example.com"])?.command == .navigate(.url(URL(string: "https://example.com")!)))
        #expect(parse("navigate", ["url": "back"])?.command == .navigate(.back))
        #expect(parse("click", ["coordinate": [10, 20.5], "click_count": 2])?.command
            == .click(.point(x: 10, y: 20.5), clickCount: 2))
        #expect(parse("click", ["x": "4", "y": 5])?.command == .click(.point(x: 4, y: 5), clickCount: 1))
        #expect(parse("click", [:]) == nil)
        #expect(parse("read_page", ["filter": "interactive", "max_depth": 500])?.command
            == .readPage(interactiveOnly: true, ref: nil, maxDepth: 60))
        #expect(parse("scroll", ["direction": "up", "amount": 2])?.command == .scroll(.up, amount: 2, target: nil))
        #expect(parse("scroll", ["direction": "sideways"]) == nil)
        #expect(parse("form_input", ["ref": "e2", "value": true])?.command == .fill(ref: "e2", value: true))
        #expect(parse("wait", ["seconds": 90])?.command == .wait(seconds: 30))
        #expect(parse("tab_close", [:]) == nil)
        #expect(parse("tab_close", ["tabId": 4]) == ControlCall(tab: 4, .closeTab))
        #expect(parse("tab_open", [:])?.command == .openTab(nil))
        #expect(parse("tab_open", ["url": "javascript:alert(1)"]) == nil)
        #expect(ControlCall.parse(tool: "nope", arguments: [:]) == nil)
    }

    @Test(arguments: [
        ("claude-code", "Claude Code"),
        ("codex-mcp-client", "Codex"),
        ("cursor-vscode", "Cursor"),
        ("claude-ai", "Claude AI"),
        ("Visual Studio Code", "Visual Studio Code"),
        ("myAgent", "My Agent"),
        ("goose", "Goose"),
        ("", "Agent"),
        ("---", "Agent"),
        ("mcp", "Mcp")
    ])
    func prettifiesClientNames(raw: String, pretty: String) {
        #expect(ControlClient.displayName(for: raw) == pretty)
    }
}

extension JSONValue {
    /// The text of a result's first content item.
    var debugText: String? {
        guard case let .array(items) = self else { return nil }
        return items.first?["text"]?.string
    }
}
