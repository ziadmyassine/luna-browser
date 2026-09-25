import Foundation

/// The MCP clients Settings offers to connect, where each keeps its server
/// list, and the edit that adds or removes Luna from it.
///
/// Every path and format below is the app's own documented one
/// (docs/LUNA-CONTROL.md cites each page). An app is only ever written to when
/// the user presses Connect or Disconnect; nothing here runs on its own.
public struct ControlApp: Sendable, Identifiable, Equatable {

    public enum Format: Sendable, Equatable {
        /// A JSON object whose `key` maps server names to entries. `typed`
        /// adds `"type": "stdio"`, which Cursor and VS Code ask for.
        case json(key: String, typed: Bool)
        /// Codex's `[mcp_servers.<name>]` table.
        case toml
        /// Claude Code rewrites `~/.claude.json` itself, constantly, so a
        /// second writer would race it. Its own command makes the change
        /// instead: Luna runs it when it can find the tool (`ControlCLI`),
        /// and the user pastes it into Terminal when it cannot. The file is
        /// only read to show whether that happened. `add` holds `%@` where
        /// the helper's path goes.
        case command(tool: String, add: [String], remove: [String])
    }

    public var id: String
    public var name: String
    /// Relative to the home folder.
    public var configPath: String
    public var format: Format
    /// Any one of these existing means the app is installed: home-relative
    /// paths, or absolute ones for an app bundle.
    public var markers: [String]
    /// Prefixes of the `clientInfo.name` the app sends in `initialize`, for
    /// telling a live connection apart from a configured one.
    public var clientNames: [String]
    /// Whether the app reads its config only at launch.
    public var needsRestart: Bool

    /// The name Luna is listed under in every app's config.
    public static let serverName = "luna"

    public static let all: [ControlApp] = [
        ControlApp(
            id: "claude-code", name: "Claude Code", configPath: ".claude.json",
            format: .command(
                tool: "claude",
                add: ["mcp", "add", "--scope", "user", serverName, "--", "%@"],
                remove: ["mcp", "remove", serverName, "--scope", "user"]
            ),
            markers: [".claude", ".claude.json"], clientNames: ["claude-code"], needsRestart: true
        ),
        ControlApp(
            id: "codex", name: "Codex", configPath: ".codex/config.toml", format: .toml,
            markers: [".codex", "/Applications/Codex.app"], clientNames: ["codex"], needsRestart: true
        ),
        ControlApp(
            id: "cursor", name: "Cursor", configPath: ".cursor/mcp.json",
            format: .json(key: "mcpServers", typed: true),
            markers: [".cursor", "/Applications/Cursor.app"], clientNames: ["cursor"], needsRestart: false
        ),
        ControlApp(
            id: "claude-desktop", name: "Claude Desktop",
            configPath: "Library/Application Support/Claude/claude_desktop_config.json",
            format: .json(key: "mcpServers", typed: false),
            markers: ["Library/Application Support/Claude", "/Applications/Claude.app"],
            clientNames: ["claude-ai"], needsRestart: true
        ),
        ControlApp(
            id: "vscode", name: "VS Code", configPath: "Library/Application Support/Code/User/mcp.json",
            format: .json(key: "servers", typed: true),
            markers: ["Library/Application Support/Code/User", "/Applications/Visual Studio Code.app"],
            clientNames: ["visual studio code"], needsRestart: false
        )
    ]

    public func config(in home: URL) -> URL { home.appending(path: configPath) }

