import Foundation

/// Reading a page: its tree, its text, what matches a query, a picture of it.
extension ControlTools {

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
        tool("screenshot", "Take a screenshot of the tab's viewport. Coordinates in it are the ones click takes.")
    ]
}
