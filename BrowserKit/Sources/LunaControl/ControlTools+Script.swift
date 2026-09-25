import Foundation

/// The page's own JavaScript and what it logged.
extension ControlTools {

    static let script: [JSONValue] = [
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
        ])
    ]
}
