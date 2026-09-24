import Foundation

/// What `tools/list` answers: every tool's name, description and input schema.
///
/// The names and argument spellings follow what agents already use to drive
/// other browsers (`ref`, `coordinate`, `tabId`), so a model's habits carry
/// over. `ControlCall.parse` is the other half and reads the same keys.
///
/// One file per area, each holding its own array, so a new tool is an append
/// to one of them rather than an edit in a list every change touches.
public enum ControlTools {

    public static let names: Set<String> = Set(all.compactMap { $0["name"]?.string })

    public static let all: [JSONValue] = tabs + page + input + script + handoff + network

    static let tabID: JSONValue = [
        "type": "integer",
        "description": "A tab id from tabs_list or tab_open. Leave it out for the tab you last used."
    ]
    static let ref: JSONValue = ["type": "string", "description": "An element ref from read_page or find, like e12."]

    static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: JSONValue] = [:],
        required: [String] = [],
        tabbed: Bool = true
    ) -> JSONValue {
        var properties = properties
        let listsTabs = name == "tabs_list" || name == "tab_open"
        if tabbed, !listsTabs { properties["tabId"] = tabID }
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
        // Said on every tool whose answer carries page text, not only once in
        // the instructions: a client may never show the model those.
        let said = tabbed ? description + " " + ControlUntrusted.rule : description
        return ["name": .string(name), "description": .string(said), "inputSchema": .object(schema)]
    }
}
