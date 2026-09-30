//
//  SidebarIcons.swift
//  Luna
//
//  A host → `NSImage` cache over `FaviconService`'s PNG bytes.
//
//  Not a convenience: `SidebarRowContent` is `Equatable` so a reused row can
//  skip reconfiguring itself, and `NSImage` compares by identity. A fresh
//  `NSImage(data:)` per row per refresh would make every row look changed,
//  re-laying and re-decoding the visible list on every session change — the
//  §19.1 budget gone.
//
//  The lookup takes a URL, not a `Tab`. A row's `Tab` is a snapshot from the
//  last `notifyChange()`, which an in-tab navigation does not raise, so its
//  host is the site the row used to be on.
//
//  One per `FaviconService`: a §5.6 private window has its own, owned by its
//  session, so its hosts are never in `shared` and go when the window does.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarIcons {

    static let shared = SidebarIcons(service: .shared)

    let service: FaviconService
    private var cache: [String: NSImage] = [:]

    init(service: FaviconService) {
        self.service = service
    }

    /// The site's icon, or nil — in which case the row draws its symbol.
    static func favicon(for tab: Tab) -> NSImage? { shared.favicon(for: tab.url) }

    /// The icon for whatever page is loaded now. Nil until the fetch lands
    /// (§4.7), which is the row's cue to fall back to its symbol rather than to
    /// the previous site's mark.
    func favicon(for url: URL?) -> NSImage? {
        guard let host = url?.host(percentEncoded: false), !host.isEmpty else { return nil }
        if let cached = cache[host] { return cached }
        guard let png = service.favicon(forHost: host),
              let image = NSImage(data: png)
        else { return nil }
        image.isTemplate = false
        cache[host] = image
        return image
    }
}
