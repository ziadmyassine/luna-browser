import Foundation
import WebKit

// Adapted from Search's ExtensionNative.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// Chrome's native messaging (§14.7, docs/EXTENSIONS.md §5): an extension
/// talking to an app on this Mac — a password manager unlocking with its
/// desktop app, a clipper handing a page to a notes app.
///
/// Those apps register with Chrome by leaving a JSON file in a
/// `NativeMessagingHosts` folder: a name, the program to run, and which
/// extensions may run it. Luna reads the same files, runs the same program
/// with the same argument, and speaks the same protocol — each message a
/// four-byte length and a line of JSON over the program's stdin and stdout.
/// A host that does not list the extension's id among its `allowed_origins` is
/// not run. Nook skipped that check; it is the only gate there is.
///
/// A host may still refuse the caller. Apple's `PasswordManagerBrowserExtensionHelper`
/// has a parent launch constraint: it runs only under a browser holding the
/// `com.apple.developer.web-browser.public-key-credential` entitlement or on a
/// fixed list of about forty, and is killed at launch otherwise.
@MainActor
struct ExtensionNative {

    struct Refused: LocalizedError, Equatable {
        let why: String
        var errorDescription: String? { why }
    }

    /// Luna's own folder first, then where Chromium browsers look, per user and
    /// for the whole Mac. The first manifest found by a name is the one used.
    let folders: [URL]

    init(folders: [URL]) {
        self.folders = folders
    }

    init(ownFolder: URL) {
        let support = URL.applicationSupportDirectory
        folders = [ownFolder] + [
            "Google/Chrome", "Chromium", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Arc/User Data"
        ].map { support.appending(path: "\($0)/NativeMessagingHosts", directoryHint: .isDirectory) } + [
            "/Library/Google/Chrome/NativeMessagingHosts",
            "/Library/Application Support/Chromium/NativeMessagingHosts",
            "/Library/Microsoft/Edge/NativeMessagingHosts"
        ].map { URL(filePath: $0, directoryHint: .isDirectory) } + [
            // Read last: a host of the same name that Chrome or the system knows comes first.
            "Vivaldi", "com.operasoftware.Opera"
        ].map { support.appending(path: "\($0)/NativeMessagingHosts", directoryHint: .isDirectory) }
    }

    /// Chrome's origin for an extension, which hosts list and are passed as argv.
    static func origin(of extensionID: String) -> String { "chrome-extension://\(extensionID)/" }

    /// The program for `name`, if one is registered and lets this extension in.
    func host(_ name: String, for extensionID: String) throws -> URL {
        guard name.range(of: #"^[a-z0-9_]+(\.[a-z0-9_]+)*$"#, options: .regularExpression) != nil else {
            throw Refused(why: "Invalid native messaging host name.")
        }
        for folder in folders {
            let file = folder.appending(path: name + ".json")
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = manifest["path"] as? String
            else { continue }
            let allowed = manifest["allowed_origins"] as? [String] ?? []
            guard allowed.contains(Self.origin(of: extensionID)) else {
                throw Refused(why: "Access to the specified native messaging host is forbidden.")
            }
            let program = path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)
            guard FileManager.default.isExecutableFile(atPath: program.path) else {
                throw Refused(why: "Specified native messaging host not found.")
            }
            return program
        }
        throw Refused(why: "Specified native messaging host not found.")
    }

    /// `runtime.sendNativeMessage`: run, send one, read one, stop.
    func send(_ message: Any, to name: String, from extensionID: String) async throws -> Any? {
        let pipe = NativeHostPipe(program: try host(name, for: extensionID), origin: Self.origin(of: extensionID))
        try pipe.start()
        defer { pipe.stop() }
        try pipe.write(message)
        return try await pipe.readOne()
    }

    /// `runtime.connectNative`: run, and keep the two talking until either end
    /// lets go.
    func connect(_ port: WKWebExtension.MessagePort, from extensionID: String) throws {
        guard let name = port.applicationIdentifier else { throw Refused(why: "No native messaging host named.") }
        let program = try host(name, for: extensionID)
        // A new port is often a worker starting over; the one before may have
        // left its host behind.
        Self.stopOrphans()
        let pipe = NativeHostPipe(program: program, origin: Self.origin(of: extensionID))
        try pipe.start()
        pipe.onMessage = { message in
            nonisolated(unsafe) let message = message
            DispatchQueue.main.async { MainActor.assumeIsolated { port.sendMessage(message, completionHandler: nil) } }
        }
        pipe.onExit = {
            DispatchQueue.main.async { MainActor.assumeIsolated { if !port.isDisconnected { port.disconnect() } } }
        }
        var beating: Timer?
        port.messageHandler = { message, _ in
            guard let message else { return }
            // The shim asking whether the port has arrived (`__lunaNative`,
            // after the worker's WebSocket in the script): answered here and
            // never passed on to the host.
            if let asked = message as? [String: Any], let word = asked[ExtensionShim.nativeKey] {
                guard (word as? String) == "here?" else { return }
                port.sendMessage([ExtensionShim.nativeKey: "here"], completionHandler: nil)
                // WebKit unloads a worker that has not posted on a port for two
                // minutes, and iCloud Passwords then forgets it was paired and
                // asks for a code again. Chrome keeps a worker with a port to an
                // app alive; here a word now and then, heard only by the shim,
                // has the worker answer on the port, which is what WebKit counts.
                if beating == nil {
                    beating = Timer.scheduledTimer(withTimeInterval: Self.heartbeat, repeats: true) { timer in
                        let gone = MainActor.assumeIsolated { port.isDisconnected }
                        if gone { return timer.invalidate() }
                        MainActor.assumeIsolated { port.sendMessage([ExtensionShim.nativeKey: "alive"], completionHandler: nil) }
                    }
                }
                return
            }
            try? pipe.write(message)
        }
        port.disconnectHandler = { _ in
            beating?.invalidate()
            pipe.stop()
        }
        Live.keep(pipe, for: port)
    }

    /// Well inside WebKit's two minutes.
    static let heartbeat: TimeInterval = 25

    /// WebKit does not always say when a port goes: an extension unloaded —
    /// reloaded, turned off, removed — leaves its worker's ports disconnected
    /// without calling their disconnect handlers, and each host would run on,
    /// with any prompt it had open, until Luna quit. So the hosts of ports that
    /// have gone are stopped here; a port still connected keeps its own.
    static func stopOrphans() {
        for (pipe, port) in Live.pipes.values where port.isDisconnected { pipe.stop() }
    }

    /// Hosts that are connected, held until they end.
    @MainActor
    private enum Live {
        static var pipes: [ObjectIdentifier: (pipe: NativeHostPipe, port: WKWebExtension.MessagePort)] = [:]

        static func keep(_ pipe: NativeHostPipe, for port: WKWebExtension.MessagePort) {
            let key = ObjectIdentifier(pipe)
            pipes[key] = (pipe, port)
            let previous = pipe.onExit
            pipe.onExit = {
                previous?()
                DispatchQueue.main.async { MainActor.assumeIsolated { _ = pipes.removeValue(forKey: key) } }
            }
        }
    }
}

