//
//  AgentTask.swift
//  Luna
//
//  One thing the agent panel was asked to do: what it is called, what it is
//  doing now, and the conversation so far — the user's messages, the agent's
//  own words and each step it took in Luna. Built from `AgentStream`'s events
//  as they arrive; drawn by `AgentPanelView`.
//

import Foundation
import LunaControl

@MainActor
final class AgentTask: Identifiable {

    enum Status: Equatable {
        /// Claude Code is starting, or a turn has begun and nothing has come back.
        case starting
        case thinking
        case working
        /// The turn is over and the agent is waiting for the user.
        case done
        case stopped
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .starting, .thinking, .working: true
            case .done, .stopped, .failed: false
            }
        }
    }

    enum StepState: Equatable { case running, done, failed }

    enum Item: Equatable, Identifiable {
        case user(id: UUID, text: String)
        /// The agent's words. `writing` while they are still arriving.
        case text(id: UUID, text: String, writing: Bool)
        case step(id: String, title: String, symbol: String, state: StepState)
        /// Something gone wrong that is not the agent's to say.
        case note(id: UUID, text: String)

        var id: String {
            switch self {
            case let .user(id, _), let .text(id, _, _), let .note(id, _): id.uuidString
            case let .step(id, _, _, _): id
            }
        }
    }

    /// The Claude Code session, and Luna Control's name for this agent.
    let id: UUID
    /// What runs it, for good: a conversation cannot move between models.
    let engine: AgentEngine
    /// Codex's own id for the conversation, from its first turn, which the
    /// next turn resumes. Claude Code takes Luna's id instead.
    private(set) var thread: String?
    /// What the user asked for, until the agent names the task (`name_task`).
    private(set) var title: String
    private(set) var items: [Item] = []
    private(set) var status: Status = .starting
    /// When the turn that is running began, for "Working for 13 s".
    private(set) var turnStartedAt = Date()
    /// How long the last turn took, once it is over.
    private(set) var lastTurn: TimeInterval?
    let createdAt = Date()
    var onChange: (() -> Void)?

    init(id: UUID, prompt: String, engine: AgentEngine = .claude) {
        self.id = id
        self.engine = engine
        title = Self.provisionalTitle(for: prompt)
        items = [.user(id: UUID(), text: prompt)]
    }

    /// The first few words of the request, until the agent says what the task is.
    static func provisionalTitle(for prompt: String) -> String {
        let words = prompt.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
        return words.count < prompt.count ? words + "…" : words
    }

    func named(_ title: String) {
        guard title != self.title else { return }
        self.title = title
        onChange?()
    }

    /// The engine said which conversation this is. Codex's id is the one
    /// the next turn resumes.
    func began(thread: String) {
        if engine == .codex { self.thread = thread }
    }

    /// The user wrote again. A new turn, unless one is running, in which case
    /// the agent reads it before its next step.
    func userWrote(_ text: String) {
        items.append(.user(id: UUID(), text: text))
        if !status.isRunning { beginTurn() }
        onChange?()
    }

    func beginTurn() {
        status = .starting
        turnStartedAt = Date()
        lastTurn = nil
    }

    func stopped() {
        guard status.isRunning else { return }
        finishWriting()
        settleSteps(as: .failed)
        status = .stopped
        lastTurn = Date().timeIntervalSince(turnStartedAt)
        onChange?()
    }

    func failed(_ message: String) {
        finishWriting()
        settleSteps(as: .failed)
        items.append(.note(id: UUID(), text: message))
        status = .failed(message)
        lastTurn = Date().timeIntervalSince(turnStartedAt)
        onChange?()
    }

    // MARK: - Reading the stream

    func apply(_ event: AgentStream.Event) {
        // A stopped turn's last words, and its result, arrive after Stop.
        // The user has already been told it stopped.
        guard status != .stopped else { return }
        switch event {
        case .started, .retrying:
            return
        case .thinking:
            if status.isRunning { status = .thinking }
        case .textBegan:
            status = .working
            items.append(.text(id: UUID(), text: "", writing: true))
        case let .text(piece):
            status = .working
            appendToDraft(piece)
        case let .textEnded(text):
            endDraft(with: text)
        case let .toolStarted(id, name, input):
            status = .working
            startStep(id: id, name: name, input: input)
        case let .toolFinished(id, failed):
            settleStep(id, as: failed ? .failed : .done)
        case let .finished(failed, message):
            finishTurn(failed: failed, message: message)
        }
        onChange?()
    }

    private func appendToDraft(_ piece: String) {
        guard case let .text(id, text, true)? = items.last else {
            items.append(.text(id: UUID(), text: piece, writing: true))
            return
        }
        items[items.count - 1] = .text(id: id, text: text + piece, writing: true)
    }

    /// The paragraph as it ended replaces the draft it was written into,
    /// wherever that is: a step can land between the last piece of text and
    /// the whole message.
    private func endDraft(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = items.lastIndex { if case .text(_, _, true) = $0 { true } else { false } }
        if let draft, case let .text(id, _, _) = items[draft] {
            if trimmed.isEmpty {
                items.remove(at: draft)
            } else {
                items[draft] = .text(id: id, text: trimmed, writing: false)
            }
        } else if !trimmed.isEmpty {
            items.append(.text(id: UUID(), text: trimmed, writing: false))
        }
    }

    private func finishWriting() {
        guard case let .text(id, text, true)? = items.last else { return }
        items[items.count - 1] = .text(id: id, text: text, writing: false)
    }

    static let unshownTools: Set<String> = ["ToolSearch"]

    private func startStep(id: String, name: String, input: [String: JSONValue]) {
        // Naming the task is not a step the user needs to read: the title
        // above the conversation changes instead.
        if AgentStream.lunaTool(name) == "name_task" {
            if let title = input["title"]?.string { self.title = title }
            return
        }
        // Claude Code's own housekeeping, which means nothing to the user.
        guard !Self.unshownTools.contains(name) else { return }
        let step = AgentSteps.describe(name: name, input: input)
        items.append(.step(id: id, title: step.title, symbol: step.symbol, state: .running))
    }

    private func settleStep(_ id: String, as state: StepState) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case let .step(_, title, symbol, _) = items[index] else { return }
        items[index] = .step(id: id, title: title, symbol: symbol, state: state)
    }

    private func settleSteps(as state: StepState) {
        for (index, item) in items.enumerated() {
            if case let .step(id, title, symbol, .running) = item {
                items[index] = .step(id: id, title: title, symbol: symbol, state: state)
            }
        }
    }

    private func finishTurn(failed: Bool, message: String?) {
        finishWriting()
        lastTurn = Date().timeIntervalSince(turnStartedAt)
        guard failed else {
            settleSteps(as: .done)
            status = .done
            return
        }
        settleSteps(as: .failed)
        let text = AgentSteps.explain(message, engine: engine)
        items.append(.note(id: UUID(), text: text))
        status = .failed(text)
    }
}
