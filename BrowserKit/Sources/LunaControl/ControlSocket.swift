import Darwin
import Foundation
import Synchronization

/// The Unix domain socket between Luna and `luna-control`, and the
/// newline-delimited reading and writing both ends share.
///
/// A socket file rather than a TCP port: nothing off this Mac can reach it,
/// and the file's permissions decide who on it can. The directory is 0700
/// and the socket 0600, so only the user Luna runs as can connect — which
/// matters, because whoever connects drives a browser that is signed in to
/// everything the user is.
public enum ControlSocket {

    /// `~/Library/Application Support/<bundle id>/Control/luna.sock`. The
    /// helper has no bundle of its own to ask, so it is handed Luna's.
    public static func path(bundleIdentifier: String = "dk.novapps.luna") -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support
            .appending(path: bundleIdentifier)
            .appending(path: "Control", directoryHint: .isDirectory)
            .appending(path: "luna.sock")
    }

    public enum Failure: Error, Equatable {
        case pathTooLong
        case inUse
        case system(String, Int32)
    }

    /// Binds and listens at `path`, making its directory user-only on the
    /// way. A socket file left by a Luna that did not quit cleanly is
    /// replaced; one that another running Luna is still answering on is not.
    public static func listen(at path: URL) throws(Failure) -> Int32 {
        let directory = path.deletingLastPathComponent().path(percentEncoded: false)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard chmod(directory, 0o700) == 0 else { throw .system("chmod", errno) }
        if let live = try? connect(to: path) {
            close(live)
            throw .inUse
        }
        unlink(path.path(percentEncoded: false))
        var address = try address(for: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system("socket", errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path.path(percentEncoded: false), 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            let error = errno
            close(fd)
            throw .system("bind", error)
        }
        return fd
    }

    public static func connect(to path: URL) throws(Failure) -> Int32 {
        var address = try address(for: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system("socket", errno) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            close(fd)
            throw .system("connect", error)
        }
        // A reader that has gone away must be an error on write, not a signal
        // that kills the process doing the writing.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    private static func address(for path: URL) throws(Failure) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path(percentEncoded: false).utf8)
        // `sun_path` is 104 bytes on Darwin, terminator included.
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw .pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    /// Writes one message and its newline. False once the other end is gone.
    @discardableResult
    public static func writeLine(_ data: Data, to fd: Int32) -> Bool {
        var line = data
        line.append(0x0A)
        return line.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

/// Reads newline-delimited messages from a file descriptor, blocking. Used on
/// a thread of its own, never on Swift concurrency's shared pool.
public final class LineReader {
    private let fd: Int32
    private var buffer = Data()

    public init(fd: Int32) { self.fd = fd }

    /// The next non-empty line without its newline, or nil at end of file.
    public func next() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex ..< newline]
                buffer.removeSubrange(buffer.startIndex ... newline)
                if line.isEmpty { continue }
                return Data(line)
            }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(fd, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                defer { buffer.removeAll() }
                return buffer.isEmpty ? nil : buffer
            }
            buffer.append(contentsOf: chunk[0 ..< count])
        }
    }
}

/// Runs `body` on the calling thread and waits for it. For the socket threads,
/// which block by design, to hand a message to a `ControlSession`.
func waitFor<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let box = Mutex<T?>(nil)
    let done = DispatchSemaphore(value: 0)
    Task {
        let value = await body()
        box.withLock { $0 = value }
        done.signal()
    }
    done.wait()
    return box.withLock { $0! }
}
