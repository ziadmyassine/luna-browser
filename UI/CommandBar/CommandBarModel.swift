//
//  CommandBarModel.swift
//  Luna
//
//  §9.2's result vocabulary and its direct URL / IP / `localhost` detection, as
//  plain values. Pure on purpose — no AppKit, no store, no clock — which is what
//  lets §9.3's ranking be asserted against hand-computed numbers in
//  `CommandBarRankingTests` instead of by driving a window.
//
//  §9.6 privacy, structurally rather than as a promise. Nothing under
//  `UI/CommandBar` references a networking type, and `CommandBarPrivacyTests`
//  greps these sources to keep it that way. Suggestions are the one §9.2 source
//  needing a network call, so the call lives outside this module:
//  `Features/Search/SearchSuggestions` fetches them and the controller hands
//  the finished strings in as another local array. What this module does with a
//  query is one of three things — activate a tab, open a URL, run a command.
//

import BrowserKit
import Foundation
import Synchronization

// MARK: - What a row does

/// Every effect the Command Bar can have. A closed enum is the §9.6 guarantee in
/// the type system: there is no case that sends a query anywhere.
enum CommandBarAction: Sendable, Hashable {
    /// Switch to a tab that is already open in this Space (§9.2).
    case activateTab(UUID)
    /// Pull a tab back out of the archive (§6.3).
    case unarchiveTab(UUID)
    /// Navigate the current or a new tab. The only case that carries a URL.
    case open(URL)
    case command(AppCommand)
}

/// §9.2's "app commands". Two, because two are what §9.2 names and the rest of
/// the surface they would drive (Spaces UI, cookie clearing) is not built yet.
enum AppCommand: String, Sendable, Hashable, CaseIterable {
    case newSpace
    case toggleSidebar

    var title: String {
        switch self {
        case .newSpace: "New Space"
        case .toggleSidebar: "Toggle Sidebar"
        }
    }

    /// SF Symbol. Resolved to an image in the row view, never here.
    var symbolName: String {
        switch self {
        case .newSpace: "square.stack.3d.up"
        case .toggleSidebar: "sidebar.left"
        }
    }
}

// MARK: - A row

/// Where a result came from. The order of the cases is the tier order of §9.3
/// — `Comparable` is synthesised from declaration order, and `CommandBarRanking`
/// sorts on it before it looks at any score.
enum CommandBarSource: Sendable, Hashable, Comparable, CaseIterable {
    /// §9.3: "adaptive matches rank above all frecency results." Literally all
    /// of them, which is why this case is first.
    case adaptive
    /// The user typed something unambiguous. A guess must not outrank an instruction.
    case directURL
    /// Already open, so switching costs nothing and reopening costs a process (§19).
    case openTab
    case history
    case archive
    case command
    /// The floor: there is always something to do with a query, and what the
    /// user actually typed outranks anything an engine guessed they meant.
    case search
    /// §3.4's suggestions, when they are switched on. Last on purpose — they
    /// are the only rows in the list that came from somewhere else.
    case suggestion
}

/// One row of the list.
struct CommandBarResult: Identifiable, Sendable, Hashable {
    /// The dedupe key (§9.2 "merged and deduped"): a normalised URL where there
    /// is one, the action otherwise. Two rows with the same id are the same thing.
    var id: String
    var source: CommandBarSource
    var title: String
    var subtitle: String
    var action: CommandBarAction
    /// Present whenever the row can be reached by URL — drives dedupe and §9.4's
    /// inline autofill. A command has none.
    var url: URL?
    /// Within a tier: frecency (§9.3) for history, adaptive `useCount` for
    /// adaptive, and a tab's recency for an open tab. Never compared across tiers.
    var score: Double
    var symbolName: String

    init(
        source: CommandBarSource,
        title: String,
        subtitle: String,
        action: CommandBarAction,
        url: URL? = nil,
        score: Double = 0,
        symbolName: String
    ) {
        self.id = url.map(CommandBarURL.dedupeKey) ?? "\(action)"
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.url = url
        self.score = score
        self.symbolName = symbolName
    }
}

