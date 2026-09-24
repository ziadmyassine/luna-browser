import Foundation

/// Acting on a page: clicking, typing, keys, scrolling, setting a field.
extension ControlTools {

    static let input: [JSONValue] = [
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
        ], required: ["ref", "value"])
    ]
}
