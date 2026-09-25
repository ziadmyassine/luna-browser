import Foundation

/// Finding and running an app's own command-line tool, for the apps whose
/// config only that tool may write (`ControlApp.Format.command`).
///
/// An app started from the Dock or Finder gets launchd's `PATH`, which has
/// none of the folders these tools install into, so the tool is looked for in
/// those folders by name rather than through a shell. A login shell would find
/// it, but would also run the user's shell startup files to do so.
public enum ControlCLI {

    /// Where the tools' installers put them: the native installer's
    /// `~/.local/bin`, Claude Code's older `~/.claude/local`, Homebrew on
    /// Apple silicon and Intel, and npm, Bun and Volta's global folders.
    static func folders(home: URL) -> [URL] {
        [".local/bin", ".claude/local", ".npm-global/bin", ".bun/bin", ".volta/bin"].map { home.appending(path: $0) }
            + ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(filePath: $0) }
    }

    /// The first executable called `tool` in `folders(home:)`, or nil.
    public static func locate(_ tool: String, home: URL) -> URL? {
        folders(home: home)
            .map { $0.appending(path: tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    public struct RunError: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    /// How long a config change may take before it is given up on. `claude
    /// mcp add` measured about a second; a tool that sits longer than this is
    /// waiting on something Luna cannot answer.
    static let timeout: TimeInterval = 30

    /// Runs the tool and returns what it printed. Throws with what it printed
    /// to standard error when it exits non-zero or outlasts `timeout`.
    ///
    /// The tool's own folder goes first on `PATH`: an npm-installed `claude`
    /// is a script that starts with `env node`, and node sits beside it.
    public static func run(_ executable: URL, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let folder = executable.deletingLastPathComponent().path(percentEncoded: false)
        environment["PATH"] = ([folder, "/opt/homebrew/bin", "/usr/local/bin"]
            + (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: RunError(description: error.localizedDescription))
            }
        }
        let printed = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationReason == .uncaughtSignal {
            throw RunError(description: "It didn’t finish within \(Int(timeout)) seconds.")
        }
        guard status == 0 else {
            let said = (String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunError(description: said.isEmpty ? "It stopped with status \(status)." : said)
        }
        return printed
    }
}
