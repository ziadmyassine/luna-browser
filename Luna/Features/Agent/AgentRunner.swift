//
//  AgentRunner.swift
//  Luna
//
//  One agent task's Claude Code: `claude -p` in stream-json mode, kept running
//  for as long as the task is, with Luna Control as its only MCP server. What
//  it prints is read a line at a time (`AgentStream`); what the user types is
//  written to it, and Stop is a control request rather than a kill, so the
//  task can be told more afterwards.
//
//  The session id is Luna's own choice, passed with `--session-id`. Claude Code
//  hands it to `luna-control` as `CLAUDE_CODE_SESSION_ID`, and the helper stamps
//  it on every call (`ControlSessionTag`), which is how Luna Control knows the
//  calls are this panel's.
//

import Foundation
import LunaControl

/// What `AgentCenter` drives, whichever engine is behind it.
@MainActor
protocol AgentProcess: AnyObject {
    var onEvent: ((AgentStream.Event) -> Void)? { get set }
    /// The process ended. `detail` is the end of what it wrote to standard
    /// error, for a run that never got as far as saying anything.
    var onExit: ((_ status: Int32, _ detail: String) -> Void)? { get set }
    var isRunning: Bool { get }
    /// Whether a message can go in while a turn is running.
    var takesMessagesWhileWorking: Bool { get }
    func start(with prompt: String) throws
    func send(_ text: String, now: Bool)
    func interrupt()
    func terminate()
}

@MainActor
final class AgentRunner: AgentProcess {

    var onEvent: ((AgentStream.Event) -> Void)?
    var onExit: ((_ status: Int32, _ detail: String) -> Void)?
    var takesMessagesWhileWorking: Bool { true }

    let session: UUID
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var errorTail = Data()

    /// The agent's working folder: one of Luna's own, so no project's
    /// `CLAUDE.md` or settings ride along into a browsing task.
    static var workingDirectory: URL {
        let folder = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "dev.novapps.luna")
            .appending(path: "Agent", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// What the agent is told beyond Claude Code's own instructions.
    static let instructions = """
    You are Luna's built-in agent, working in the Luna web browser through the Luna Control tools \
    (mcp__luna__*). The user is watching your steps in a panel beside the page and can message you \
    while you work. Before anything else, call name_task with a two-to-four-word name for the task \
    as the user would say it ("Lisbon trip", "Electricity bill") and an emoji that fits it as its icon (✈️, 🧾); \
    Luna names your sidebar folder after it. \
    Open the tabs you need with tab_open; they go into that folder. Once a tab's purpose is clear, call \
    label_tab to give it a one-to-three-word name and an icon ("Flights", airplane, teal). Write to the user in short, plain \
    sentences: say what you are about to do, and finish with the answer or what you found. Passwords, \
    payment details and one-time codes are the user's: use request_user when a step needs one. \
    Do not buy, book, send or delete anything without asking the user first.
    """

    /// - Parameter resuming: carry on the session's earlier conversation
    ///   rather than start it, for a task picked up again from History.
    init(executable: URL, session: UUID = UUID(), resuming: Bool = false) {
        self.session = session
        process.executableURL = executable
        process.currentDirectoryURL = Self.workingDirectory
        process.arguments = Self.arguments(session: session, resuming: resuming)
        process.environment = Self.environment(for: executable)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    static func arguments(session: UUID, resuming: Bool = false) -> [String] {
        let luna: JSONValue = ["command": .string(ControlService.helperURL.path(percentEncoded: false))]
        let server: JSONValue = ["mcpServers": .object([AgentStream.serverName: luna])]
        return [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            resuming ? "--resume" : "--session-id", session.uuidString.lowercased(),
            "--mcp-config", String(data: server.encoded(), encoding: .utf8) ?? "{}",
            "--strict-mcp-config",
            // Luna's tools and the web's: nothing that reads or writes files
            // or runs commands on this Mac, and nothing asks, because there is
            // no terminal to ask in.
            "--allowedTools", "mcp__\(AgentStream.serverName)", "WebSearch", "WebFetch",
            "--permission-mode", "dontAsk",
            "--append-system-prompt", instructions
        ]
    }

    /// Launchd's environment has none of the folders the tool installs into,
    /// and an npm `claude` is a script that starts with `env node`. A Luna
    /// started from inside a Claude Code session must not hand that
    /// session's identity on, or the agent's calls would be filed under it.
    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("CLAUDE_CODE_") && $0.key != "CLAUDECODE"
        }
        let folder = executable.deletingLastPathComponent().path(percentEncoded: false)
        environment["PATH"] = ([folder, "/opt/homebrew/bin", "/usr/local/bin"]
            + (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        return environment
    }

    /// Starts the process and gives it the task.
    ///
    /// Each chunk goes to the main queue in the order it was read: a `Task`
    /// per chunk is not promised to run in order, and two lines of the
    /// agent's answer arriving the other way round is a garbled answer.
    func start(with prompt: String) throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receiveError(data) } }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(status) } }
        }
        try process.run()
        send(prompt, now: false)
    }

    var isRunning: Bool { process.isRunning }

    /// A message from the user. While a turn is running it goes in now, so
    /// the agent reads it before its next step.
    func send(_ text: String, now: Bool) {
        write(AgentStream.userMessage(text, now: now))
    }

    /// Stops the turn that is running. The process stays, for what comes next.
    func interrupt() {
        write(AgentStream.interrupt(id: UUID().uuidString))
    }

    /// Ends the task for good.
    func terminate() {
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }
        process.terminate()
    }

    private func write(_ line: String) {
        guard process.isRunning else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(bytes: buffer[buffer.startIndex ..< newline], encoding: .utf8) ?? ""
            buffer.removeSubrange(buffer.startIndex ... newline)
            for event in AgentStream.events(in: line) { onEvent?(event) }
        }
    }

    private func receiveError(_ data: Data) {
        guard !data.isEmpty else { return }
        errorTail.append(data)
        if errorTail.count > 4096 { errorTail.removeFirst(errorTail.count - 4096) }
    }

    private func ended(_ status: Int32) {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        onExit?(status, (String(bytes: errorTail, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
