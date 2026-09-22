import Foundation

//  Luna's own pages (§4.4): the History page, and the error pages that
//  replace WebKit's defaults (§4.5).
//
//  There was a third, `luna://newtab` — a search pill over a grid of Favorites,
//  and what a tab with no address of its own opened. It is gone. Every route
//  into it already opened §9.1's Command Bar instead: `⌘T`, the sidebar's own
//  New Tab row, the top bar's `+`, and the page's own pill, which handed off
//  rather than taking a second line of input. What was left was a page whose
//  only job was to be somewhere to stand while the bar was open. A tab with no
//  address is `about:blank` now, which is what it always was.
//
//  The gotcha §4.4 records, and the reason everything here is a URL: a
//  `WKURLSchemeHandler` only fires for resources loaded *inside a document that
//  itself came from that scheme*. An internal page injected with
//  `loadHTMLString` into `about:blank` therefore cannot load a single
//  sub-resource — no favicon, no stylesheet — and fails silently while looking
//  like it worked. Every internal page is navigated to as `luna://…`.
//
//  No colour value lives in `BrowserKit` (contract rule 3). The palette is a
//  block of CSS custom properties the app hands over in `palette`, generated
//  from `Design/Tokens.swift` by `Features/InternalPages/InternalPageTheme`.
//  Every rule reads `var(--luna-…, <CSS system colour>)`, so an unset palette
//  degrades to the OS's own `Canvas`/`CanvasText` rather than to a second,
//  drifting set of hex values.

/// The URL scheme Luna's internal pages are served from.
public enum InternalPages {

    public static let scheme = "luna"

    // MARK: - Pages

    /// A page the handler can render.
    public enum Page: Equatable, Sendable {
        case history
        case error(InternalPageError)

        /// The URL that renders this page. Internal pages are navigated to;
        /// nothing here is ever injected into a document (§4.4).
        public var url: URL {
            switch self {
            case .history: URL(string: "\(scheme)://history")!
            case let .error(error): error.pageURL
            }
        }

        /// What the page calls itself — the same string it sets as its own
        /// `<title>`, which is the point: a tab showing one of these has no
        /// title until the load lands, and a label falling back to the host is
        /// all there is to show until then. The host and the title being the
        /// same word is why the address is `history` and not `archive`.
        public var name: String {
            switch self {
            case .history: "History"
            case let .error(error): copy(for: error.kind).title
            }
        }
    }

    /// The name Luna's own pages go by, for a URL that is one — and nil for
    /// every URL that has a host worth showing instead.
    public static func name(for url: URL) -> String? {
        guard case let .page(page) = route(url) else { return nil }
        return page.name
    }

    /// A link on an internal page that the engine cannot perform itself.
    /// `TabController` cancels the navigation and reports it (§4.4).
    public enum Action: Equatable, Sendable {
        /// The way off an error page that is not "try the thing that failed":
        /// §9.1's Command Bar, opened to make a new tab. It is the app's, not
        /// the engine's, which is the whole reason this enum exists.
        case commandBar
        /// History's restore affordance (§6.4).
        case restore(UUID)
        /// An error page's "Try Again" — `TabController` performs it.
        case retry(URL)
        /// An interstitial's "Continue Anyway" — `TabController` performs it and
        /// records the bypass (§4.5).
        case proceed(URL)
    }

    /// What one `luna://` URL means.
    public enum Route: Equatable, Sendable {
        case page(Page)
        /// A cached favicon, served as a sub-resource of an internal page —
        /// exactly the case §4.4's gotcha is about.
        case favicon(host: String)
        case action(Action)
        case notFound
    }

    /// Pure, so routing is testable without a web view.
    public static func route(_ url: URL) -> Route {
        guard url.scheme?.lowercased() == scheme else { return .notFound }
        let query = query(in: url)
        switch url.host()?.lowercased() {
        case "history": return .page(.history)
        // The address this page used to have. A URL somebody bookmarked or
        // left in a closed tab should not stop resolving because the page was
        // renamed, so the old host still lands on the new page.
        case "archive": return .page(.history)
        case "error": return .page(.error(InternalPageError(query: query)))
        case "favicon":
            let host = String(url.path().trimmingPrefix("/"))
            return host.isEmpty ? .notFound : .favicon(host: host)
        case let host: return action(host, query).map(Route.action) ?? .notFound
        }
    }

