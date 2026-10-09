import Foundation
import Synchronization

/// Which agent session a `luna-control` process serves, and what the user
/// calls it, stamped into the messages it passes to Luna.
///
/// An MCP client starts one helper per session, so the helper is where "which
/// session" is known: `clientInfo` names the app, and two sessions of one app
/// are otherwise the same client. The id goes on `initialize`; the name goes
/// on every `tools/call`, because a session is usually named after it starts —
/// Claude Code titles it from the first message, and the user may rename it.
public final class ControlSessionTag: Sendable {

    /// Keys in `params._meta`, which MCP leaves for this kind of extra.
    public static let sessionKey = "dev.novapps.luna/session"
    public static let nameKey = "dev.novapps.luna/sessionName"

    public let session: String
    private let transcript: Mutex<Transcript>
    private let projects: URL
    /// Sessions found by a call's tool-use id (`name(forToolUse:)`), each
    /// with its own transcript, and the last one found.
    private let found: Mutex<(sessions: [String: Transcript], last: String?)> = Mutex(([:], nil))

    /// `environment` is the helper's own, inherited from the client that
    /// started it.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let claudeSession = environment["CLAUDE_CODE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }
        session = claudeSession ?? UUID().uuidString
        let root = environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        transcript = Mutex(Transcript(root: root, session: claudeSession))
        projects = root.appending(path: "projects")
    }

    /// The session's name now, read at most every `Transcript.interval`.
    public var name: String? {
        transcript.withLock { $0.name() }
    }

    /// `message` with the session stamped on, or unchanged when it is not a
    /// message that carries one.
    public func stamp(_ message: JSONValue?) -> JSONValue? {
        guard case var .object(object)? = message, case var .object(params) = object["params"] ?? .object([:])
        else { return message }
        var meta: [String: JSONValue] = [:]
        if case let .object(existing)? = params["_meta"] { meta = existing }
        switch object["method"]?.string {
        case "initialize":
            meta[Self.sessionKey] = .string(session)
            if let name { meta[Self.nameKey] = .string(name) }
        case "tools/call":
            guard let name = name ?? meta[Self.toolUseKey]?.string.flatMap(name(forToolUse:)) else { return message }
            meta[Self.nameKey] = .string(name)
        default:
            return message
        }
        params["_meta"] = .object(meta)
        object["params"] = .object(params)
        return .object(object)
    }

    // MARK: - A client serving every session

    /// Where Claude Code puts a call's tool-use id in `params._meta`.
    public static let toolUseKey = "claudecode/toolUseId"

    /// Luna's own reader of calls by their tool-use id, over the transcripts
    /// in the user's `~/.claude`, for calls that arrive without a name.
    public static let calls = ControlSessionTag(environment: [:])

    /// The title of the session a call comes from, found by the call's
    /// tool-use id in the transcripts written to in the last few minutes.
    ///
    /// For a client that connects once for all its sessions: the Claude app's
    /// local agent mode starts this helper itself, as `local-agent-mode-luna`,
    /// with no session in its environment, and forwards every session's calls
    /// through it. The id of the call is in its `_meta`, and the session that
    /// made it has just written that id to its transcript.
    func name(forToolUse id: String) -> String? {
        guard id.hasPrefix("toolu_") || id.count >= 8 else { return nil }
        let needle = Data(id.utf8)
        let last = found.withLock { $0.last }
        let wrote = { (file: URL) in Self.tail(of: file).range(of: needle) != nil }
        let session = last.flatMap { Self.transcript(of: $0, in: projects) }.flatMap { wrote($0) ? last : nil }
            ?? Self.recentTranscripts(in: projects).first(where: wrote)?
            .deletingPathExtension().lastPathComponent
        guard let session else { return nil }
        return found.withLock { state in
            state.last = session
            var transcript = state.sessions[session] ?? Transcript(root: projects.deletingLastPathComponent(), session: session)
            let name = transcript.name()
            state.sessions[session] = transcript
            return name
        }
    }

    /// How recently a transcript must have been written to, and how much of
    /// its end is searched: the call's id was written moments before the call.
    static let recentWindow: TimeInterval = 600
    static let tailLength: UInt64 = 2 << 20

    static func transcript(of session: String, in projects: URL) -> URL? {
        Transcript.locate(session, in: projects)
    }

    /// The transcripts written to within `recentWindow`, newest first.
    static func recentTranscripts(in projects: URL, now: Date = Date()) -> [URL] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        let files = folders.flatMap { folder in
            ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
        let dated = files.compactMap { file -> (URL, Date)? in
            guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(date) < recentWindow else { return nil }
            return (file, date)
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func tail(of file: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return Data() }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return Data() }
        try? handle.seek(toOffset: end > tailLength ? end - tailLength : 0)
        return (try? handle.readToEnd()) ?? Data()
    }

    /// Claude Code's record of a session, `projects/<folder>/<id>.jsonl`
    /// under its config directory, which it appends the session's title to
    /// every so often: `custom-title` when the user named it, `ai-title` when
    /// it named it itself. The file reaches gigabytes, so it is read from the
    /// end once, and after that only what was added since.
    struct Transcript {
        let root: URL
        let session: String?
        var file: URL?
        var cached: String?
        var readAt: Date?
        /// The file's length at the last read.
        var offset: UInt64?

        static let interval: TimeInterval = 2
        /// How far back the first read looks, growing until it finds a
        /// title. Title records came 42 MB apart at worst in a 1.9 GB
        /// transcript, where screenshots sat between them.
        static let reach: [UInt64] = [1 << 20, 16 << 20, 64 << 20]

        init(root: URL, session: String?) {
            self.root = root
            self.session = session
        }

        mutating func name(now: Date = Date()) -> String? {
            guard let session else { return nil }
            if let readAt, now.timeIntervalSince(readAt) < Self.interval { return cached }
            readAt = now
            if file == nil { file = Self.locate(session, in: root.appending(path: "projects")) }
            guard let file, let handle = try? FileHandle(forReadingFrom: file) else { return cached }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd() else { return cached }
            // A file shorter than last time was replaced: start again.
            let floor = offset.map { $0 <= end ? $0 : 0 } ?? 0
            offset = end
            for reach in Self.reach {
                let start = end > floor + reach ? end - reach : floor
                try? handle.seek(toOffset: start)
                if let data = try? handle.read(upToCount: Int(end - start)), let title = Self.title(in: data) {
                    cached = title
                    break
                }
                if start == floor { break }
            }
            return cached
        }

        static func locate(_ session: String, in projects: URL) -> URL? {
            let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
            return folders.lazy
                .map { $0.appending(path: "\(session).jsonl") }
                .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        }

        /// The last title the user gave, else the last one the app gave.
        static func title(in data: Data) -> String? {
            var custom: String?
            var generated: String?
            for line in data.split(separator: UInt8(ascii: "\n")).reversed() where custom == nil {
                let isCustom = line.range(of: Data(#""type":"custom-title""#.utf8)) != nil
                let isGenerated = generated == nil && line.range(of: Data(#""type":"ai-title""#.utf8)) != nil
                guard isCustom || isGenerated, let record = JSONValue.parse(Data(line)) else { continue }
                if isCustom {
                    custom = record["customTitle"]?.string.flatMap(trimmed)
                } else {
                    generated = record["aiTitle"]?.string.flatMap(trimmed)
                }
            }
            return custom ?? generated
        }

        private static func trimmed(_ title: String) -> String? {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }
}
