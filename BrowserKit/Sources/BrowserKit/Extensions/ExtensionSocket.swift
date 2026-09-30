import Foundation
import WebKit

// Adapted from Search's ExtensionSocket.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// A WebSocket for an extension's worker.
///
/// WebKit runs an extension's service worker on its web process's main thread,
/// and a worker's WebSocket waits there, synchronously, for the main thread to
/// set up its channel: the worker waits on itself for ever, and every page of
/// the extension freezes with it. 1Password opens one the moment a sign-in
/// succeeds. So in a worker the shim's WebSocket is made here, with
/// URLSession, and its frames carried over a native port: text as it is,
/// binary as base64. The Origin and user agent are the ones Chrome would send.
@MainActor
enum ExtensionSocket {

    /// The native application the shim connects to for a socket.
    static let name = ExtensionShim.application + ".socket"

    /// One session for every socket; each task has its connection as its own delegate.
    private static let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
    /// Held from the port's opening until either end lets go.
    private static var open: [ObjectIdentifier: Connection] = [:]

    static func connect(_ port: WKWebExtension.MessagePort, from extensionID: String) {
        let connection = Connection(port: port, origin: String(ExtensionNative.origin(of: extensionID).dropLast()))
        let key = ObjectIdentifier(connection)
        open[key] = connection
        connection.onEnd = { open[key] = nil }
    }

    @MainActor
    final class Connection: NSObject, URLSessionWebSocketDelegate {
        private let port: WKWebExtension.MessagePort
        private let origin: String
        private var task: URLSessionWebSocketTask?
        private var ended = false
        var onEnd: (() -> Void)?

        init(port: WKWebExtension.MessagePort, origin: String) {
            self.port = port
            self.origin = origin
            super.init()
            port.messageHandler = { [weak self] message, _ in
                nonisolated(unsafe) let message = message
                MainActor.assumeIsolated { self?.take(message) }
            }
            port.disconnectHandler = { [weak self] _ in
                MainActor.assumeIsolated { self?.end(tellingPort: false) }
            }
            // WebKit loses what is posted on a port a worker has only just
            // opened; the shim takes this for the sign that this one arrived.
            post(["ready": true])
        }

        private func take(_ message: Any?) {
            guard let message = message as? [String: Any] else { return }
            // The shim asks every port to an app whether it has arrived before
            // sending on it (see `ExtensionNative`): this one answers too, so
            // the socket is never held waiting.
            if let word = message[ExtensionShim.nativeKey] {
                if (word as? String) == "here?" { post([ExtensionShim.nativeKey: "here"]) }
                return
            }
            if let address = message["open"] as? String {
                // Said again now the worker is surely listening: the first one,
                // sent as the port opened, is often lost. The worker says
                // "open" until it hears back, so a repeat is only answered.
                post(["ready": true])
                guard task == nil else { return }
                start(address, protocols: message["protocols"] as? [String] ?? [], userAgent: message["userAgent"] as? String)
            } else if let text = message["send"] as? String {
                task?.send(.string(text)) { _ in }
            } else if let encoded = message["sendBinary"] as? String, let data = Data(base64Encoded: encoded) {
                task?.send(.data(data)) { _ in }
            } else if message["close"] != nil {
                let code = (message["close"] as? Int).flatMap(URLSessionWebSocketTask.CloseCode.init(rawValue:)) ?? .normalClosure
                task?.cancel(with: code, reason: (message["reason"] as? String).map { Data($0.utf8) })
            }
        }

        private func start(_ address: String, protocols: [String], userAgent: String?) {
            guard task == nil, let url = URL(string: address), ["ws", "wss"].contains(url.scheme?.lowercased()) else {
                return fail()
            }
            var request = URLRequest(url: url)
            request.setValue(origin, forHTTPHeaderField: "Origin")
            if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
            if !protocols.isEmpty {
                request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }
            let task = ExtensionSocket.session.webSocketTask(with: request)
            task.delegate = self
            self.task = task
            task.resume()
        }

        /// Frames as they come until the socket ends; how it ended is the
        /// delegate's to say.
        private func receive(from task: URLSessionWebSocketTask) {
            Task { [weak self] in
                while let message = try? await task.receive() {
                    guard let self, !ended else { return }
                    switch message {
                    case .string(let text): post(["text": text])
                    case .data(let data): post(["binary": data.base64EncodedString()])
                    @unknown default: break
                    }
                }
            }
        }

        private func post(_ message: [String: Any]) {
            guard !port.isDisconnected else { return }
            port.sendMessage(message, completionHandler: nil)
        }

        private func fail() {
            post(["failed": true])
            post(["closed": 1006, "reason": "", "clean": false])
            end(tellingPort: true)
        }

        private func end(tellingPort: Bool) {
            guard !ended else { return }
            ended = true
            task?.cancel(with: .goingAway, reason: nil)
            if tellingPort, !port.isDisconnected { port.disconnect() }
            onEnd?()
        }

        nonisolated func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol chosen: String?
        ) {
            MainActor.assumeIsolated {
                post(["opened": chosen ?? ""])
                receive(from: webSocketTask)
            }
        }

        nonisolated func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            MainActor.assumeIsolated {
                let text = reason.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
                post(["closed": closeCode.rawValue, "reason": text, "clean": true])
                end(tellingPort: true)
            }
        }

        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let failed = error != nil
            MainActor.assumeIsolated {
                guard !ended else { return }
                if failed { return fail() }
                post(["closed": 1005, "reason": "", "clean": true])
                end(tellingPort: true)
            }
        }
    }
}
