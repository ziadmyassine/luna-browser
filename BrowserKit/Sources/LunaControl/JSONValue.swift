import Foundation

/// Any JSON value. JSON-RPC's `params`, a tool's `arguments` and an MCP
/// result are all shapes the protocol leaves open, so they travel as this
/// rather than as a `Codable` struct per message.
///
/// Integers are kept apart from doubles so a request id of `7` goes back as
/// `7`: a client matches its responses by id, and `7.0` is not always `7` to it.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    public var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var bool: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    /// A number, whichever way it was spelled. `"3"` counts too: models write
    /// numbers as strings often enough that refusing them is only friction.
    public var double: Double? {
        switch self {
        case let .int(value): Double(value)
        case let .double(value): value
        case let .string(value): Double(value)
        default: nil
        }
    }

    public var int: Int? { double.map { Int($0) } }

    /// Decodes one JSON document. Nil for anything that is not JSON.
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// One line of JSON — no newline inside it, which is what makes a newline
    /// the message boundary on both of Luna Control's pipes.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        // Every case encodes; a failure here would be a bug in this enum.
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
