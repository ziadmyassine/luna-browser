import Darwin
import Foundation
import LunaControl
import Testing

/// The helper's pipe, the socket and Luna's session end to end: what an MCP
/// client writes to `luna-control` reaches the performer, and the answer
/// comes back — and with nothing listening, the helper still answers.
@Suite("Luna Control relay", .serialized)
struct ControlRelayTests {

    /// A short path: `sun_path` holds 104 bytes and the test runner's
    /// temporary directory can use most of them.
    private func socketPath() -> URL {
        URL(filePath: "/tmp/lc-\(UUID().uuidString.prefix(8))/luna.sock")
    }

    /// The relay on a thread with a pipe for stdin and one for stdout, the
    /// way an MCP client runs it.
    private final class Harness {
        let input: (read: Int32, write: Int32)
        let output: (read: Int32, write: Int32)
        let reader: LineReader

        init(socket: URL) {
            var inPipe: [Int32] = [0, 0]
            var outPipe: [Int32] = [0, 0]
            pipe(&inPipe)
            pipe(&outPipe)
            input = (inPipe[0], inPipe[1])
            output = (outPipe[0], outPipe[1])
            reader = LineReader(fd: outPipe[0])
            let relay = ControlRelay(socketPath: socket, output: outPipe[1])
            let stdin = inPipe[0]
            Thread.detachNewThread { relay.run(input: stdin) }
        }

        func ask(_ message: JSONValue) -> JSONValue? {
            ControlSocket.writeLine(message.encoded(), to: input.write)
            return reader.next().flatMap(JSONValue.parse)
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

    @Test func roundTripsThroughTheSocket() throws {
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
        #expect(harness.ask(Self.initialize)?["result"]?["serverInfo"]?["name"] == "luna")
        // Named before the reply is written, so Settings can already show it.
        #expect(listener.clientNames == ["test-agent"])
        let reply = harness.ask(Self.call(2, "screenshot"))
        #expect(reply?["id"] == 2)
        #expect(reply?["result"]?["content"]?.debugText == "Test Agent asked for screenshot")
    }

    @Test func answersByItselfUntilLunaIsThereAndThenIntroducesTheClient() throws {
        let path = socketPath()
        let harness = Harness(socket: path)
        defer { harness.finish() }

        // Nothing is listening: the handshake still works and a call says why it cannot.
        #expect(harness.ask(Self.initialize)?["result"]?["protocolVersion"] == "2025-06-18")
        let listed = harness.ask(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        #expect(listed?["result"]?["tools"] != nil)
        let refused = harness.ask(Self.call(3, "tabs_list"))
        #expect(refused?["result"]?["isError"] == true)
        #expect(refused?["result"]?["content"]?.debugText == ControlRelay.unreachable)

        // Luna starts. The next call connects, and the replayed `initialize`
        // means Luna knows who is asking; its answer to the replay is not
        // passed on, so the next line out is the call's own.
        let listener = try ControlListener(path: path) { _, client in .text(client.displayName) }
        defer { listener.stop() }
        let reply = harness.ask(Self.call(4, "tabs_list"))
        #expect(reply?["id"] == 4)
        #expect(reply?["result"]?["content"]?.debugText == "Test Agent")
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