// MARK: - §9.2 direct URL / IP / localhost

/// URL shapes the Command Bar recognises without asking anybody.
enum CommandBarURL {

    /// Schemes a typed string may carry. Matches `NavigationPolicy.internalSchemes`
    /// minus the ones no human types: a pasted `javascript:` is an XSS vector, not
    /// a navigation, and `blob:`/`data:` URLs are not something you retype.
    private static let typableSchemes: Set<String> = ["http", "https", "file", "about", "luna"]

    /// §9.2: "direct URL / IP / `localhost` detection". Returns the URL the user
    /// evidently meant, or nil when the string is a search.
    ///
    /// Deliberately conservative. Anything with whitespace is a search; a bare word
    /// with no dot is a search (otherwise every one-word query becomes a doomed DNS
    /// lookup); a trailing-dot or single-label host is a search.
    static func direct(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        if let scheme = explicitScheme(of: trimmed) {
            guard typableSchemes.contains(scheme) else { return nil }
            return URL(string: trimmed)
        }

        let (host, rest) = splitHost(trimmed)
        guard isLocalhost(host) || isIPv4(host) || isIPv6Literal(host) || looksLikeDomain(host) else { return nil }
        // `localhost` and IP literals are overwhelmingly a dev server, which is
        // overwhelmingly plain HTTP. Everything else gets https and lets the site
        // redirect down if it really must.
        let scheme = isLocalhost(host) || isIPv4(host) || isIPv6Literal(host) ? "http" : "https"
        return URL(string: "\(scheme)://\(host)\(rest)")
    }

    //  ponytail: §9.5's per-Space engine and bang keywords are still not built.
    //  One engine for the whole app — but the user's, not a constant.
    /// Where a string that is not a URL goes. The floor under every text
    /// entry point: the Command Bar's search row and §3.2's URL pill both
    /// commit through here, so they cannot disagree about what a query means.
    ///
    /// §9.7: synchronous, no I/O — see `SearchSettings`.
    static func search(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SearchSettings.current.url(searching: query)
    }

