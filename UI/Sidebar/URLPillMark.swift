//
//  URLPillMark.swift
//  Luna
//
//  §3.2's leading mark: the one glyph that says whether what is in the address
//  bar is a **place** or a **question**.
//
//  Split out of `URLPillView.swift` for the reason `URLPillLayout.swift` was:
//  that file crosses SwiftLint's 400-line limit otherwise. Nothing changed on
//  the way across.
//
//  `mark` and `markState` stay stored properties of the view — an extension
//  cannot hold them — and nothing outside these files touches either.
//

import AppKit
import BrowserKit

extension URLPillView {

    // MARK: - The leading mark (§3.2)

    /// What the pill is about, in one glyph: a **magnifier** when what is in it
    /// is a search, the site's **favicon** when the address is one Luna already
    /// has a mark for, and a **globe** when it is an address and no mark has
    /// arrived.
    ///
    /// The point is that it answers *while you type*, before Return decides
    /// anything: the same string can be either, and which one it is is a rule
    /// (`CommandBarURL.direct`) rather than something the user should have to
    /// hold in their head. `apple.com` is a place; `apple news` is a question;
    /// the mark is the pill saying which it read.
    ///
    /// **The same rule that commits.** It is not a second, looser guess made
    /// for the glyph's sake — the mark asks `CommandBarURL.direct` exactly as
    /// `BrowserSession.load` does, so a pill showing a globe cannot then run a
    /// search, and a magnifier cannot open a site.
    @MainActor
    enum LeadingMark: Equatable {
        case search
        case link
        case site(NSImage)

        /// What `text` would do if it were committed now. Empty is a search:
        /// an empty pill is an invitation to type a question, which is what
        /// §3.2's placeholder says in words.
        ///
        /// A page Luna serves itself is a search too, not a globe. `luna://`
        /// is a scheme the bar accepts, so the rule would otherwise call the
        /// new tab a website — and a globe over a page that is nowhere on the
        /// web is the one answer here that is simply untrue. A new tab is an
        /// invitation to ask for something, which is what the magnifier says.
        static func reading(_ text: String) -> LeadingMark {
            guard let url = CommandBarURL.direct(from: text) else { return .search }
            guard InternalPages.name(for: url) == nil else { return .search }
            return SidebarIcons.favicon(for: url).map(LeadingMark.site) ?? .link
        }
    }

    /// The mark for the pill as it stands: what is being typed while it is
    /// open, and the page it is showing the address of the rest of the time.
    func refreshMark() {
        apply(isEditing ? .reading(field.stringValue) : .reading(displayedURL?.absoluteString ?? ""))
    }

    private func apply(_ next: LeadingMark) {
        guard next != markState else { return }
        markState = next
        switch next {
        case .search:
            mark.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            mark.image?.isTemplate = true
            mark.contentTintColor = Tokens.Text.secondary
        case .link:
            mark.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            mark.image?.isTemplate = true
            mark.contentTintColor = Tokens.Text.secondary
        case let .site(favicon):
            mark.image = favicon
            mark.contentTintColor = nil
        }
        // A favicon is not the same shape as a glyph, so the text's start moves
        // with the mark rather than being reserved for the widest of the two.
        needsLayout = true
    }

    /// `apple.com`, not `https://www.apple.com/iphone` (§30.3). `www.` is the
    /// one subdomain that is never meaningful.
    ///
    /// Luna's own pages answer with their name instead. They have a host like
    /// anything else and it is not a name — a tab on `luna://newtab` carries no
    /// title until the page reports one, and until then this was its label.
    static func domain(of url: URL?) -> String {
        guard let url else { return "" }
        if let name = InternalPages.name(for: url) { return name }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
