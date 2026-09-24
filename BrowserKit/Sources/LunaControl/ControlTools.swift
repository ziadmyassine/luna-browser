import Foundation

/// What `tools/list` answers: every tool's name, description and input schema.
///
/// The names and argument spellings follow what agents already use to drive
/// other browsers (`ref`, `coordinate`, `tabId`), so a model's habits carry
/// over. `ControlCall.parse` is the other half and reads the same keys.
public enum ControlTools {

    public static let names: Set<String> = Set(all.compactMap { $0["name"]?.string })

    private static let tabID: JSONValue = [
        "type": "integer",
        "description": "A tab id from tabs_list or tab_open. Leave it out for the tab you last used."
    ]
    private static let ref: JSONValue = ["type": "string", "description": "An element ref from read_page or find, like e12."]

    public static let all: [JSONValue] = [
        tool("tabs_list", """
        List the tabs open in Luna, in every Space: id, title, URL, and whether each one is in your folder. \
        The user's own tabs are listed too; you may read and act on them.
        """),
        tool("tab_open", """
        Open a new tab, in your own folder in the sidebar. It opens in the background and does not take \
        over the user's window. Returns the tab id; later calls without a tabId use this tab.
        """, ["url": ["type": "string", "description": "Where to go. Leave out for a blank tab."]]),
        tool("navigate", "Go to a URL in a tab, or go back, forward or reload. Waits for the page to load.", [
            "url": ["type": "string", "description": "A URL, or \"back\", \"forward\" or \"reload\"."]
        ], required: ["url"]),
        tool("read_page", """
        Read the page as an accessibility tree: one line per element with its role, its name and, for anything \
        you can act on, a ref like e12. Refs stay the same for the same element until the page navigates.
        """, [
            "filter": ["type": "string", "enum": ["all", "interactive"], "description": "interactive lists only controls."],
            "ref": ["type": "string", "description": "Read only the subtree under this element."],
            "max_depth": ["type": "integer", "description": "How deep to go. Default 30."]
        ]),
        tool("page_text", "The page's readable text, main content first. Cheaper than read_page for articles."),
        tool("find", "Find elements whose text, label, placeholder or role contains the query. Returns refs.", [
            "query": ["type": "string", "description": "What to look for, e.g. \"sign in\" or \"search box\"."]
        ], required: ["query"]),
        tool("click", "Click an element by ref, or a point by viewport coordinates from a screenshot.", [
            "ref": ref,
            "coordinate": ["type": "array", "items": ["type": "number"], "description": "[x, y] in CSS pixels."],
            "click_count": ["type": "integer", "description": "2 for a double click."]
        ]),
        tool("type", "Type text into the element with focus, or into ref after focusing it.", [
            "text": ["type": "string"], "ref": ref
        ], required: ["text"]),
        tool("key", """
        Press keys in the page: Enter, Tab, Escape, Backspace, Delete, ArrowUp/Down/Left/Right, Home, End, \
        PageUp, PageDown, or a character. Combine with + (cmd+a) and separate presses with spaces.
        """, ["key": ["type": "string"]], required: ["key"]),
        tool("scroll", "Scroll the page, or the element under ref or coordinate, by a number of steps.", [
            "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
            "amount": ["type": "integer", "description": "Steps of about 100 pixels. Default 3."],
            "ref": ["type": "string", "description": "Scroll this element into view instead."],
            "coordinate": ["type": "array", "items": ["type": "number"]]
        ]),
        tool("form_input", "Set a form control's value: text for fields, true/false for checkboxes, an option for selects.", [
            "ref": ref, "value": ["description": "The new value."]
        ], required: ["ref", "value"]),
        tool("screenshot", "Take a screenshot of the tab's viewport. Coordinates in it are the ones click takes."),
        tool("javascript", """
        Run JavaScript in the page and return the value of the last expression, as JSON. Runs with the \
        page's own variables and the user's signed-in session.
        """, ["code": ["type": "string"]], required: ["code"]),
        tool("console_read", """
        Read what the page has logged to the console since Luna Control first touched it on this page.
        """, [
            "pattern": ["type": "string", "description": "Only messages matching this regular expression."],
            "only_errors": ["type": "boolean"],
            "clear": ["type": "boolean", "description": "Empty the log after reading it."]
        ]),
        tool("tab_close", "Close a tab you opened. Only tabs in your own folder can be closed.", [:], required: ["tabId"]),
        tool("wait", "Wait before the next step, up to 30 seconds.", [
            "seconds": ["type": "number", "description": "Default 1."]
        ], tabbed: false)
    ]

    private static func tool(
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
        return ["name": .string(name), "description": .string(description), "inputSchema": .object(schema)]
    }
}
