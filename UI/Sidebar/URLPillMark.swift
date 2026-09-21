//
//  URLPillMark.swift
//  Luna
//
//  What the pill says: the text in it, and the rule for whether that text is a
//  place or a question.
//
//  The pill no longer wears that answer. It had a leading mark for a while
//  — a magnifier, a globe, or the site's favicon — and Martin's verdict was
//  that an address bar is not where it belongs: a favicon at the head of the
//  one line saying what page you are on is a second thing to read, on both
//  surfaces and in both of §3.2b's forms. The rule stays, because §9.1's
//  Command Bar field does wear it, and there it is answering a question as it
//  is being typed rather than labelling a page you are already on.
//
//  Split out of `URLPillView.swift` for the reason `URLPillLayout.swift` was:
//  that file crosses SwiftLint's 400-line limit otherwise.
//

import AppKit
import BrowserKit

extension URLPillView {

    // MARK: - Content

    /// What the bar is for, said in the bar. With no site in it the pill was
    /// a lone magnifier over empty space. "Website name" rather than "URL"
    /// because that is what people type: `apple.com`, not a scheme.
    ///
    /// Two strings, because there are two pills. §3.2b's capsule is 420 pt
    /// of centred glass and says the whole sentence; §3.2's is one row of a
    /// column that starts at 260 pt, and after its two glyphs it has about
    /// 180 pt of text box — where the long line, which measures 181, truncates
    /// to `Search or enter website nam…`. That says less than the short one
    /// does: a placeholder that does not fit is not a placeholder.
    func applyPlaceholder() {
        field.placeholderString = centresText
            ? String(localized: "Search or enter website name")
            : String(localized: "Search the web")
    }

    /// Domain at rest — which is the only state the pill has. It used to check
    /// that it was not overwriting something half-typed; nothing is ever typed
    /// here now (see `URLPillView.onHandOff`).
    func show(url: URL?) {
        displayedURL = url
        field.stringValue = Self.label(of: url)
        needsLayout = true
        field.setAccessibilityValue(url?.absoluteString ?? "")
    }

    // MARK: - Place or question (§9.1)

    /// What a string is, in one glyph: a magnifier when it reads as a
    /// search, the site's favicon when it is an address Luna already has a
    /// mark for, and a globe when it is an address and no mark has arrived.
    ///
    /// The point is that it answers while you type, before Return decides
    /// anything: the same string can be either, and which one it is is a rule
    /// (`CommandBarURL.direct`) rather than something the user should have to
    /// hold in their head. `apple.com` is a place; `apple news` is a question;
    /// the mark is §9.1's field saying which it read.
    ///
    /// The same rule that commits. It is not a second, looser guess made
    /// for the glyph's sake — the mark asks `CommandBarURL.direct` exactly as
    /// `BrowserSession.load` does, so a field showing a globe cannot then run a
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

    /// What the pill reads at rest — the domain, or nothing at all on a new
    /// tab, where the placeholder is the truer answer.
    ///
    /// A new tab is the one page with no address worth showing. `New Tab` is a
    /// label for a row in a list of tabs; in an address bar it reads as the
    /// name of a site you are on, and it took the place of the one line that
    /// says what the bar is for. Luna's other pages keep their names —
    /// `History` is somewhere you actually are.
    static func label(of url: URL?) -> String {
        guard let url, case .page(.newTab) = InternalPages.route(url) else { return domain(of: url) }
        return ""
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
