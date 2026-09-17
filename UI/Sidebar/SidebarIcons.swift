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

import AppKit
import BrowserKit

@MainActor
enum SidebarIcons {

    private static var cache: [String: NSImage] = [:]

    /// The site's icon, or nil — in which case the row draws its symbol.
    static func favicon(for tab: Tab) -> NSImage? {
        // §3.2's "Show tab favicons". This is the one chokepoint — the sidebar
        // list and the Essentials grid both come through here — so the setting
        // is a single guard rather than a flag every call site has to remember.
        guard AppearanceSection.showFavicons else { return nil }
        guard let host = tab.url.host(percentEncoded: false), !host.isEmpty else { return nil }
        if let cached = cache[host] { return cached }
        guard let png = FaviconService.shared.favicon(forHost: host),
              let image = NSImage(data: png)
        else { return nil }
        image.isTemplate = false
        cache[host] = image
        return image
    }
}
