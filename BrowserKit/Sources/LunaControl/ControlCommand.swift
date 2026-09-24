import Foundation

/// One tool call, decoded: which tab it is about and what to do there.
///
/// `tab` is the number `tabs_list` and `tab_open` hand out. Nil means the tab
/// this client last opened or acted on, and failing that the tab the user has
/// in front of them — which is what a model means when it says "the page".
public struct ControlCall: Sendable, Equatable {
    public var tab: Int?
    public var command: ControlCommand

    public init(tab: Int? = nil, _ command: ControlCommand) {
        self.tab = tab
        self.command = command
    }
}

public enum ControlCommand: Sendable, Equatable {
    case listTabs
    case openTab(URL?)
    case navigate(Navigation)
    case readPage(interactiveOnly: Bool, ref: String?, maxDepth: Int)
    case pageText
    case find(String)
    case click(Target, clickCount: Int)
    case type(String, ref: String?)
    case key(String)
    case scroll(ScrollDirection, amount: Int, target: Target?)
    case fill(ref: String, value: JSONValue)
    case screenshot
    case javascript(String)
    case console(pattern: String?, onlyErrors: Bool, clear: Bool)
    case closeTab
    case wait(seconds: Double)

    public enum Navigation: Sendable, Equatable {
        case url(URL)
        case back, forward, reload
    }

    /// An element from `read_page` or `find`, or a point in CSS pixels from
    /// the top left of the viewport — the same space a screenshot is in.
    public enum Target: Sendable, Equatable {
        case ref(String)
        case point(x: Double, y: Double)
    }

    public enum ScrollDirection: String, Sendable, CaseIterable {
        case up, down, left, right
    }
}

/// A call that could not be decoded. The message is written for the model
/// that made the call: it is what it reads back instead of a result.
public struct ControlError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

extension ControlCall {

    /// Decodes a `tools/call`. Nil for a tool Luna does not have, which is a
    /// protocol error rather than a failed call.
    public static func parse(tool: String, arguments: [String: JSONValue]) -> Result<ControlCall, ControlError>? {
        guard ControlTools.names.contains(tool) else { return nil }
        let args = Arguments(values: arguments)
        do {
            return .success(ControlCall(tab: args.int("tabId"), try command(tool, args)))
        } catch let error as ControlError {
            return .failure(error)
        } catch {
            return .failure(ControlError(error.localizedDescription))
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func command(_ tool: String, _ args: Arguments) throws -> ControlCommand {
        switch tool {
        case "tabs_list": return .listTabs
        case "tab_open": return .openTab(try args.string("url").map(Self.url(from:)))
        case "navigate": return .navigate(try navigation(try args.required("url")))
        case "read_page":
            return .readPage(
                interactiveOnly: args.string("filter") == "interactive",
                ref: args.string("ref"),
                maxDepth: min(max(args.int("max_depth") ?? 30, 1), 60)
            )
        case "page_text": return .pageText
        case "find": return .find(try args.required("query"))
        case "click":
            guard let target = args.target() else { throw ControlError("Give a ref from read_page or find, or x and y.") }
            return .click(target, clickCount: min(max(args.int("click_count") ?? 1, 1), 3))
        case "type": return .type(try args.required("text"), ref: args.string("ref"))
        case "key": return .key(try args.required("key"))
        case "scroll":
            let raw = args.string("direction") ?? "down"
            guard let direction = ControlCommand.ScrollDirection(rawValue: raw) else {
                throw ControlError("direction must be up, down, left or right.")
            }
            return .scroll(direction, amount: max(args.int("amount") ?? 3, 1), target: args.target())
        case "form_input":
            guard let value = args.values["value"] else { throw ControlError("value is required.") }
            return .fill(ref: try args.required("ref"), value: value)
        case "screenshot": return .screenshot
        case "javascript": return .javascript(try args.required("code"))
        case "console_read":
            return .console(
                pattern: args.string("pattern"),
                onlyErrors: args.values["only_errors"]?.bool ?? false,
                clear: args.values["clear"]?.bool ?? false
            )
        case "tab_close":
            guard args.int("tabId") != nil else { throw ControlError("tabId is required.") }
            return .closeTab
        case "wait": return .wait(seconds: min(max(args.values["seconds"]?.double ?? 1, 0), 30))
        default: throw ControlError("Luna has no tool called \(tool).")
        }
    }

    private static func navigation(_ raw: String) throws -> ControlCommand.Navigation {
        switch raw.lowercased() {
        case "back": .back
        case "forward": .forward
        case "reload": .reload
        default: .url(try url(from: raw))
        }
    }

    /// What a person would type into the address bar, made into a URL. A bare
    /// host is https, because that is what it means in 2026 and because §17's
    /// HTTPS upgrade would take it there anyway.
    public static func url(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
        let spelled = hasScheme ? trimmed : "https://" + trimmed
        guard !trimmed.isEmpty, let url = URL(string: spelled), let scheme = url.scheme?.lowercased(),
              ["http", "https", "about", "file", "data"].contains(scheme)
        else { throw ControlError("“\(raw)” is not a web address.") }
        return url
    }
}

/// The arguments object, read leniently: a model that sends `"3"` for `3`
/// meant three.
private struct Arguments {
    let values: [String: JSONValue]

    func string(_ key: String) -> String? {
        guard let value = values[key] else { return nil }
        if case let .string(text) = value { return text }
        return value.double.map { String($0) }
    }

    func int(_ key: String) -> Int? { values[key]?.int }

    func required(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else { throw ControlError("\(key) is required.") }
        return value
    }

    /// `ref`, or `x` and `y`, or `coordinate` as `[x, y]` — the shape agents
    /// written against other browsers send.
    func target() -> ControlCommand.Target? {
        if let ref = string("ref"), !ref.isEmpty { return .ref(ref) }
        if let x = values["x"]?.double, let y = values["y"]?.double { return .point(x: x, y: y) }
        if case let .array(pair)? = values["coordinate"], pair.count == 2,
           let x = pair[0].double, let y = pair[1].double {
            return .point(x: x, y: y)
        }
        return nil
    }
}
