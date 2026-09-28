import Foundation

/// The program on the other end of a connection, as it named itself in MCP's
/// `initialize`. Its display name is the sidebar folder its tabs go into.
public struct ControlClient: Sendable, Hashable {
    /// `clientInfo.name` as sent, or empty when there was none.
    public var rawName: String
    public var displayName: String
    /// One per `initialize`, so two windows of the same client each keep
    /// their own idea of which tab they are working in.
    public var connection: UUID
    /// One per agent session, which outlives a connection: `luna-control`
    /// sends it (`ControlSessionTag`) and sends the same one again when Luna
    /// relaunches under it. Two sessions of one app are two agents, each with
    /// a folder, a pause and an activity list of its own. A client that came
    /// in without the helper is one session per connection.
    public var session: String
    /// What the user calls the session, when its app writes that down
    /// somewhere the helper can read. Nil until then.
    public var sessionName: String?

    public init(rawName: String, connection: UUID = UUID(), session: String? = nil, sessionName: String? = nil) {
        self.rawName = rawName
        self.connection = connection
        self.session = session ?? connection.uuidString
        self.sessionName = sessionName
        displayName = Self.displayName(for: rawName)
    }

    /// What a folder is called when the client gave no name, or one with no
    /// letters in it.
    public static let fallbackName = "Agent"

    /// Clients name themselves like packages — `claude-code`, `codex-mcp-client`,
    /// `cursor-vscode` — and a sidebar folder wants a product name. Generic on
    /// purpose: no client is special-cased, so a new one reads as well as an
    /// old one does.
    ///
    /// Words split on `-`, `_`, `.`, spaces and camel humps; a trailing word
    /// that only says what kind of program it is (`mcp`, `client`, `cli`) is
    /// dropped; a common initialism (`ai`, `gpt`) is capitalised whole; a word
    /// that is already mixed or upper case keeps its spelling.
    public static func displayName(for rawName: String) -> String {
        var words = split(rawName)
        let noise: Set<String> = ["mcp", "client", "cli", "app", "server", "vscode", "desktop", "ide"]
        while words.count > 1, let last = words.last, noise.contains(last.lowercased()) {
            words.removeLast()
        }
        let name = words.map(capitalised).joined(separator: " ")
        return name.isEmpty ? fallbackName : String(name.prefix(40))
    }

    private static func split(_ raw: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in raw {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func capitalised(_ word: String) -> String {
        guard word == word.lowercased(), let first = word.first else { return word }
        if ["ai", "ui", "vs", "llm", "gpt", "api"].contains(word) { return word.uppercased() }
        return first.uppercased() + word.dropFirst()
    }
}
