import Foundation

/// What the agent is doing, in the user's words: a name for the task, which
/// Luna gives the agent's sidebar folder in place of the app's or the
/// session's name.
extension ControlTools {

    static let task: [JSONValue] = [
        tool("name_task", """
        Name the task you are working on in two to four words, the way the user would say it — \
        "Lisbon trip", "Electricity bill", "Running shoes". Luna names your sidebar folder after it and \
        shows it to the user, with the icon you choose for it. Call it before your first tab, and again if \
        the task becomes a different one.
        """, [
            "title": ["type": "string", "description": "Two to four words, no punctuation at the end."],
            "icon": ["type": "string", "description": "One emoji (✈️, 🧾, 👟) or an SF Symbol name for the folder."]
        ],
             required: ["title"], tabbed: false),
        tool("label_tab", """
        Name one of your tabs for what it is for in the task, in one to three words — "Flights", "Hotels", \
        "Things to do". Luna shows the name in the sidebar in place of the page's title, so the user can \
        see at a glance what each of your tabs is doing. Only tabs in your folder. Call it once a tab's \
        purpose is clear.
        """, ["title": ["type": "string", "description": "One to three words."]], required: ["title"]),
        tool("show_document", """
        Write up what you found as a Markdown document — headings, tables, lists, links — and Luna saves it \
        and opens it in a tab in your folder, set for reading, where the user can change its type and size. \
        Use it whenever your answer is more than a few lines: a comparison, an itinerary, options with \
        prices. Then tell the user in a sentence or two what is in it.
        """, [
            "title": ["type": "string", "description": "The document's title, a few words."],
            "markdown": ["type": "string", "description": "The whole document, in Markdown. Start with a # heading."]
        ], required: ["title", "markdown"], tabbed: false)
    ]
}