    /// `https://example.com/a` → `example.com/a`. What §9.4 autofills and what a
    /// row shows: a scheme and a `www.` are noise the user did not type.
    static func displayForm(of url: URL) -> String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/"), url.path == "/" || url.path.isEmpty { text.removeLast() }
        return text
    }

    /// The dedupe key of §9.2. Case-folds scheme and host, drops `www.` and a bare
    /// trailing slash, and keeps everything else: `?q=1` is a different page.
    static func dedupeKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        if var host = components.host?.lowercased() {
            if host.hasPrefix("www.") { host.removeFirst(4) }
            components.host = host
        }
        if components.path == "/" { components.path = "" }
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    // MARK: Shapes

    /// `scheme:` only when the colon really introduces a scheme.
    ///
    /// Two things masquerade as one. `192.168.1.40:5173` is caught by the leading
    /// character — a scheme starts with a letter, an address does not.
    /// `localhost:8080` is not, so what follows the colon decides it: a real
    /// scheme is followed by `//`, or by something that is not a bare port number.
    private static func explicitScheme(of input: String) -> String? {
        guard let colon = input.firstIndex(of: ":") else { return nil }
        let candidate = String(input[input.startIndex..<colon]).lowercased()
        guard candidate.first?.isLetter == true,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }
        let port = input[input.index(after: colon)...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard port.isEmpty || !port.allSatisfy(\.isNumber) else { return nil }
        return candidate
    }

    /// Splits `host:port/path?query` into the authority and everything after it.
    private static func splitHost(_ input: String) -> (host: String, rest: String) {
        guard let cut = input.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) else {
            return (input, "")
        }
        return (String(input[input.startIndex..<cut]), String(input[cut...]))
    }

    private static func stripPort(_ host: String) -> String {
        // An IPv6 literal is bracketed, so its colons are inside `[...]`.
        guard !host.hasPrefix("["), let colon = host.lastIndex(of: ":") else { return host }
        let port = host[host.index(after: colon)...]
        return port.allSatisfy(\.isNumber) && !port.isEmpty ? String(host[host.startIndex..<colon]) : host
    }

    private static func isLocalhost(_ host: String) -> Bool {
        stripPort(host).lowercased() == "localhost"
    }

    private static func isIPv4(_ host: String) -> Bool {
        let labels = stripPort(host).split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 3 && label.allSatisfy(\.isNumber) && (Int(label) ?? 256) <= 255
        }
    }

    /// `[::1]` / `[::1]:8080`. Bare `::1` is not accepted: unbracketed it is
    /// indistinguishable from a malformed host:port and RFC 3986 requires the
    /// brackets in a URL anyway.
    private static func isIPv6Literal(_ host: String) -> Bool {
        guard host.hasPrefix("["), let close = host.firstIndex(of: "]") else { return false }
        let inner = host[host.index(after: host.startIndex)..<close]
        let after = host[host.index(after: close)...]
        guard !inner.isEmpty, inner.allSatisfy({ $0.isHexDigit || $0 == ":" }), inner.contains(":") else { return false }
        return after.isEmpty || (after.hasPrefix(":") && after.dropFirst().allSatisfy(\.isNumber) && after.count > 1)
    }

    //  ponytail: no public-suffix list, so `notes.txt` is treated as a host. Swap
    //  one in if users complain; the failure mode is a wasted DNS lookup, not a
    //  wrong page.
    /// At least two labels, and a last label that looks like a TLD: two or more
    /// letters. Rejects `1.5` (a number) and `.com` (no host), which is the honest
    /// cost of not shipping a public-suffix list.
    private static func looksLikeDomain(_ host: String) -> Bool {
        let labels = stripPort(host).split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let tld = labels.last else { return false }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }
}

// MARK: - §3.4's search engine

/// The engines §23.1 §3.4 offers. Every one is a template carrying a `%s`
/// placeholder, the built-ins included, so `.custom` is not a second code path.
enum SearchEngine: String, Sendable, Hashable, CaseIterable {
    case duckDuckGo
    case google
    case bing
    case kagi
    case custom

    /// §9.6/§32's shipped default, and first in `allCases`: the popup's order.
    static let fallback = SearchEngine.duckDuckGo

    /// Nil for `.custom`, whose template is the user's `search.customEngineURL`.
    var template: String? {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/?q=%s"
        case .google: "https://www.google.com/search?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .kagi: "https://kagi.com/search?q=%s"
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .kagi: "Kagi"
        case .custom: "Custom"
        }
    }

    /// Where §3.4's suggestions come from, as a `%s` template like the one
    /// above. All three speak OpenSearch — `["what you typed", ["a", "b"]]` —
    /// so `SearchSuggestions` has one parser rather than three.
    ///
    /// Nil is the honest answer for the other two. Kagi's autosuggest is
    /// behind its session cookie and answers nothing useful without one, and a
    /// custom engine has given Luna a search template and said nothing about
    /// where its suggestions live. Guessing either would send the query
    /// somewhere the user did not name, which is the one thing this must not
    /// do; those engines simply have no suggestions.
    var suggestTemplate: String? {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/ac/?q=%s&type=list"
        case .google: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        case .bing: "https://api.bing.com/osjson.aspx?query=%s"
        case .kagi, .custom: nil
        }
    }
}

/// An engine plus the custom template only `.custom` consults.
struct SearchEngineSetting: Sendable, Hashable {

    /// The token a template substitutes the query for (§3.4).
    static let placeholder = "%s"