    public func isInstalled(home: URL) -> Bool {
        markers.contains { marker in
            let url = marker.hasPrefix("/") ? URL(filePath: marker) : home.appending(path: marker)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    /// Whether the config names a server called `serverName`. A file that is
    /// missing or unreadable does not.
    public func isConnected(home: URL) -> Bool {
        guard let data = try? Data(contentsOf: config(in: home)) else { return false }
        switch format {
        case let .json(key, _):
            return (try? Self.object(data))?[key].flatMap { $0 as? [String: Any] }?[Self.serverName] != nil
        case .command:
            return (try? Self.object(data))?["mcpServers"].flatMap { $0 as? [String: Any] }?[Self.serverName] != nil
        case .toml:
            return TOMLTables.contains(String(bytes: data, encoding: .utf8) ?? "", table: Self.tomlTable)
        }
    }

    /// Whether a live connection's `clientInfo.name` is this app's.
    public func matches(clientName: String) -> Bool {
        let name = clientName.lowercased()
        return clientNames.contains { name.hasPrefix($0) }
    }

    /// The Terminal command for a `.command` app, nil for the rest.
    public func command(connecting: Bool, helper: URL) -> String? {
        invocation(connecting: connecting, helper: helper).map { tool, arguments in
            ([tool] + arguments).map(Self.shellQuoted).joined(separator: " ")
        }
    }

    /// The same command as a tool name and its arguments, for running it
    /// without a shell.
    public func invocation(connecting: Bool, helper: URL) -> (tool: String, arguments: [String])? {
        guard case let .command(tool, add, remove) = format else { return nil }
        let path = helper.path(percentEncoded: false)
        return (tool, connecting ? add.map { $0 == "%@" ? path : $0 } : remove)
    }

    // MARK: - Editing

    public struct EditError: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    /// Adds Luna to the config, or replaces an entry of the same name, and
    /// leaves every other server and setting as it was. The file as it stood
    /// is copied to `<name>.luna-backup` first.
    public func connect(home: URL, helper: URL) throws {
        try edit(home: home) { text in
            switch format {
            case let .json(key, typed):
                var entry: [String: Any] = ["command": helper.path(percentEncoded: false)]
                if typed { entry["type"] = "stdio" }
                return try Self.editJSON(text, key: key) { $0[Self.serverName] = entry }
            case .toml:
                return TOMLTables.removing(Self.tomlTable, from: text)
                    + "[\(Self.tomlTable)]\ncommand = \(TOMLTables.quoted(helper.path(percentEncoded: false)))\n"
            case .command:
                throw EditError(description: "\(name) is connected from Terminal.")
            }
        }
    }

    /// Removes Luna's entry and nothing else. A config without one is left
    /// untouched, backup and all.
    public func disconnect(home: URL) throws {
        guard isConnected(home: home) else { return }
        try edit(home: home) { text in
            switch format {
            case let .json(key, _):
                return try Self.editJSON(text, key: key) { $0[Self.serverName] = nil }
            case .toml:
                return String(TOMLTables.removing(Self.tomlTable, from: text).dropLast())
            case .command:
                throw EditError(description: "\(name) is disconnected from Terminal.")
            }
        }
    }

    private static let tomlTable = "mcp_servers.\(serverName)"

    private func edit(home: URL, _ change: (String?) throws -> String) throws {
        let url = config(in: home)
        let path = url.path(percentEncoded: false)
        let manager = FileManager.default
        let existing = try? Data(contentsOf: url)
        var text: String?
        if let existing {
            guard let decoded = String(bytes: existing, encoding: .utf8) else {
                throw EditError(description: "It isn’t UTF-8 text, so Luna left it alone.")
            }
            text = decoded
        }
        let updated = try change(text)
        if let existing {
            try existing.write(to: url.appendingPathExtension("luna-backup"), options: .atomic)
        } else {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        // An atomic write replaces the file, and with it its mode; a config
        // that holds tokens may be 0600 on purpose.
        let mode = try? manager.attributesOfItem(atPath: path)[.posixPermissions]
        try Data(updated.utf8).write(to: url, options: .atomic)
        if let mode { try? manager.setAttributes([.posixPermissions: mode], ofItemAtPath: path) }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EditError(description: "not a JSON object")
        }
        return object
    }

    /// Key order is not kept — `JSONSerialization` has none to keep — so the
    /// output is sorted to be the same every time. The backup has the
    /// original. A file with comments in it is refused rather than stripped.
    private static func editJSON(
        _ text: String?,
        key: String,
        _ change: (inout [String: Any]) -> Void
    ) throws -> String {
        var root: [String: Any] = [:]
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                root = try object(Data(text.utf8))
            } catch {
                throw EditError(description: "It isn’t plain JSON, so Luna left it alone. Add the entry by hand.")
            }
        }
        var servers = root[key] as? [String: Any] ?? [:]
        change(&servers)
        root[key] = servers
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return (String(bytes: data, encoding: .utf8) ?? "") + "\n"
    }

    static func shellQuoted(_ path: String) -> String {
        let plain = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
        return plain ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - For any other app

    /// The entry most MCP clients take, for the "Other apps" row.
    public static func genericJSON(helper: URL) -> String {
        """
        {
          "mcpServers": {
            "\(serverName)": { "command": "\(helper.path(percentEncoded: false))" }
          }
        }
        """
    }
}

/// Just enough TOML to find and drop one table: headers are read, values are
/// not. A header is `[a.b]`, with or without quotes around a part.
///
/// ponytail: Luna's entry is always written as a table, so an entry spelled
/// as dotted keys or an inline table in the user's file is not recognised.
/// Handle those if someone hand-writes one.
enum TOMLTables {

    /// A header line's table name with quotes and spaces removed, or nil for
    /// a line that is not a `[table]` header (an `[[array]]` one is not).
    static func header(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[["), let close = trimmed.firstIndex(of: "]") else {
            return nil
        }
        return trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            .filter { $0 != "\"" && $0 != "'" && $0 != " " }
    }

    static func contains(_ text: String, table: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { header(String($0)) == table }
    }

    /// `text` without `table` or its subtables, ending in one blank line when
    /// there is anything left, so what is appended after it stands apart.
    static func removing(_ table: String, from text: String?) -> String {
        var kept: [Substring] = []
        var skipping = false
        for line in (text ?? "").split(separator: "\n", omittingEmptySubsequences: false) {
            if let name = header(String(line)) {
                skipping = name == table || name.hasPrefix(table + ".")
            }
            if !skipping { kept.append(line) }
        }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty { kept.removeLast() }
        return kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n\n"
    }

    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