/// One host program and the framing Chrome uses to talk to it. Its output is
/// read on the file handle's own queue, so everything it holds is behind a lock.
final class NativeHostPipe: @unchecked Sendable {

    /// Chrome's limit on a message to a host.
    static let maximumMessageBytes = 1 << 20

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var waiters: [CheckedContinuation<Reply, any Error>] = []

    /// A host's reply, which is JSON and so safe to hand across threads.
    private struct Reply: @unchecked Sendable { let message: Any? }
    private var _onMessage: (@Sendable (Any) -> Void)?
    private var _onExit: (@Sendable () -> Void)?

    var onMessage: (@Sendable (Any) -> Void)? {
        get { lock.withLock { _onMessage } }
        set { lock.withLock { _onMessage = newValue } }
    }

    var onExit: (@Sendable () -> Void)? {
        get { lock.withLock { _onExit } }
        set { lock.withLock { _onExit = newValue } }
    }

    init(program: URL, origin: String) {
        process.executableURL = program
        process.arguments = [origin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A host already gone — refused to run, killed as it started — would
        // take Luna with it: writing to its closed pipe raises SIGPIPE. With
        // this the write only fails.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                finish()
            } else {
                take(chunk)
            }
        }
        process.terminationHandler = { [weak self] _ in self?.finish() }
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func write(_ message: Any) throws {
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        guard json.count <= Self.maximumMessageBytes else {
            throw ExtensionNative.Refused(why: "Message too long for a native messaging host.")
        }
        var length = UInt32(json.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        try input.fileHandleForWriting.write(contentsOf: frame)
    }

    func readOne() async throws -> Any? {
        let reply = try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
        return reply.message
    }

    /// Whole frames out of what has arrived: the first ones to whoever is
    /// waiting for a reply, the rest to `onMessage`.
    private func take(_ chunk: Data) {
        let (handed, rest, listener): ([(CheckedContinuation<Reply, any Error>, Any)], [Any], (@Sendable (Any) -> Void)?) =
            lock.withLock {
                buffer.append(chunk)
                var messages: [Any] = []
                while buffer.count >= 4 {
                    let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
                    guard buffer.count >= 4 + length else { break }
                    let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length)
                    buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + 4 + length)
                    if let message = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
                        messages.append(message)
                    }
                }
                var handed: [(CheckedContinuation<Reply, any Error>, Any)] = []
                for message in messages where !waiters.isEmpty {
                    handed.append((waiters.removeFirst(), message))
                }
                return (handed, Array(messages.dropFirst(handed.count)), _onMessage)
            }
        for (continuation, message) in handed { continuation.resume(returning: Reply(message: message)) }
        for message in rest { listener?(message) }
    }

    private func finish() {
        let (pending, exit) = lock.withLock {
            defer {
                waiters = []
                _onExit = nil
            }
            return (waiters, _onExit)
        }
        for waiter in pending { waiter.resume(throwing: ExtensionNative.Refused(why: "Native host has exited.")) }
        exit?()
    }
}
