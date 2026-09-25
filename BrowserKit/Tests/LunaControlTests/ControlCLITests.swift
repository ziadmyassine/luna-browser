import Foundation
@testable import LunaControl
import Testing

/// Finding a tool where its installer put it, and running it without a
/// shell. Each test uses a temporary home.
@Suite("Luna Control command-line tools")
struct ControlCLITests {

    private let home = URL.temporaryDirectory.appending(path: "luna-cli-\(UUID().uuidString)")

    private func install(_ tool: String, in folder: String, executable: Bool = true) throws -> URL {
        let url = home.appending(path: folder).appending(path: tool)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho ran \"$@\"\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    @Test func findsTheToolInTheInstallersFolder() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ControlCLI.locate("luna-test-tool", home: home) == nil)
        _ = try install("luna-test-tool", in: ".npm-global/bin", executable: false)
        #expect(ControlCLI.locate("luna-test-tool", home: home) == nil, "a file that cannot run is not the tool")
        let native = try install("luna-test-tool", in: ".local/bin")
        #expect(ControlCLI.locate("luna-test-tool", home: home) == native)
    }

    @Test func runsWithArgumentsAsGiven() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let tool = try install("luna-test-tool", in: ".local/bin")
        let printed = try await ControlCLI.run(tool, arguments: ["mcp", "add", "/Users/a b/luna-control"])
        #expect(printed == "ran mcp add /Users/a b/luna-control\n")
    }

    @Test func aFailureCarriesWhatTheToolSaid() async throws {
        let tool = URL(filePath: "/bin/sh")
        await #expect(throws: ControlCLI.RunError(description: "already exists")) {
            try await ControlCLI.run(tool, arguments: ["-c", "echo already exists >&2; exit 1"])
        }
        await #expect(throws: ControlCLI.RunError(description: "It stopped with status 3.")) {
            try await ControlCLI.run(tool, arguments: ["-c", "exit 3"])
        }
    }
}
