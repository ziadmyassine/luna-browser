import Darwin
import Foundation
import Synchronization

/// Luna's end of the socket: accepts connections and gives each one a
/// `ControlSession` of its own and a thread to read it on.
///
/// While one exists the socket file exists, and `stop()` removes it, so
/// "the setting is off" and "there is nothing to connect to" are one fact.
public final class ControlListener: Sendable {

    private let path: URL
    private let source: any DispatchSourceRead
    /// Each open connection and the client it named in `initialize`, empty
    /// until it has.
    private let connections = Mutex<[Int32: String]>([:])
    private let onClientsChange: @Sendable () -> Void

    /// The `clientInfo.name` of every client connected now — what Settings
    /// shows as an app being in use.
    public var clientNames: [String] {
        connections.withLock { Array($0.values.filter { !$0.isEmpty }) }
    }

    public init(
        path: URL,
        version: String = "1.0",
        onClientsChange: @escaping @Sendable () -> Void = {},
        perform: @escaping ControlPerformer
    ) throws(ControlSocket.Failure) {
        self.onClientsChange = onClientsChange
        self.path = path
        let fd = try ControlSocket.listen(at: path)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "luna.control.accept"))
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0, let self else { return }
            // Darwin hands the listening socket's `O_NONBLOCK` on to the
            // accepted one, and this one is read on a thread that blocks.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            self.connections.withLock { $0[client] = "" }
            let session = ControlSession(version: version, perform: perform) { [weak self] named in
                self?.connections.withLock { $0[client] = named.rawName }
                self?.onClientsChange()
            }
            Thread.detachNewThread { [weak self] in
                Self.serve(client, session)
                self?.connections.withLock { _ = $0.removeValue(forKey: client) }
                self?.onClientsChange()
                close(client)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    /// Closes the socket and every connection on it. Each connection's
    /// helper sees end of file and falls back to answering "Luna is not
    /// reachable" until it can connect again.
    public func stop() {
        source.cancel()
        unlink(path.path(percentEncoded: false))
        connections.withLock { open in
            for fd in open.keys { shutdown(fd, SHUT_RDWR) }
        }
    }

    private static func serve(_ fd: Int32, _ session: ControlSession) {
        let reader = LineReader(fd: fd)
        while let line = reader.next() {
            let reply = waitFor { await session.handle(line) }
            if let reply, !ControlSocket.writeLine(reply, to: fd) { return }
        }
    }
}
