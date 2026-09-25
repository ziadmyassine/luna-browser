import Foundation

/// Acting on a page: clicking, typing, keys, hovering, dragging, scrolling,
/// setting a field, uploading.
extension ControlTools {

    static let coordinate: JSONValue = [
        "type": "array", "items": ["type": "number"], "description": "[x, y] in CSS pixels, as in a screenshot."
    ]
    static let trusted: JSONValue = [
        "type": "boolean",
        "description": """
        Default true: real input the page cannot tell from a person's. The result says trusted: false when Luna \
        fell back to page events. Pass false for page events if trusted input does nothing on a page.
        """
    ]

    static let input: [JSONValue] = [
        tool("click", """
        Click an element by ref, or a point by viewport coordinates from a screenshot. Selects, date and colour \
        pickers are refused: set them with form_input. File pickers are refused: use file_upload.
        """, [
            "ref": ref,
            "coordinate": coordinate,
            "click_count": ["type": "integer", "description": "2 for a double click, 3 for a triple. Default 1."],
            "button": ["type": "string", "enum": ["left", "right", "middle"], "description": "Default left."],
            "modifiers": ["type": "string", "description": "Keys held during the click, e.g. \"cmd\" or \"cmd+shift\"."],
            "trusted": trusted
        ]),
        tool("type", "Type text into the element with focus, or into ref after focusing it. A newline presses Enter.", [
            "text": ["type": "string"], "ref": ref, "trusted": trusted
        ], required: ["text"]),
        tool("key", """
        Press keys in the page: Enter, Tab, Escape, Backspace, Delete, ArrowUp/Down/Left/Right, Home, End, \
        PageUp, PageDown, F1–F12, space, or a character. Combine with + (cmd+a, shift+Tab) and separate presses \
        with spaces. cmd+c, cmd+x and cmd+v reach the page but not the clipboard.
        """, [
            "key": ["type": "string"],
            "repeat": ["type": "integer", "description": "Press the whole sequence this many times, up to 50."],
            "trusted": trusted
        ], required: ["key"]),
        tool("hover", """
        Hover over an element or a point, for menus and tooltips that open on hover. Sent as page events \
        (trusted: false), which a page that watches real pointer movement may ignore.
        """, [
            "ref": ref, "coordinate": coordinate
        ]),
        tool("drag", """
        Press on one element or point, move to another and let go: sliders, sortable lists, drop zones. \
        Draggable elements get the page's own drag and drop events.
        """, [
            "ref": ["type": "string", "description": "The element to drag."],
            "start_coordinate": ["type": "array", "items": ["type": "number"], "description": "Or the point to press at."],
            "to_ref": ["type": "string", "description": "The element to drop on."],
            "coordinate": ["type": "array", "items": ["type": "number"], "description": "Or the point to let go at."],
            "trusted": trusted
        ]),
        tool("scroll", "Scroll the page, or the element under ref or coordinate, by a number of steps.", [
            "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
            "amount": ["type": "integer", "description": "Steps of about 100 pixels. Default 3."],
            "ref": ["type": "string", "description": "Scroll this element into view instead."],
            "coordinate": ["type": "array", "items": ["type": "number"]]
        ]),
        tool("form_input", "Set a form control's value: text for fields, true/false for checkboxes, an option for selects.", [
            "ref": ref, "value": ["description": "The new value."]
        ], required: ["ref", "value"]),
        tool("file_upload", """
        Give files to a file input by ref, or drop them on a drop zone. Send each file's bytes as base64 with a \
        name, or the absolute path of a file on this Mac. A path always waits for the user's approval unless they \
        allow everything, and is refused if it is a symbolic link, has other hard links, is not the user's, or is \
        in ~/.ssh, the keychains or Luna's own data. At most 10 MB a file and 25 MB a call.
        """, [
            "ref": ref,
            "files": ["type": "array", "items": ["type": "object", "properties": [
                "name": ["type": "string"], "mimeType": ["type": "string"],
                "data": ["type": "string", "description": "The file's bytes in base64."],
                "path": ["type": "string", "description": "An absolute path on this Mac, instead of name and data."]
            ]]]
        ], required: ["ref", "files"])
    ]
}
