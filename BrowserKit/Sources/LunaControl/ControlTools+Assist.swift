import Foundation

/// The tools that reach past the page: what the user has browsed and how
/// they have arranged their tabs, the text of a PDF, and an event for the
/// calendar. None of them act on a page.
extension ControlTools {

    static let assist: [JSONValue] = [
        tool("history_search", """
        Search the pages the user has visited in Luna, newest first, by words in their title or address. \
        Use it to learn what the user has been working on before asking them. Luna's own agent only. \
        \(ControlUntrusted.rule)
        """, [
            "query": ["type": "string", "description": "Words to look for. Empty for the most recent pages."],
            "limit": ["type": "integer", "description": "At most this many, up to 50. Default 20."]
        ], tabbed: false),
        tool("folders_list", """
        List the user's sidebar folders in every Space — their names and the tabs in each, with tab ids. \
        The folders are how the user organises what they are working on; act on a folder's tabs by their ids. \
        \(ControlUntrusted.rule)
        """, tabbed: false),
        tool("pdf_text", """
        The text of a PDF: the one at `url`, or the one open in the tab. Fetched as the user, signed in where \
        they are, so a form or a set of rules behind a login can be read. A file in Downloads can be given \
        as a file:// address.
        """, ["url": ["type": "string", "description": "The PDF's address. Leave it out for the tab's."]]),
        tool("add_to_calendar", """
        Put an event or a deadline in the user's calendar. Calendar opens with it and the user confirms it.
        """, [
            "title": ["type": "string"],
            "start": ["type": "string", "description": "ISO 8601: 2027-01-01 for a whole day, or 2027-01-01T09:00 for a time."],
            "end": ["type": "string", "description": "ISO 8601, optional."],
            "notes": ["type": "string", "description": "Optional: a line on what it is and a link."]
        ], required: ["title", "start"], tabbed: false)
    ]
}
