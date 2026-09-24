import Foundation

/// Reading a page: its tree, its text, what matches a query, a picture or a
/// recording of it, and the size it is laid out at.
extension ControlTools {

    /// The frames a `gif` recording keeps.
    public static let frameLimit = 60

    private static let sizes = "\(ControlCommand.viewportRange.lowerBound) to \(ControlCommand.viewportRange.upperBound)."

    static let page: [JSONValue] = [
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
        tool("screenshot", """
        Take a screenshot of the tab's viewport. Coordinates in it are the ones click takes: after one at a \
        scale, give click, hover, drag and scroll points read off that smaller picture until the next screenshot. \
        region zooms in to read detail and leaves that mapping alone.
        """, [
            "scale": ["type": "number", "description": "0.1 to 1: image pixels per CSS pixel. Default 1."],
            "region": [
                "type": "array", "items": ["type": "number"],
                "description": "[x0, y0, x1, y1] in CSS pixels: only this part of the viewport."
            ]
        ]),
        tool("gif", """
        Record the tab as an animated GIF: start, then a frame is taken after each call that changes the page, \
        with a marker where it clicked; stop pauses; export writes the file and returns its path. Up to \
        \(ControlTools.frameLimit) frames, the newest kept. Password and card fields are hidden in every frame.
        """, [
            "action": ["type": "string", "enum": ["start", "stop", "export"]]
        ], required: ["action"]),
        tool("viewport", """
        Lay one of your own tabs out at another size, such as a phone's, in CSS pixels. Only that tab changes: \
        no window on the user's screen moves. Not for a tab the user has on screen. Call with neither width \
        nor height to give it back its size.
        """, [
            "width": ["type": "integer", "description": .string(sizes)],
            "height": ["type": "integer", "description": .string(sizes)]
        ])
    ]
}
