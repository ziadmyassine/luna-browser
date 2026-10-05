import Foundation

/// What the agent is doing, in the user's words: a name for the task, which
/// Luna gives the agent's sidebar folder in place of the app's or the
/// session's name.
extension ControlTools {

    static let task: [JSONValue] = [
        tool("name_task", """
        Name the task you are working on in two to four words, the way the user would say it — \
        "Lisbon trip", "Electricity bill", "Running shoes". Luna names your sidebar folder after it and \
        shows it to the user. Call it before your first tab, and again if the task becomes a different one.
        """, ["title": ["type": "string", "description": "Two to four words, no punctuation at the end."]],
             required: ["title"], tabbed: false)
    ]
}
