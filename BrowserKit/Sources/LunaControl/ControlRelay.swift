import Darwin
import Foundation
import Synchronization

/// `luna-control`'s whole job: an MCP server on stdin and stdout that passes
/// every line through to Luna's socket and every reply back.
///
/// MCP clients start their servers when they start, and Luna may not be
/// running then, or may quit and come back mid-session. So while there is no
/// socket the relay answers by itself — `initialize` and `tools/list`
/// normally, every call with how to fix it — and tries again on each message.
/// When it does get through after `initialize` has already happened, it
/// replays that `initialize` so Luna still learns who the client is, and
/// swallows Luna's answer to it.
public final class ControlRelay: Sendable {

    static let replayID: JSONValue = "luna-control-replay"

    public static let unreachable = """
    Luna isn't reachable. Open Luna and turn on Settings → Advanced → “Allow apps to control Luna”, then try again.
    """

    private let socketPath: URL
    private let output: Int32
    private let local = ControlSession { _, _ in .error(ControlRelay.unreachable) }
    private let state = Mutex<(socket: Int32?, initialize: JSONValue?)>((nil, nil))
    private let writing = Mutex(())

    public init(socketPath: URL, output: Int32 = STDOUT_FILENO) {
        self.socketPath = socketPath
        self.output = output
    }

    /// Relays until `input` reaches end of file, which is how an MCP client
    /// says it is finished with a server.
    public func run(input: Int32 = STDIN_FILENO) {
        let reader = LineReader(fd: input)
        while let line = reader.next() {
            let message = JSONValue.parse(line)
            if message?["method"]?.string == "initialize" {
                state.withLock { $0.initialize = message }
            }
            if let socket = connected(replaying: message?["method"]?.string != "initialize"),
               ControlSocket.writeLine(line, to: socket) {
                continue
            }
            if let reply = waitFor({ [local] in await local.handle(line) }) { emit(reply) }
        }
        state.withLock { if let socket = $0.socket { shutdown(socket, SHUT_RDWR) } }
    }

    /// The live socket, connecting if there is none.
    private func connected(replaying: Bool) -> Int32? {
        if let socket = state.withLock({ $0.socket }) { return socket }
        guard let socket = try? ControlSocket.connect(to: socketPath) else { return nil }
        let initialize = state.withLock { current in
            current.socket = socket
            return current.initialize
        }
        if replaying, case var .object(replay)? = initialize {
            replay["id"] = Self.replayID
            ControlSocket.writeLine(JSONValue.object(replay).encoded(), to: socket)
            ControlSocket.writeLine((["jsonrpc": "2.0", "method": "notifications/initialized"] as JSONValue).encoded(), to: socket)
        }
        Thread.detachNewThread { [self] in pump(socket) }
        return socket
    }

    /// Luna's replies, out to the client, until Luna goes away.
    private func pump(_ socket: Int32) {
        let reader = LineReader(fd: socket)
        while let line = reader.next() {
            if JSONValue.parse(line)?["id"] == Self.replayID { continue }
            emit(line)
        }
        state.withLock { if $0.socket == socket { $0.socket = nil } }
        close(socket)
    }

    /// One writer at a time: replies come from both the socket's thread and
    /// the local session, and two interleaved half-lines are one broken one.
    private func emit(_ line: Data) {
        _ = writing.withLock { _ in ControlSocket.writeLine(line, to: output) }
    }
}
