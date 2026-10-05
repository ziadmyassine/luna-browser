//
//  AgentCenter.swift
//  Luna
//
//  The agent panel's tasks, app-wide: the one on show, the ones before it,
//  the process behind the one that is live, and whether the engine it runs on
//  is signed in. Every window's panel shows the same task, the way every
//  window shows the same sidebar.
//
//  One live process at a time. Going back to an earlier task from History
//  and writing to it resumes its conversation, so a task is never lost, only
//  asleep.
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
    private var runner: (any AgentProcess)?
    private var runnerTask: UUID?
    /// What the user wrote while a Codex turn ran, for the turn after it.
    private var waiting: [String] = []
    private var accounts: [AgentEngine: AgentAccount] = [:]
    private var nameWatch: (any NSObjectProtocol)?

    /// Why the agent cannot start, or nil when it can.
    enum Blocker: Equatable {
        /// Luna Control is off, and it is the agent's hands.
        case controlOff
        /// The engine's tool is not installed where its installers put it.
        case notInstalled(AgentEngine)
        case signedOut(AgentEngine)
        /// Its browser sign-in is running.
        case signingIn(AgentEngine, page: URL?)
    }

    /// The engine the panel is about: the task's own, or the one new tasks get.
    var engine: AgentEngine { current?.engine ?? AgentEngine.chosen }

    var blocker: Blocker? {
        if !ControlService.isEnabled { return .controlOff }
        let engine = engine
        if engine.executable == nil { return .notInstalled(engine) }
        switch account(for: engine).state {
        case .signedOut: return .signedOut(engine)
        case let .signingIn(page): return .signingIn(engine, page: page)
        case .signedIn, .unknown: return nil
        }
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

    func account(for engine: AgentEngine) -> AgentAccount {
        if let account = accounts[engine] { return account }
        let account = AgentAccount(engine: engine)
        account.onChange = { [weak self] in self?.changed() }
        accounts[engine] = account
        return account
    }

    // MARK: - Signing in

    /// Asks the engine whether it is signed in, as the panel opens: a
    /// signed-out tool is better found now than as the first task fails.
    func checkAccount() {
        guard engine.executable != nil else { return }
        account(for: engine).check()
    }

    /// Both engines, for the settings page, which shows them side by side.
    func checkAccounts() {
        for engine in AgentEngine.allCases where engine.executable != nil { account(for: engine).check() }
    }

    func signIn() { account(for: engine).startSignIn() }
    func cancelSignIn() { account(for: engine).cancelSignIn() }
    func reopenSignInPage() { account(for: engine).reopenPage() }

    /// The engine new tasks run on.
    func use(_ engine: AgentEngine) {
        AgentEngine.chosen = engine
        // A task belongs to its engine, so a new one starts.
        if current?.engine != engine { current = nil }
        checkAccount()
        changed()
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
            if runner.takesMessagesWhileWorking {
                runner.send(text, now: running)
            } else {
                waiting.append(text)
            }
        } else {
            launch(for: current, prompt: text, resuming: true)
        }
    }

    /// Stops what the agent is doing. The task stays, and can be told more.
    func stop() {
        guard let current, current.status.isRunning else { return }
        if runnerTask == current.id {
            waiting.removeAll()
            runner?.interrupt()
        }
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
        let task = AgentTask(id: UUID(), prompt: prompt, engine: AgentEngine.chosen)
        task.onChange = { [weak self] in self?.changed() }
        tasks.insert(task, at: 0)
        current = task
        // Before the agent's first call: its folder is Astro's, named from
        // the request until the agent names the task.
        ControlService.astroTasks[task.id.uuidString.lowercased()] = task.title
        launch(for: task, prompt: prompt, resuming: false)
    }

    private func launch(for task: AgentTask, prompt: String, resuming: Bool) {
        runner?.terminate()
        waiting.removeAll()
        guard let executable = task.engine.executable else {
            return task.failed(String(localized: "\(task.engine.toolName) is not installed. \(task.engine.installHint)"))
        }
        let runner: any AgentProcess = switch task.engine {
        case .claude: AgentRunner(executable: executable, session: task.id, resuming: resuming)
        case .codex: AgentCodexRunner(executable: executable, task: task.id, thread: resuming ? task.thread : nil)
        }
        runner.onEvent = { [weak task] event in
            if case let .started(thread) = event { task?.began(thread: thread) }
            task?.apply(event)
        }
        runner.onExit = { [weak self, weak task] status, detail in
            guard let self, let task, self.runnerTask == task.id else { return }
            self.ended(task, status: status, detail: detail)
        }
        self.runner = runner
        runnerTask = task.id
        task.beginTurn()
        do {
            try runner.start(with: prompt)
        } catch {
            self.runner = nil
            runnerTask = nil
            task.failed(String(localized: "\(task.engine.toolName) could not start: \(error.localizedDescription)"))
        }
        changed()
    }

    private func ended(_ task: AgentTask, status: Int32, detail: String) {
        runner = nil
        runnerTask = nil
        if task.status.isRunning {
            let message = detail.isEmpty ? String(localized: "\(task.engine.toolName) stopped (\(status)).") : detail
            task.failed(AgentSteps.explain(message, engine: task.engine))
        }
        if case let .failed(message) = task.status, AgentEngine.meansSignedOut(message) || AgentEngine.meansSignedOut(detail) {
            account(for: task.engine).lost()
        }
        // A Codex turn is one process; what came in during it is the next.
        guard !waiting.isEmpty, task.status == .done else { return }
        let next = waiting.joined(separator: "\n\n")
        waiting.removeAll()
        launch(for: task, prompt: next, resuming: true)
    }

    /// Ends the live process, when Luna quits.
    func shutDown() {
        runner?.terminate()
        runner = nil
        runnerTask = nil
        for account in accounts.values { account.cancelSignIn() }
    }

    private func taskNamed(session: String?, title: String?) {
        guard let session, let title,
              let task = tasks.first(where: { $0.id.uuidString.lowercased() == session.lowercased() }) else { return }
        task.named(title)
    }

    private func changed() {
        let working = tasks.filter(\.status.isRunning).map { $0.id.uuidString.lowercased() }
        ControlService.current?.setAstroWorking(Set(working))
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
