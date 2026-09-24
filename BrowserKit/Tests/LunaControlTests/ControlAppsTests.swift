import Foundation
@testable import LunaControl
import Testing

/// Connecting an app edits a file the user owns, so the edit must keep
/// everything else in it, keep a backup, and be safe to repeat. Every test
/// runs against a temporary home, never the real one.
@Suite("Luna Control apps")
struct ControlAppsTests {

    private let home = URL.temporaryDirectory.appending(path: "luna-apps-\(UUID().uuidString)")
    private let helper = URL(filePath: "/Applications/Luna.app/Contents/MacOS/luna-control")

    private func app(_ id: String) throws -> ControlApp {
        try #require(ControlApp.all.first { $0.id == id })
    }

    private func write(_ text: String, to app: ControlApp) throws {
        let url = app.config(in: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ app: ControlApp) throws -> String {
        try String(contentsOf: app.config(in: home), encoding: .utf8)
    }

    private func json(_ app: ControlApp) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(read(app).utf8)) as? [String: Any])
    }

    @Test func jsonConnectKeepsOtherServersAndSettings() throws {
        let cursor = try app("cursor")
        try write(#"{"theme": "dark", "mcpServers": {"other": {"command": "/bin/other"}}}"#, to: cursor)
        try cursor.connect(home: home, helper: helper)
        let root = try json(cursor)
        #expect(root["theme"] as? String == "dark")
        let servers = try #require(root["mcpServers"] as? [String: Any])
        #expect((servers["other"] as? [String: Any])?["command"] as? String == "/bin/other")
        let luna = try #require(servers["luna"] as? [String: Any])
        #expect(luna["command"] as? String == helper.path(percentEncoded: false))
        #expect(luna["type"] as? String == "stdio")
        #expect(cursor.isConnected(home: home))
    }

    @Test func jsonConnectCreatesAMissingFileAndItsFolder() throws {
        let desktop = try app("claude-desktop")
        #expect(!desktop.isConnected(home: home))
        try desktop.connect(home: home, helper: helper)
        let servers = try #require(try json(desktop)["mcpServers"] as? [String: Any])
        #expect((servers["luna"] as? [String: Any])?["type"] == nil, "Claude Desktop's entry has no type")
        #expect(!FileManager.default.fileExists(atPath: desktop.config(in: home).path + ".luna-backup"))
    }

    @Test func vsCodeUsesItsOwnKey() throws {
        let code = try app("vscode")
        try code.connect(home: home, helper: helper)
        #expect(try json(code)["servers"] is [String: Any])
        #expect(try json(code)["mcpServers"] == nil)
    }

    @Test func connectBacksUpTheFileAsItWas() throws {
        let cursor = try app("cursor")
        let original = #"{"mcpServers": {"other": {"command": "/bin/other"}}}"#
        try write(original, to: cursor)
        try cursor.connect(home: home, helper: helper)
        let backup = cursor.config(in: home).appendingPathExtension("luna-backup")
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
    }

    @Test func connectAndDisconnectAreIdempotent() throws {
        let cursor = try app("cursor")
        try write(#"{"mcpServers": {"other": {"command": "/bin/other"}}}"#, to: cursor)
        try cursor.connect(home: home, helper: helper)
        let once = try read(cursor)
        try cursor.connect(home: home, helper: helper)
        #expect(try read(cursor) == once)

        try cursor.disconnect(home: home)
        let servers = try #require(try json(cursor)["mcpServers"] as? [String: Any])
        #expect(Array(servers.keys) == ["other"])
        let after = try read(cursor)
        try cursor.disconnect(home: home)
        #expect(try read(cursor) == after)
        #expect(!cursor.isConnected(home: home))
    }

    @Test func jsonWithCommentsIsRefusedAndLeftAlone() throws {
        let code = try app("vscode")
        let original = "{\n  // mine\n  \"servers\": {}\n}\n"
        try write(original, to: code)
        #expect(throws: ControlApp.EditError.self) { try code.connect(home: home, helper: helper) }
        #expect(try read(code) == original)
    }

    @Test func tomlConnectKeepsEverythingElse() throws {
        let codex = try app("codex")
        let original = """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/bin/other"

        [mcp_servers.other.env]
        KEY = "value"

        """
        try write(original, to: codex)
        try codex.connect(home: home, helper: helper)
        #expect(try read(codex) == original + """

        [mcp_servers.luna]
        command = "/Applications/Luna.app/Contents/MacOS/luna-control"

        """)
        #expect(codex.isConnected(home: home))
    }

    @Test func tomlConnectReplacesAnOldEntryAndDisconnectRemovesItsSubtables() throws {
        let codex = try app("codex")
        try write("""
        model = "gpt-5"

        [mcp_servers."luna"]
        command = "/old/luna-control"

        [mcp_servers.luna.env]
        A = "b"

        [mcp_servers.other]
        command = "/bin/other"
        """, to: codex)
        try codex.connect(home: home, helper: helper)
        try codex.connect(home: home, helper: helper)
        let text = try read(codex)
        #expect(!text.contains("/old/luna-control"))
        #expect(!text.contains("A = \"b\""))
        #expect(text.components(separatedBy: "[mcp_servers.luna]").count == 2)

        try codex.disconnect(home: home)
        #expect(try read(codex) == """
        model = "gpt-5"

        [mcp_servers.other]
        command = "/bin/other"

        """)
        #expect(!codex.isConnected(home: home))
    }

    @Test func claudeCodeIsACommandAndReadsItsUserScope() throws {
        let claude = try app("claude-code")
        #expect(claude.command(connecting: true, helper: helper)
            == "claude mcp add --scope user luna -- /Applications/Luna.app/Contents/MacOS/luna-control")
        #expect(claude.command(connecting: true, helper: URL(filePath: "/Users/a b/Luna.app/luna-control"))
            == "claude mcp add --scope user luna -- '/Users/a b/Luna.app/luna-control'")
        #expect(claude.command(connecting: false, helper: helper) == "claude mcp remove luna --scope user")
        #expect(throws: ControlApp.EditError.self) { try claude.connect(home: home, helper: helper) }

        try write(#"{"projects": {"/x": {"mcpServers": {"luna": {}}}}}"#, to: claude)
        #expect(!claude.isConnected(home: home), "a project-scoped entry is not the user scope")
        try write(#"{"mcpServers": {"luna": {"command": "x"}}}"#, to: claude)
        #expect(claude.isConnected(home: home))
    }

    @Test func installedMeansAnyMarkerExists() throws {
        let codex = try app("codex")
        let bare = ControlApp(
            id: codex.id, name: codex.name, configPath: codex.configPath, format: codex.format,
            markers: [".codex"], clientNames: [], needsRestart: true
        )
        #expect(!bare.isInstalled(home: home))
        try FileManager.default.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
        #expect(bare.isInstalled(home: home))
    }

    @Test func liveClientsAreMatchedByName() throws {
        #expect(try app("claude-code").matches(clientName: "claude-code"))
        #expect(try app("codex").matches(clientName: "codex-mcp-client"))
        #expect(try app("vscode").matches(clientName: "Visual Studio Code - Insiders"))
        #expect(try !app("claude-desktop").matches(clientName: "claude-code"))
    }
}
