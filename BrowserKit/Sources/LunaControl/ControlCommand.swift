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
    /// `trusted` false forces the DOM events a page can tell from a person's;
    /// true goes through the stage when the tab can be staged (`ControlStage`).
    case click(
        Target, clickCount: Int, button: MouseButton = .left, modifiers: ControlInput.Modifiers = [], trusted: Bool = true
    )
    case type(String, ref: String?, trusted: Bool = true)
    /// Space-separated presses, the whole run `repeat` times.
    case key(String, repeat: Int = 1, trusted: Bool = true)
    /// Page events only: WebKit turns no moved event into a hover on the stage.
    case hover(Target)
    case drag(from: Target, to: Target, trusted: Bool = true)
    case scroll(ScrollDirection, amount: Int, target: Target?)
    case fill(ref: String, value: JSONValue)
    case screenshot
    case javascript(String)
    case console(pattern: String?, onlyErrors: Bool, clear: Bool)
    case network(pattern: String?, includeBodies: Bool, clear: Bool)
    case closeTab
    case wait(seconds: Double)
    /// Asks the user to do a step only they can, and waits until they say
    /// it is done.
    case requestUser(String)
    /// Answers the `alert`, `confirm` or `prompt` open in the tab.
    case dialog(accept: Bool, text: String?)
    /// Hands files to a file input, or drops them on anything else.
    case upload(ref: String, files: [UploadSource])

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

    /// A file the agent sends the bytes of, or one on this Mac it names —
    /// read only after the user has seen the path, through `ControlUpload`.
    public enum UploadSource: Sendable, Equatable {
        case data(ControlUpload.File)
        case path(String)
    }

    public enum MouseButton: String, Sendable {
        case left, right, middle
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
        case "click": return try click(args)
        case "type": return .type(try args.required("text"), ref: args.string("ref"), trusted: args.trusted)
        case "key": return try key(args)
        case "hover": return try hover(args)
        case "drag": return try drag(args)
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
        case "network_read":
            return .network(
                pattern: args.string("pattern"),
                includeBodies: args.values["include_bodies"]?.bool ?? false,
                clear: args.values["clear"]?.bool ?? false
            )
        case "tab_close":
            guard args.int("tabId") != nil else { throw ControlError("tabId is required.") }
            return .closeTab
        case "wait": return .wait(seconds: min(max(args.values["seconds"]?.double ?? 1, 0), 30))
        case "request_user": return .requestUser(String(try args.required("reason").prefix(500)))
        case "dialog": return try dialog(args)
        case "file_upload": return .upload(ref: try args.required("ref"), files: try uploads(args.values["files"]))
        default: throw ControlError("Luna has no tool called \(tool).")
        }
    }

    private static func dialog(_ args: Arguments) throws -> ControlCommand {
        switch args.string("action") {
        case "accept": return .dialog(accept: true, text: args.string("text"))
        case "dismiss": return .dialog(accept: false, text: nil)
        default: throw ControlError("action must be accept or dismiss.")
        }
    }

    private static func uploads(_ value: JSONValue?) throws -> [ControlCommand.UploadSource] {
        guard case let .array(items)? = value, !items.isEmpty else { throw ControlError("files needs at least one file.") }
        return try items.map { item in
            if let path = item["path"]?.string { return .path(path) }
            guard let name = item["name"]?.string, !name.isEmpty, let encoded = item["data"]?.string else {
                throw ControlError("Each file needs a path, or a name and its data in base64.")
            }
            // Strict apart from line breaks, which some encoders add every 76 characters.
            guard let data = Data(base64Encoded: encoded.filter { !$0.isWhitespace }) else {
                throw ControlError("The data for “\(name)” is not base64.")
            }
            return .data(ControlUpload.File(name: name, mimeType: item["mimeType"]?.string ?? "application/octet-stream", data: data))
        }
    }

    private static func click(_ args: Arguments) throws -> ControlCommand {
        guard let target = args.target() else { throw ControlError("Give a ref from read_page or find, or x and y.") }
        guard let button = ControlCommand.MouseButton(rawValue: args.string("button") ?? "left") else {
            throw ControlError("button must be left, right or middle.")
        }
        return .click(
            target, clickCount: min(max(args.int("click_count") ?? 1, 1), 3), button: button,
            modifiers: try ControlInput.modifiers(args.string("modifiers") ?? ""), trusted: args.trusted
        )
    }

    private static func key(_ args: Arguments) throws -> ControlCommand {
        let keys = try args.required("key")
        for combo in keys.split(separator: " ") { _ = try ControlInput.key(String(combo)) }
        return .key(keys, repeat: min(max(args.int("repeat") ?? 1, 1), 50), trusted: args.trusted)
    }

    private static func hover(_ args: Arguments) throws -> ControlCommand {
        guard let target = args.target() else { throw ControlError("Give a ref from read_page or find, or a coordinate.") }
        return .hover(target)
    }

    private static func drag(_ args: Arguments) throws -> ControlCommand {
        guard let from = args.target(ref: "ref", point: "start_coordinate", xy: false),
              let to = args.target(ref: "to_ref", point: "coordinate", xy: false)
        else { throw ControlError("Give where to start (ref or start_coordinate) and where to drop (to_ref or coordinate).") }
        return .drag(from: from, to: to, trusted: args.trusted)
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

    var trusted: Bool { values["trusted"]?.bool ?? true }

    /// `ref`, or `x` and `y`, or `coordinate` as `[x, y]` — the shape agents
    /// written against other browsers send. `drag` reads its two ends under
    /// other keys, and not `x`/`y`, which could only name one of them.
    func target(ref refKey: String = "ref", point pointKey: String = "coordinate", xy: Bool = true) -> ControlCommand.Target? {
        if let ref = string(refKey), !ref.isEmpty { return .ref(ref) }
        if xy, let x = values["x"]?.double, let y = values["y"]?.double { return .point(x: x, y: y) }
        if case let .array(pair)? = values[pointKey], pair.count == 2,
           let x = pair[0].double, let y = pair[1].double {
            return .point(x: x, y: y)
        }
        return nil
    }
}
