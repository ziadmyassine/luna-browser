import Foundation

/// Handing a step to the user, and the page's own dialogs.
extension ControlTools {

    static let handoff: [JSONValue] = [
        tool("request_user", """
        Ask the user to do a step only they can — sign in, enter a password or card, solve a CAPTCHA, \
        approve something — and wait until they say it is done, up to five minutes. Luna marks your folder; \
        the user opens it to read your reason and press Done. Say exactly what they should do.
        """, ["reason": ["type": "string", "description": "What the user should do, in one or two sentences."]],
             required: ["reason"], tabbed: false),
        tool("dialog", """
        Answer the alert, confirm or prompt the page has open. Luna holds a dialog from a tab in your folder \
        for you rather than showing it to the user, and dismisses it after 30 seconds; every other call on \
        that tab fails until it is answered. For an alert, accept and dismiss both close it. A "Leave site?" \
        warning never appears: leaving a page always goes ahead.
        """, [
            "action": ["type": "string", "enum": ["accept", "dismiss"]],
            "text": ["type": "string", "description": "For a prompt: the answer to type."]
        ], required: ["action"])
    ]
}