    var engine: SearchEngine = .fallback
    /// Kept while another engine is selected: switching away and back must not
    /// erase what the user typed.
    var customTemplate: String = ""
    /// §3.4's suggestions. On, which is a change of position and worth
    /// stating: it means a query you are still typing reaches the engine you
    /// have already chosen to send your searches to, and nowhere else. It is
    /// one switch away from off, and off means nothing leaves the Mac until you
    /// press Return.
    var suggestions: Bool = true

    /// Where to ask for suggestions, or nil when they are off, the engine has
    /// no endpoint, or the query is empty.
    func suggestURL(for query: String) -> URL? {
        guard suggestions, !query.isEmpty, let template = engine.suggestTemplate else { return nil }
        return Self.url(from: template, searching: query)
    }

    /// Usable only once it carries the placeholder and parses as an http
    /// URL with the query substituted: `%s` alone is not a URL, and a URL
    /// without `%s` searches for nothing.
    static func isUsable(_ template: String) -> Bool {
        url(from: template, searching: "luna") != nil
    }

    /// In force, or nil when `.custom` is selected and not usable yet.
    var activeTemplate: String? {
        if let built = engine.template { return built }
        return Self.isUsable(customTemplate) ? customTemplate : nil
    }

    /// Falls back to `SearchEngine.fallback` rather than returning nil: §9.2's
    /// search row is the floor, and a half-typed custom engine must not remove it.
    func url(searching query: String) -> URL? {
        let template = activeTemplate ?? SearchEngine.fallback.template
        return template.flatMap { Self.url(from: $0, searching: query) }
    }

    /// RFC 3986's unreserved set and nothing else.
    ///
    /// Measured, and it fixes a live bug. The hard-coded engine built its
    /// URL with `URLComponents.queryItems`, which leaves `+`, `/` and `?`
    /// unescaped in a query value — so `a+b` reached the engine as `q=a+b`, two
    /// words. A space is still `%20`, exactly as before.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func url(from template: String, searching query: String) -> URL? {
        guard template.contains(placeholder),
              let escaped = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        let text = template.replacingOccurrences(of: placeholder, with: escaped)
        guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
        return url
    }
}

/// The one live copy of §3.4's engine choice.
///
/// Not `UserDefaults`: `search(for:)` runs inside `controlTextDidChange` in
/// the same frame as the keystroke (§9.7, 9.6 ms median), and a defaults read
/// there is a cross-process lookup on a path that has none today. Defaults are
/// read once, lazily, when `storage` is first touched.
///
/// Not `@MainActor`: `CommandBarRanking` is deliberately non-isolated so its
/// tests can hand-compute an order without a window, and it calls `search(for:)`.
enum SearchSettings {

    static let engineKey = "search.engine"
    static let customEngineKey = "search.customEngineURL"
    static let suggestionsKey = "search.suggestions"

    private static let storage = Mutex(stored())

    /// One uncontended `os_unfair_lock` acquire and a two-field copy.
    static var current: SearchEngineSetting { storage.withLock { $0 } }

    /// Re-reads `UserDefaults`. `SettingsDefaults.restoreAll()` removes the keys
    /// without telling this cache, so something has to; never a keystroke path.
    static func reload() { storage.withLock { $0 = stored() } }

    /// Live value first — it is what the next keystroke reads — then disk.
    static func apply(_ setting: SearchEngineSetting) {
        storage.withLock { $0 = setting }
        let defaults = UserDefaults.standard
        defaults.set(setting.engine.rawValue, forKey: engineKey)
        defaults.set(setting.customTemplate, forKey: customEngineKey)
        defaults.set(setting.suggestions, forKey: suggestionsKey)
    }

    private static func stored() -> SearchEngineSetting {
        let defaults = UserDefaults.standard
        return SearchEngineSetting(
            engine: defaults.string(forKey: engineKey).flatMap(SearchEngine.init(rawValue:)) ?? .fallback,
            customTemplate: defaults.string(forKey: customEngineKey) ?? "",
            suggestions: defaults.object(forKey: suggestionsKey) as? Bool ?? true
        )
    }
}
