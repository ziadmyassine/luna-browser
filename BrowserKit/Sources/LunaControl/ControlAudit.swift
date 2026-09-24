import Foundation

/// The record of every call a client made: what, where, what was decided and
/// how it ended. One JSON object per line, in the Control folder beside the
/// socket, readable only by the user — it names the sites an agent visited.
///
/// No values: what was typed is counted, script is scrubbed and cut short, so
/// the log is not a second place a secret can end up.
public enum ControlAudit {

    public struct Record: Codable, Sendable, Equatable {
        public var time: Date
        public var client: String
        public var tool: String
        public var tab: Int?
        public var site: String?
        public var summary: String
        /// `allowed`, `approved`, `declined`, `refused`, `stopped`.
        public var decision: String
        /// `ok` or `error`.
        public var outcome: String

        public init(
            time: Date = Date(), client: String, tool: String, tab: Int?, site: String?,
            summary: String, decision: String, outcome: String
        ) {
            self.time = time
            self.client = client
            self.tool = tool
            self.tab = tab
            self.site = site
            self.summary = summary
            self.decision = decision
            self.outcome = outcome
        }
    }

    public static func url(inControlFolderOf socket: URL) -> URL {
        socket.deletingLastPathComponent().appending(path: "activity.jsonl")
    }

    /// Past this the file is rolled to `activity.1.jsonl`, replacing the one
    /// before: two files of a few thousand calls each is history enough.
    static let rollSize = 4 << 20

    public static func append(_ record: Record, to url: URL) throws {
        let manager = FileManager.default
        let path = url.path(percentEncoded: false)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: path))?[.size] as? Int, size > rollSize {
            let rolled = url.deletingPathExtension().appendingPathExtension("1.jsonl")
            try? manager.removeItem(at: rolled)
            try manager.moveItem(at: url, to: rolled)
        }
        if !manager.fileExists(atPath: path) {
            guard manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let line = try encoder.encode(record) + Data("\n".utf8)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// The newest `limit` records, newest first. A line that does not decode
    /// is skipped rather than ending the read.
    public static func read(from url: URL, limit: Int = 200) -> [Record] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").reversed().lazy
            .compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
            .prefix(limit)
            .map(\.self)
    }

    /// What the call did, for the log and for the approval prompt: the tool
    /// and its target, never what it typed.
    public static func summary(of command: ControlCommand) -> String { // swiftlint:disable:this cyclomatic_complexity
        switch command {
        case .listTabs: "tabs_list"
        case let .openTab(url): "tab_open \(url.map { ControlRedactor.scrub($0.absoluteString) } ?? "blank")"
        case let .navigate(.url(url)): "navigate to \(ControlRedactor.scrub(url.absoluteString))"
        case .navigate(.back): "navigate back"
        case .navigate(.forward): "navigate forward"
        case .navigate(.reload): "navigate reload"
        case .readPage: "read_page"
        case .pageText: "page_text"
        case let .find(query): "find \(clip(query))"
        case let .click(target, count, button, _, _):
            "click \(describe(target))\(count > 1 ? " ×\(count)" : "")\(button == .left ? "" : " \(button.rawValue)")"
        case let .type(text, ref, _): "type \(text.count) characters\(ref.map { " into \($0)" } ?? "")"
        case let .key(keys, times, _): "key \(clip(keys))\(times > 1 ? " ×\(times)" : "")"
        case let .hover(target): "hover \(describe(target))"
        case let .drag(from, to, _): "drag \(describe(from)) to \(describe(to))"
        case let .scroll(direction, _, target): "scroll \(target.map(describe) ?? direction.rawValue)"
        case let .fill(ref, _): "form_input \(ref)"
        case .screenshot: "screenshot"
        case let .javascript(code): "javascript \(clip(ControlRedactor.scrub(code)))"
        case .console: "console_read"
        case .closeTab: "tab_close"
        case let .wait(seconds): "wait \(seconds) s"
        }
    }

    /// The tool's name as `tools/list` spells it.
    public static func tool(of command: ControlCommand) -> String {
        String(summary(of: command).prefix { $0 != " " })
    }

    private static func describe(_ target: ControlCommand.Target) -> String {
        switch target {
        case let .ref(ref): ref
        case let .point(x, y): "at \(Int(x)),\(Int(y))"
        }
    }

    private static func clip(_ text: String) -> String {
        text.count > 200 ? text.prefix(200) + "…" : text
    }
}
