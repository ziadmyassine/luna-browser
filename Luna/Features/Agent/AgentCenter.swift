//
//  AgentCenter.swift
//  Luna
//
//  The agent panel's tasks, app-wide: the one on show, the ones before it,
//  and the Claude Code process behind the one that is live. Every window's
//  panel shows the same task, the way every window shows the same sidebar.
//
//  One live process at a time. Going back to an earlier task from History
//  and writing to it resumes its session (`claude --resume`), so a task is
//  never lost, only asleep.
//

import AppKit
import LunaControl

@MainActor
final class AgentCenter {

    static let shared = AgentCenter()

    /// Posted on the main actor whenever anything the panel draws changed.
    static let didChange = Notification.Name("AgentCenter.didChange")

    /// Every task this launch, newest first.
    private(set) var tasks: [AgentTask] = []
    /// The task on show, or nil for a fresh panel waiting for its first message.
    private(set) var current: AgentTask?
    private var runner: AgentRunner?
    private var runnerTask: UUID?
    private var nameWatch: (any NSObjectProtocol)?

    /// Why the agent cannot start, or nil when it can.
    enum Blocker: Equatable {
        /// Luna Control is off, and it is the agent's hands.
        case controlOff
        /// Claude Code is not installed where its installers put it.
        case noClaudeCode
    }

    var blocker: Blocker? {
        if !ControlService.isEnabled { return .controlOff }
        if AgentRunner.executable == nil { return .noClaudeCode }
        return nil
    }

    private init() {
        nameWatch = NotificationCenter.default.addObserver(
            forName: ControlService.taskNamed, object: nil, queue: .main
        ) { [weak self] note in
            let session = note.userInfo?["session"] as? String
            let title = note.userInfo?["title"] as? String
            MainActor.assumeIsolated { self?.taskNamed(session: session, title: title) }
        }
    }

    // MARK: - What the user does

    /// A message from the composer: the first of a new task, or more for the
    /// one on show.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, blocker == nil else { return }
        guard let current else { return start(text) }
        let running = current.status.isRunning
        current.userWrote(text)
        if runnerTask == current.id, let runner, runner.isRunning {
            runner.send(text, now: running)
        } else {
            launch(for: current, prompt: text, resuming: true)
        }
    }

    /// Stops what the agent is doing. The task stays, and can be told more.
    func stop() {
        guard let current, current.status.isRunning else { return }
        if runnerTask == current.id { runner?.interrupt() }
        current.stopped()
    }

    /// A clean panel for the next task. The one on show goes to History.
    func newTask() {
        current = nil
        changed()
    }

    /// Back to an earlier task, from History.
    func show(_ task: AgentTask) {
        current = task
        changed()
    }

    /// Turns Luna Control on, for the panel's own button. The user pressing
    /// it is the consent the setting asks for.
    func turnOnControl() {
        UserDefaults.standard.set(true, forKey: ControlService.enabledKey)
        ControlService.current?.update()
        changed()
    }

    // MARK: - The process

    private func start(_ prompt: String) {
        let task = AgentTask(id: UUID(), prompt: prompt)
        task.onChange = { [weak self] in self?.changed() }
        tasks.insert(task, at: 0)
        current = task
        launch(for: task, prompt: prompt, resuming: false)
    }

    private func launch(for task: AgentTask, prompt: String, resuming: Bool) {
        runner?.terminate()
        guard let executable = AgentRunner.executable else {
            return task.failed(String(localized: "Claude Code is not installed. Install it from claude.com/code, then try again."))
        }
        let runner = AgentRunner(executable: executable, session: task.id, resuming: resuming)
        runner.onEvent = { [weak task] event in task?.apply(event) }
        runner.onExit = { [weak self, weak task] status, detail in
            guard let self, let task, self.runnerTask == task.id else { return }
            self.runner = nil
            self.runnerTask = nil
            if task.status.isRunning {
                task.failed(AgentSteps.explain(detail.isEmpty ? String(localized: "Claude Code stopped (\(status)).") : detail))
            }
        }
        self.runner = runner
        runnerTask = task.id
        task.beginTurn()
        do {
            try runner.start(with: prompt)
        } catch {
            self.runner = nil
            runnerTask = nil
            task.failed(String(localized: "Claude Code could not start: \(error.localizedDescription)"))
        }
        changed()
    }

    /// Ends the live process, when Luna quits.
    func shutDown() {
        runner?.terminate()
        runner = nil
        runnerTask = nil
    }

    private func taskNamed(session: String?, title: String?) {
        guard let session, let title,
              let task = tasks.first(where: { $0.id.uuidString.lowercased() == session.lowercased() }) else { return }
        task.named(title)
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
