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
        "Things to do" — and give it an icon: an SF Symbol name (airplane, bed.double.fill, map.fill, cart.fill, \
        fork.knife, ticket.fill) on a tile of one color. Luna shows the name and icon in the sidebar in place \
        of the page's own, so the user can see at a glance what each of your tabs is doing. Only tabs in your \
        folder. Call it once a tab's purpose is clear.
        """, [
            "title": ["type": "string", "description": "One to three words."],
            "symbol": ["type": "string", "description": "An SF Symbol name."],
            "color": ["type": "string", "enum": .array(ControlCall.tabColours.map(JSONValue.string))]
        ])
    ]
}
