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
    public static let sessionKey = "dk.novapps.luna/session"
    public static let nameKey = "dk.novapps.luna/sessionName"

    public let session: String
    private let transcript: Mutex<Transcript>

    /// `environment` is the helper's own, inherited from the client that
    /// started it.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let claudeSession = environment["CLAUDE_CODE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }
        session = claudeSession ?? UUID().uuidString
        let root = environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        transcript = Mutex(Transcript(root: root, session: claudeSession))
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
            guard let name else { return message }
            meta[Self.nameKey] = .string(name)
        default:
            return message
        }
        params["_meta"] = .object(meta)
        object["params"] = .object(params)
        return .object(object)
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
