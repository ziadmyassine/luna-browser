//
//  SidebarIcons.swift
//  Luna
//
//  A host → `NSImage` cache over `FaviconService`'s PNG bytes.
//
//  This is not a convenience: `SidebarRowContent` is `Equatable` so a reused
//  row can skip reconfiguring itself, and `NSImage` compares by identity. A
//  fresh `NSImage(data:)` per row per refresh would make every row look
//  changed, every time — re-laying and re-decoding the whole visible list on
//  every session change, which is exactly the §19.1 budget gone.
//
//  The lookup takes a URL, not a `Tab`, and that is the load-bearing part.
//  A row's `Tab` is a snapshot the sidebar took at the last `notifyChange()`,
//  and an in-tab navigation does not raise one — it writes the tab and
//  publishes a `TabState`. Asking the snapshot for the host meant the row kept
//  drawing the icon of the site it used to be on.
//

import AppKit
import BrowserKit

@MainActor
enum SidebarIcons {

    private static var cache: [String: NSImage] = [:]

    /// The site's icon, or nil — in which case the row draws its symbol.
    static func favicon(for tab: Tab) -> NSImage? { favicon(for: tab.url) }

    /// The icon for whatever page is loaded now. Nil until the fetch lands
    /// (§4.7), which is the row's cue to fall back to its symbol rather than to
    /// the previous site's mark.
    static func favicon(for url: URL?) -> NSImage? {
        guard let host = url?.host(percentEncoded: false), !host.isEmpty else { return nil }
        if let cached = cache[host] { return cached }
        guard let png = FaviconService.shared.favicon(forHost: host),
              let image = NSImage(data: png)
        else { return nil }
        image.isTemplate = false
        cache[host] = image
        return image
    }
}
