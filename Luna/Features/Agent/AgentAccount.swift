//
//  AgentAccount.swift
//  Luna
//
//  Whether the agent's engine is signed in, and signing it in from the panel
//  instead of a terminal. Both tools have a browser sign-in of their own —
//  `claude auth login`, `codex login` — that opens the account's page and
//  waits on a local port for it to hand the account back; Luna runs that in
//  the background and watches it end. Nothing about the account passes
//  through Luna: the tool keeps its own credentials, as it does when the user
//  signs in from a terminal.
//

import AppKit

@MainActor
final class AgentAccount {

    enum State: Equatable {
        /// Not asked yet, or being asked.
        case unknown
        case signedIn
        case signedOut
        /// The tool's sign-in is running, waiting for the browser. `page` is
        /// the address it printed, to open again if the browser lost it.
        case signingIn(page: URL?)
    }

    let engine: AgentEngine
    private(set) var state: State = .unknown { didSet { if state != oldValue { onChange?() } } }
    var onChange: (() -> Void)?

    private var signIn: Process?
    private var checking = false

    init(engine: AgentEngine) {
        self.engine = engine
    }

    /// Asks the tool whether it is signed in, unless it is busy signing in.
    func check() {
        guard !checking, signIn == nil, let executable = engine.executable else { return }
        checking = true
        let engine = engine
        Task {
            let answer = await Self.run(executable, arguments: engine.statusArguments)
            checking = false
            guard signIn == nil else { return }
            state = engine.isSignedIn(status: answer.status, output: answer.output) ? .signedIn : .signedOut
        }
    }

    /// The agent said the account is not good any more.
    func lost() {
        guard signIn == nil else { return }
        state = .signedOut
    }

    /// Starts the tool's browser sign-in. The tool opens the page itself.
    func startSignIn() {
        guard signIn == nil, let executable = engine.executable else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = engine.signInArguments
        process.environment = AgentRunner.environment(for: executable)
        process.currentDirectoryURL = AgentRunner.workingDirectory
        // Held open: Claude Code offers to read a pasted code from it, and
        // standard input at its end reads as the user giving up.
        process.standardInput = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(bytes: handle.availableData, encoding: .utf8) ?? ""
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.read(text) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(process) } }
        }
        do {
            try process.run()
            signIn = process
            state = .signingIn(page: nil)
        } catch {
            state = .signedOut
        }
    }

    func signOut() {
        guard signIn == nil, let executable = engine.executable else { return }
        let arguments = engine.signOutArguments
        state = .unknown
        Task {
            _ = await Self.run(executable, arguments: arguments)
            check()
        }
    }

    func cancelSignIn() {
        guard let signIn else { return }
        self.signIn = nil
        (signIn.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        signIn.terminate()
        state = .signedOut
    }

    /// Opens the sign-in page again, in the browser the user is looking at.
    func reopenPage() {
        guard case let .signingIn(page?) = state else { return }
        NSWorkspace.shared.open(page)
    }

    private func read(_ text: String) {
        guard case .signingIn(nil) = state, let page = Self.page(in: text) else { return }
        state = .signingIn(page: page)
    }

    private func ended(_ process: Process) {
        guard signIn === process else { return }
        signIn = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        state = .unknown
        check()
    }

    /// The first web address in what the tool printed: its sign-in page.
    nonisolated static func page(in text: String) -> URL? {
        let pattern = #/https:\/\/[^\s"'<>]+/#
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return URL(string: String(match.output))
    }

    /// Runs a short command and returns its exit status and everything it
    /// printed, both streams together: Codex answers on standard error.
    private static func run(_ executable: URL, arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = AgentRunner.environment(for: executable)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { process in
                let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? ""))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, ""))
            }
        }
    }
}
