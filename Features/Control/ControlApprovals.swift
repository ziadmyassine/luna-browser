//
//  ControlApprovals.swift
//  Luna
//
//  Luna Control's calls that wait for the user (docs/LUNA-CONTROL.md,
//  Security). Each is a continuation the call is suspended on until the user
//  answers in the folder's approval card, the client is stopped, or five
//  minutes pass.
//
//  Asking never takes the user's window: the folder's icon changes and the
//  Dock icon bounces once, and the card opens only when the user clicks the
//  folder. Nothing here makes a window key or activates the app.
//

import AppKit

@MainActor
final class ControlApprovals {

    struct Request: Identifiable, Equatable {
        let id = UUID()
        /// The client's display name, which is also its folder's.
        var client: String
        var folder: UUID?
        var site: String?
        /// What the call will do, from `ControlAudit.summary`.
        var summary: String
        var reason: String
        /// Whether "allow on this site" is offered beside "allow once".
        var grantable: Bool
    }

    enum Answer: Equatable {
        case once, always, deny, timedOut, stopped
    }

    /// Posted on the main actor whenever a request arrives or is answered.
    static let didChange = Notification.Name("ControlApprovals.didChange")

    /// Long enough to come back from another app; short enough that an agent
    /// left waiting overnight does not act on a page the user forgot about.
    static let timeout: Duration = .seconds(300)

    /// The service's, to repaint the folders' marks.
    var onChange: (() -> Void)?

    private(set) var pending: [Request] = []
    private var waiting: [UUID: CheckedContinuation<Answer, Never>] = [:]

    func pending(inFolder folder: UUID) -> [Request] {
        pending.filter { $0.folder == folder }
    }

    /// Suspends until the request is answered. Cancelling the calling task
    /// answers it `.stopped`.
    func ask(_ request: Request) async -> Answer {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.answer(request.id, .timedOut)
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancelled before it was queued: the handler below already
                // ran and found nothing to answer.
                guard !Task.isCancelled else { return continuation.resume(returning: .stopped) }
                pending.append(request)
                waiting[request.id] = continuation
                changed()
                // Once per burst, not per request: a bounce says "look at
                // Luna", and a second one says nothing more.
                if pending.count == 1 { _ = NSApp.requestUserAttention(.informationalRequest) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.answer(request.id, .stopped) }
        }
    }

    func answer(_ id: UUID, _ answer: Answer) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        pending.removeAll { $0.id == id }
        changed()
        continuation.resume(returning: answer)
    }

    /// Ends every request from `client`, or from everyone when nil.
    func cancel(client: String?) {
        for request in pending where client == nil || request.client == client {
            answer(request.id, .stopped)
        }
    }

    private func changed() {
        onChange?()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
