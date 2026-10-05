//
//  AgentCodexRunner.swift
//  Luna
//
//  One turn of an agent task on Codex: `codex exec --json`, given the
//  message on standard input, with Luna Control as an MCP server set up on
//  the command line. Unlike Claude Code's stream-json mode, a Codex run is
//  one turn and ends — the next message resumes the thread in a new process
//  (`codex exec resume <thread>`), and a message written while a turn runs
//  waits for it to end (`AgentCenter`). Stop is an interrupt, as Control-C
//  would be.
//
//  The task's id goes to `luna-control` as `CLAUDE_CODE_SESSION_ID`, the
//  variable `ControlSessionTag` reads, so Luna Control files the calls under
//  the panel's task whichever engine makes them.
//

import Foundation
import LunaControl

@MainActor
final class AgentCodexRunner: AgentProcess {

    var onEvent: ((AgentStream.Event) -> Void)?
    var onExit: ((_ status: Int32, _ detail: String) -> Void)?
    var takesMessagesWhileWorking: Bool { false }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var errorTail = Data()

    /// - Parameter thread: Codex's id for the conversation, to carry it on;
    ///   nil starts a new one.
    init(executable: URL, task: UUID, thread: String?) {
        process.executableURL = executable
        process.currentDirectoryURL = AgentRunner.workingDirectory
        process.arguments = Self.arguments(task: task, thread: thread)
        process.environment = AgentRunner.environment(for: executable)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    static func arguments(task: UUID, thread: String?) -> [String] {
        let helper = ControlService.helperURL.path(percentEncoded: false)
        let server = "mcp_servers.\(AgentStream.serverName)"
        let settings = [
            "\(server).command=\(toml(helper))",
            "\(server).env={CLAUDE_CODE_SESSION_ID=\(toml(task.uuidString.lowercased()))}",
            // `exec` never asks, so a tool that would ask is refused instead;
            // Luna Control asks the user itself, in Luna, where it needs to.
            "\(server).default_tools_approval_mode=\"approve\"",
            "developer_instructions=\(toml(AgentRunner.instructions))",
            "web_search=\"live\"",
            // Luna's tools and the web's, as for Claude Code: no shell.
            "features.shell_tool=false"
        ]
        var arguments = ["exec", "--json", "--skip-git-repo-check", "--cd", AgentRunner.workingDirectory.path(percentEncoded: false),
                         "--sandbox", "read-only"]
        for setting in settings { arguments += ["-c", setting] }
        if let thread { arguments += ["resume", thread] }
        return arguments + ["-"]
    }

    /// A TOML basic string, which is how `-c` reads a value.
    static func toml(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }

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
        try? input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try? input.fileHandleForWriting.close()
    }

    var isRunning: Bool { process.isRunning }

    /// Codex reads its message once, at the start; `AgentCenter` holds
    /// anything written later for the next turn.
    func send(_ text: String, now: Bool) {}

    func interrupt() {
        guard process.isRunning else { return }
        process.interrupt()
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(bytes: buffer[buffer.startIndex ..< newline], encoding: .utf8) ?? ""
            buffer.removeSubrange(buffer.startIndex ... newline)
            for event in AgentCodexStream.events(in: line) { onEvent?(event) }
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
