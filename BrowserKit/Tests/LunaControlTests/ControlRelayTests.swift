import Darwin
import Foundation
import Synchronization
@testable import LunaControl
import Testing

/// The helper's pipe, the socket and Luna's session end to end: what an MCP
/// client writes to `luna-control` reaches the performer, and the answer
/// comes back — and with nothing listening, the helper still answers.
///
/// Every wait for a reply happens on a thread of its own (`offPool`). The
/// relay answers through Swift tasks, and a test blocked on a read inside
/// the cooperative pool holds one of the threads those tasks need: on CI's
/// three-core runner a few of them at once took the whole pool, and the test
/// run stopped for good.
@Suite("Luna Control relay", .serialized)
struct ControlRelayTests {

    private static func offPool<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: body()) }
        }
    }

    /// A short path: `sun_path` holds 104 bytes and the test runner's
    /// temporary directory can use most of them.
    private func socketPath() -> URL {
        URL(filePath: "/tmp/lc-\(UUID().uuidString.prefix(8))/luna.sock")
    }

    /// The relay on a thread with a pipe for stdin and one for stdout, the
    /// way an MCP client runs it.
    private final class Harness: @unchecked Sendable {
        let input: (read: Int32, write: Int32)
        let output: (read: Int32, write: Int32)
        let reader: LineReader

        init(socket: URL, tag: ControlSessionTag = ControlSessionTag(environment: [:])) {
            var inPipe: [Int32] = [0, 0]
            var outPipe: [Int32] = [0, 0]
            pipe(&inPipe)
            pipe(&outPipe)
            input = (inPipe[0], inPipe[1])
            output = (outPipe[0], outPipe[1])
            reader = LineReader(fd: outPipe[0])
            let relay = ControlRelay(socketPath: socket, output: outPipe[1], tag: tag)
            let stdin = inPipe[0]
            Thread.detachNewThread { relay.run(input: stdin) }
        }

        func ask(_ message: JSONValue) async -> JSONValue? {
            await ControlRelayTests.offPool { [self] in
                ControlSocket.writeLine(message.encoded(), to: input.write)
                return reader.next().flatMap(JSONValue.parse)
            }
        }

        func nextReply() async -> JSONValue? {
            await ControlRelayTests.offPool { [self] in reader.next().flatMap(JSONValue.parse) }
        }

        func finish() {
            close(input.write)
        }
    }

    private static let initialize: JSONValue = [
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": ["protocolVersion": "2025-06-18", "clientInfo": ["name": "test-agent"]]
    ]

    private static func call(_ id: Int, _ tool: String, _ args: JSONValue = [:]) -> JSONValue {
        ["jsonrpc": "2.0", "id": .int(id), "method": "tools/call", "params": ["name": .string(tool), "arguments": args]]
    }

    @Test func roundTripsThroughTheSocket() async throws {
        let path = socketPath()
        let listener = try ControlListener(path: path) { call, client in
            .text("\(client.displayName) asked for \(ControlAudit.tool(of: call.command))")
        }
        defer { listener.stop() }

        // User-only, both of them.
        let socketMode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
        let folderMode = try FileManager.default.attributesOfItem(
            atPath: path.deletingLastPathComponent().path
        )[.posixPermissions] as? Int
        #expect(socketMode == 0o600)
        #expect(folderMode == 0o700)

        let harness = Harness(socket: path)
        defer { harness.finish() }
        #expect(await harness.ask(Self.initialize)?["result"]?["serverInfo"]?["name"] == "luna")
        // Named before the reply is written, so Settings can already show it.
        #expect(listener.clientNames == ["test-agent"])
        let reply = await harness.ask(Self.call(2, "screenshot"))
        #expect(reply?["id"] == 2)
        #expect(reply?["result"]?["content"]?.debugText == "Test Agent asked for screenshot")
    }

    @Test func answersByItselfUntilLunaIsThereAndThenIntroducesTheClient() async throws {
        let path = socketPath()
        let harness = Harness(socket: path)
        defer { harness.finish() }

        // Nothing is listening: the handshake still works and a call says why it cannot.
        #expect(await harness.ask(Self.initialize)?["result"]?["protocolVersion"] == "2025-06-18")
        let listed = await harness.ask(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        #expect(listed?["result"]?["tools"] != nil)
        let refused = await harness.ask(Self.call(3, "tabs_list"))
        #expect(refused?["result"]?["isError"] == true)
        #expect(refused?["result"]?["content"]?.debugText == ControlRelay.unreachable)

        // Luna starts. The next call connects, and the replayed `initialize`
        // means Luna knows who is asking; its answer to the replay is not
        // passed on, so the next line out is the call's own.
        let listener = try ControlListener(path: path) { _, client in .text(client.displayName) }
        defer { listener.stop() }
        let reply = await harness.ask(Self.call(4, "tabs_list"))
        #expect(reply?["id"] == 4)
        #expect(reply?["result"]?["content"]?.debugText == "Test Agent")
    }

    /// Two sessions of one app are two agents to Luna: each helper names its
    /// session, the same one again after Luna comes back, and the title the
    /// user knows it by as soon as there is one.
    @Test func eachHelperTellsLunaWhichSessionItServes() async throws {
        let projects = URL.temporaryDirectory.appending(path: "lc-\(UUID().uuidString.prefix(8))")
        let transcript = projects.appending(path: "projects/-Users-me-app/abc.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projects) }
        try Data(#"{"type":"user"}"#.utf8).write(to: transcript)
        let tag = ControlSessionTag(environment: ["CLAUDE_CODE_SESSION_ID": "abc", "CLAUDE_CONFIG_DIR": projects.path])

        let path = socketPath()
        let seen = Mutex<[ControlClient]>([])
        let listener = try ControlListener(path: path) { _, client in
            seen.withLock { $0.append(client) }
            return .text("")
        }
        defer { listener.stop() }
        let harness = Harness(socket: path, tag: tag)
        defer { harness.finish() }
        _ = await harness.ask(Self.initialize)
        _ = await harness.ask(Self.call(2, "tabs_list"))
        #expect(listener.clients.map(\.session) == ["abc"])
        #expect(seen.withLock { $0.last?.sessionName } == nil)

        let title = #"{"type":"ai-title","aiTitle":"Fix the sidebar","sessionId":"abc"}"#
        try Data((#"{"type":"user"}"# + "\n" + title + "\n").utf8).write(to: transcript)
        try await Task.sleep(for: .seconds(ControlSessionTag.Transcript.interval + 0.1))
        _ = await harness.ask(Self.call(3, "tabs_list"))
        #expect(seen.withLock { $0.last?.session } == "abc")
        #expect(seen.withLock { $0.last?.sessionName } == "Fix the sidebar")
    }

    /// The Claude app's agent mode starts one helper for all its sessions and
    /// gives it none: a call is named after the session whose transcript has
    /// just written the call's tool-use id.
    @Test func aCallIsNamedAfterTheSessionThatWroteItsToolUse() throws {
        let root = URL.temporaryDirectory.appending(path: "lc-\(UUID().uuidString.prefix(8))")
        let folder = root.appending(path: "projects/-Users-me-app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"type":"custom-title","customTitle":"Main 2","sessionId":"abc"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_01Luna","name":"mcp__luna__tab_open"}]}}"#
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: folder.appending(path: "abc.jsonl"))
        try Data(#"{"type":"custom-title","customTitle":"Other","sessionId":"def"}"#.utf8).write(to: folder.appending(path: "def.jsonl"))
        let tag = ControlSessionTag(environment: ["CLAUDE_CONFIG_DIR": root.path])
        let call: JSONValue = [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "tab_open", "_meta": ["claudecode/toolUseId": "toolu_01Luna"]]
        ]
        #expect(tag.stamp(call)?["params"]?["_meta"]?[ControlSessionTag.nameKey]?.string == "Main 2")
        let unknown: JSONValue = [
            "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["_meta": ["claudecode/toolUseId": "toolu_none"]]
        ]
        #expect(tag.stamp(unknown)?["params"]?["_meta"]?[ControlSessionTag.nameKey] == nil, "no session wrote it")
    }

    @Test func theNameTheUserGaveOutranksTheOneTheAppGave() {
        let lines = [
            #"{"type":"custom-title","customTitle":"Main 2","sessionId":"abc"}"#,
            #"{"type":"ai-title","aiTitle":"Fix the sidebar","sessionId":"abc"}"#,
            #"{"type":"assistant","message":"custom-title"}"#
        ]
        #expect(ControlSessionTag.Transcript.title(in: Data(lines.joined(separator: "\n").utf8)) == "Main 2")
        #expect(ControlSessionTag.Transcript.title(in: Data(lines[1].utf8)) == "Fix the sidebar")
        #expect(ControlSessionTag.Transcript.title(in: Data(lines[2].utf8)) == nil)
    }

    /// Luna quitting while a call waits, as one waiting for the user's
    /// approval does, answers it at once rather than leaving the client to
    /// its own timeout.
    @Test func aCallLunaWentAwayDuringIsAnswered() async throws {
        let path = socketPath()
        let listener = try ControlListener(path: path) { _, _ in
            try? await Task.sleep(for: .seconds(60))
            return .text("too late")
        }
        let harness = Harness(socket: path)
        defer { harness.finish() }
        #expect(await harness.ask(Self.initialize)?["result"] != nil)

        ControlSocket.writeLine(Self.call(2, "tab_open").encoded(), to: harness.input.write)
        try await Task.sleep(for: .milliseconds(200))
        let started = Date()
        listener.stop()
        let reply = await harness.nextReply()
        #expect(reply?["id"] == 2)
        #expect(reply?["result"]?["isError"] == true)
        #expect(reply?["result"]?["content"]?.debugText == ControlRelay.unreachable)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func refusesToTakeOverASocketAnotherLunaIsAnswering() throws {
        let path = socketPath()
        let first = try ControlListener(path: path) { _, _ in .text("first") }
        defer { first.stop() }
        #expect(throws: ControlSocket.Failure.inUse) {
            _ = try ControlListener(path: path) { _, _ in .text("second") }
        }
    }

    @Test func stoppingRemovesTheSocket() throws {
        let path = socketPath()
        let listener = try ControlListener(path: path) { _, _ in .text("") }
        #expect(FileManager.default.fileExists(atPath: path.path))
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
}