    private static func action(_ host: String?, _ query: (String) -> String?) -> Action? {
        switch host {
        case "commandbar": return .commandBar
        case "restore": return query("tab").flatMap(UUID.init(uuidString:)).map(Action.restore)
        case "retry": return webURL(query("url")).map(Action.retry)
        case "proceed": return webURL(query("url")).map(Action.proceed)
        default: return nil
        }
    }

    private static func query(in url: URL) -> (String) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        return { name in items?.first { $0.name == name }?.value }
    }

    /// Percent-encoded `name=value` pairs for a `luna://` URL.
    ///
    /// Not `URLComponents.queryItems`. That setter leaves `&` and `+` alone
    /// in a value — both are legal in a query component — so a URL carrying
    /// another URL (`luna://retry?url=https://a.test/?x=1&y=2`) reads back as two
    /// query items and the Retry button loses half its target. Encoding against
    /// the unreserved set is the only spelling that round-trips.
    static func query(_ items: [(name: String, value: String)]) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return items
            .map { "\($0.name)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
    }

    /// An error page renders an attacker-controlled URL by definition, and its
    /// buttons hand that URL straight back to `load`. Anything that is not
    /// plain web content is refused here rather than at the call site, so
    /// `luna://retry?url=javascript:…` cannot become an XSS gadget.
    static func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text) else { return nil }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https" ? url : nil
    }

    // MARK: - Trust (§4.4 security)

    /// Whether a `luna://` navigation from a document with this scheme is
    /// allowed. Internal pages must not be reachable from ordinary web content:
    /// a page that could navigate or frame one gets a clickjacking surface over
    /// History's restore buttons for free.
    ///
    /// Web content always has an `http(s)`/`file`/`data`/`blob` source
    /// document, so refusing everything that is not Luna's own is the whole
    /// rule. Luna's own loads either have no source document yet or come from
    /// another internal page. The one case this would catch wrongly — routing
    /// an error page after a failure on `https://…` — carries a one-shot token
    /// instead (`TabController.expectInternalLoad`).
    ///
    /// `frame-ancestors 'none'` on every response is the second half of this;
    /// see `InternalPageHandler`.
    public static func allowsNavigation(fromDocumentScheme sourceScheme: String?) -> Bool {
        guard let sourceScheme = sourceScheme?.lowercased() else { return true }
        return sourceScheme == scheme || sourceScheme == "about"
    }

    // MARK: - App-supplied seams
    //
    // `BrowserKit` cannot reach `Design/` (no AppKit) or the tab list, so the
    // two things internal pages need from outside are set once at assembly by
    // `Features/InternalPages/InternalPagesInstaller`.

    /// CSS custom properties generated from `Design/Tokens.swift`.
    @MainActor public static var palette = ""

    /// The archived tabs `luna://history` renders, read live.
    @MainActor public static var content: (@MainActor () -> InternalPageContent)?

    /// Performs an `Action` the engine cannot. The `UUID` is the tab that asked.
    @MainActor public static var onAction: (@MainActor (Action, UUID) -> Void)?

}

/// What the History page renders (§6.4). Supplied by the app; `BrowserKit`
/// cannot see the tab list.
public struct InternalPageContent: Sendable {

    public struct Entry: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let url: URL
        public let archivedAt: Date?

        public init(id: UUID, title: String, url: URL, archivedAt: Date? = nil) {
            self.id = id
            self.title = title
            self.url = url
            self.archivedAt = archivedAt
        }
    }

    public var archived: [Entry]

    public init(archived: [Entry] = []) {
        self.archived = archived
    }
}

// MARK: - Escaping

/// The only way text reaches an internal page's DOM.
///
/// Every string these pages render is attacker-controlled: a failed URL, a
/// page-supplied `<title>` kept on an archived tab, a host name. There is no
/// "safe" source here, so there is no unescaped path — `InternalPageTests`
/// fails if a template interpolates anything that did not come through this.
public enum HTML {

    /// Text content and quoted attribute values. `&` first, or the other
    /// replacements' own ampersands get double-escaped.
    public static func escape(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out.replacingOccurrences(of: "'", with: "&#39;")
    }

    /// An `href` value, or nil when the URL is not plain web content. A
    /// `javascript:` URL in an archived tab's row would otherwise be a stored
    /// XSS with a click target.
    public static func href(_ url: URL) -> String? {
        InternalPages.webURL(url.absoluteString).map { escape($0.absoluteString) }
    }

    /// A `luna://` action URL, percent-encoded then escaped.
    static func action(_ host: String, url: URL) -> String {
        let query = InternalPages.query([(name: "url", value: url.absoluteString)])
        return escape("\(InternalPages.scheme)://\(host)?\(query)")
    }
}
