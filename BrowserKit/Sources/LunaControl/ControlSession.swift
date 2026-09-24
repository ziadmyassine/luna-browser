import Foundation

/// What a tool call produced: text, images, or an error the model should read.
public struct ControlResult: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        case png(Data)
    }

    public var content: [Content]
    public var isError: Bool

    public init(_ content: [Content], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String) -> ControlResult { ControlResult([.text(text)]) }
    public static func error(_ message: String) -> ControlResult { ControlResult([.text(message)], isError: true) }

    var json: JSONValue {
        let items: [JSONValue] = content.map { item in
            switch item {
            case let .text(text): ["type": "text", "text": .string(text)]
            case let .png(data): ["type": "image", "mimeType": "image/png", "data": .string(data.base64EncodedString())]
            }
        }
        return ["content": .array(items), "isError": .bool(isError)]
    }
}

/// Carries out one decoded call. The app's is `ControlService.perform`; the
/// relay's, when Luna cannot be reached, answers every call with that fact.
public typealias ControlPerformer = @Sendable (ControlCall, ControlClient) async -> ControlResult

/// One MCP conversation: JSON-RPC 2.0, one message per line, in both
/// directions. Knows the protocol and nothing about browsers.
///
/// An actor because a connection's messages are answered in the order they
/// arrive and the client named in `initialize` belongs to that connection.
public actor ControlSession {

    /// The versions this server speaks. A client asking for one of them gets
    /// it back; any other gets the newest, which is how MCP negotiates.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public static let instructions = """
    Luna Control drives the Luna web browser on this Mac. Tabs you open go into a sidebar folder named \
    after you. Start with tabs_list or tab_open, read the page with read_page or page_text, act with \
    click, type, key, form_input and scroll, and use refs from read_page or find. The browser is signed \
    in as the user: act only as they asked. Some calls wait for the user to approve them in Luna; a \
    declined or stopped call says so, and is not to be worked around. Passwords, card numbers, one-time \
    codes and CAPTCHAs are the user's: when a step needs one, call request_user and wait. \(ControlUntrusted.rule)
    """

    public private(set) var client = ControlClient(rawName: "")
    private let perform: ControlPerformer
    private let version: String
    private let onInitialize: (@Sendable (ControlClient) -> Void)?

    public init(
        version: String = "1.0",
        perform: @escaping ControlPerformer,
        onInitialize: (@Sendable (ControlClient) -> Void)? = nil
    ) {
        self.version = version
        self.perform = perform
        self.onInitialize = onInitialize
    }

    /// Answers one line. Nil for a notification, which gets no reply, and
    /// for a response, which a client sends only to requests this server
    /// never makes.
    public func handle(_ line: Data) async -> Data? {
        guard let message = JSONValue.parse(line), case .object = message else {
            return Self.reply(id: .null, error: (-32700, "Parse error"))
        }
        guard let method = message["method"]?.string else { return nil }
        let id = message["id"]
        let params = message["params"] ?? [:]
        switch method {
        case "initialize":
            client = ControlClient(rawName: params["clientInfo"]?["name"]?.string ?? "")
            onInitialize?(client)
            return id.map { Self.reply(id: $0, result: initializeResult(params)) }
        case "ping":
            return id.map { Self.reply(id: $0, result: [:]) }
        case "tools/list":
            return id.map { Self.reply(id: $0, result: ["tools": .array(ControlTools.all)]) }
        case "tools/call":
            guard let id else { return nil }
            return await call(id: id, params: params)
        default:
            // A notification — `initialized`, `cancelled` — needs nothing back.
            return id.map { Self.reply(id: $0, error: (-32601, "Method not found: \(method)")) }
        }
    }

    private func initializeResult(_ params: JSONValue) -> JSONValue {
        let asked = params["protocolVersion"]?.string ?? ""
        let agreed = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
        return [
            "protocolVersion": .string(agreed),
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "luna", "title": "Luna", "version": .string(version)],
            "instructions": .string(Self.instructions)
        ]
    }

    private func call(id: JSONValue, params: JSONValue) async -> Data {
        let name = params["name"]?.string ?? ""
        var arguments: [String: JSONValue] = [:]
        if case let .object(object)? = params["arguments"] { arguments = object }
        guard let parsed = ControlCall.parse(tool: name, arguments: arguments) else {
            return Self.reply(id: id, error: (-32602, "Unknown tool: \(name)"))
        }
        let result: ControlResult
        switch parsed {
        case let .success(call): result = await perform(call, client)
        case let .failure(error): result = .error(error.message)
        }
        return Self.reply(id: id, result: result.json)
    }

    static func reply(id: JSONValue, result: JSONValue) -> Data {
        (["jsonrpc": "2.0", "id": id, "result": result] as JSONValue).encoded()
    }

    static func reply(id: JSONValue, error: (code: Int, message: String)) -> Data {
        let body: JSONValue = ["code": .int(error.code), "message": .string(error.message)]
        return (["jsonrpc": "2.0", "id": id, "error": body] as JSONValue).encoded()
    }
}
