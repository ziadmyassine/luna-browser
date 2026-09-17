//
//  CommandBarModel.swift
//  Luna
//
//  §9.2's result vocabulary and its direct URL / IP / `localhost` detection, as
//  plain values. Pure on purpose — no AppKit, no store, no clock — which is what
//  lets §9.3's ranking be asserted against hand-computed numbers in
//  `CommandBarRankingTests` instead of by driving a window.
//
//  **§9.6 privacy, structurally rather than as a promise.** Nothing under
//  `UI/CommandBar` references a networking type. A query leaves this module in
//  exactly three shapes: a tab id to activate, a URL to *navigate to*, or an app
//  command. Search-engine suggestions (§9.2, §9.6) are deliberately not built —
//  they are the one source that would need a network call, and they are deferred
//  until §9.6's opt-out exists. `CommandBarPrivacyTests` greps these sources for
//  networking symbols and fails if one ever appears, so the guarantee outlives
//  this comment.
//

import BrowserKit
import Foundation

// MARK: - What a row does

/// Every effect the Command Bar can have. A closed enum is the §9.6 guarantee in
/// the type system: there is no case that sends a query anywhere.
enum CommandBarAction: Sendable, Hashable {
    /// Switch to a tab that is already open, possibly in another Space (§9.2).
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

/// Where a result came from. **The order of the cases is the tier order of §9.3**
/// — `Comparable` is synthesised from declaration order, and `CommandBarRanking`
/// sorts on it before it looks at any score.
enum CommandBarSource: Sendable, Hashable, Comparable, CaseIterable {
    /// §9.3: "adaptive matches rank *above* all frecency results." Literally all
    /// of them, which is why this case is first.
    case adaptive
    /// The user typed something unambiguous. A guess must not outrank an instruction.
    case directURL
    /// Already open, so switching costs nothing and reopening costs a process (§19).
    case openTab
    case history
    case archive
    case command
    /// The floor: there is always something to do with a query.
    case search
}

/// The Space badge §9.2 asks for on a cross-Space tab. `RGBA`, not `NSColor`,
/// so the ranking stays AppKit-free and testable.
struct SpaceBadge: Sendable, Hashable {
    var name: String
    var colour: RGBA
    var symbolName: String
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
    var badge: SpaceBadge?
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
        badge: SpaceBadge? = nil,
        score: Double = 0,
        symbolName: String
    ) {
        self.id = url.map(CommandBarURL.dedupeKey) ?? "\(action)"
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.url = url
        self.badge = badge
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
    /// `localhost:8080` is not, so what *follows* the colon decides it: a real
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
