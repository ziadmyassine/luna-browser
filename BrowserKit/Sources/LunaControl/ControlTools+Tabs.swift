import Foundation

/// Tabs and where they are: listing, opening, going somewhere, closing.
extension ControlTools {

    static let tabs: [JSONValue] = [
        tool("tabs_list", """
        List the tabs open in Luna, in every Space: id, title, URL, and whether each one is in your folder. \
        The user's own tabs are listed too; you may read and act on them.
        """),
        tool("tab_open", """
        Open a new tab, in your own folder in the sidebar. It opens in the background and does not take \
        over the user's window. Returns the tab id; later calls without a tabId use this tab.
        """, ["url": ["type": "string", "description": "Where to go. Leave out for a blank tab."]]),
        tool("navigate", "Go to a URL in a tab, or go back, forward or reload. Waits for the page to load.", [
            "url": ["type": "string", "description": "A URL, or \"back\", \"forward\" or \"reload\"."]
        ], required: ["url"]),
        tool("tab_close", "Close a tab you opened. Only tabs in your own folder can be closed.", [:], required: ["tabId"]),
        tool("wait", "Wait before the next step, up to 30 seconds.", [
            "seconds": ["type": "number", "description": "Default 1."]
        ], tabbed: false)
    ]
}
