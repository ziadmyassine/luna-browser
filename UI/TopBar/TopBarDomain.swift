//
//  TopBarDomain.swift
//  Luna
//
//  What a tab is called on §4's bar when the page has not said: its domain.
//
//  It outlived the pill it was written for. §4 used to expand the active tab
//  into a URL pill and this was that pill's display rule; the bar now draws
//  every tab as itself and `⌘L` goes to §9.1, but the rule is unchanged — a
//  chip with no title shows a domain, never a URL.
//

import BrowserKit
import Foundation

/// §3.2: a tab is named by a domain, never by a URL.
enum TopBarDomain {

    /// Host minus `www.`. Not eTLD+1: Foundation ships no public-suffix list,
    /// and collapsing to the last two labels would turn `docs.github.com` into
    /// `github.com` — §3.2 keeps a subdomain when it is meaningful, and every
    /// subdomain except `www` is. Same rule as `BrowserKit`'s favicon key.
    static func display(for url: URL?) -> String {
        guard let url else { return "" }
        // Luna's own pages have a host, and it is not a name: a New Tab whose
        // `<title>` has not arrived yet was labelled `archive` until it did.
        if let name = InternalPages.name(for: url) { return name }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            // `about:blank` — there is no host to shorten.
            return url.absoluteString
        }
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// What the user typed in the pill, as something to navigate to — or nil,
    /// meaning "this was a search, not an address".
    ///
    /// Deliberately thin: dangerous schemes are not re-checked here because
    /// `NavigationPolicy` already blocks them at the one place every navigation
    /// passes through. A second copy would be a second thing to keep right.
    static func resolve(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        guard trimmed.contains(".") else { return nil }
        return URL(string: "https://" + trimmed)
    }
}
