import Foundation

/// EasyList-syntax text → WebKit's content-blocker rules (§17.1).
///
/// The governing fact: one bad rule fails the entire list, not itself. A rejected
/// regex, an uppercase domain or an unknown `resource-type` string takes all 150,000
/// rules down with it. So everything here is a whitelist — a construct we have not
/// measured as accepted is dropped, and `skipped` counts what went. Coverage is a thing
/// we can improve; a list that will not compile is a browser with no blocking at all.
public enum FilterListConverter {

    public struct Conversion: Sendable {
        /// `block` rules, in list order.
        public var blocks: [ContentRule] = []
        /// `css-display-none` rules (§17.3) — shipped in the list so there is no flicker.
        public var hides: [ContentRule] = []
        /// `ignore-previous-rules`. WebKit applies these against rules **earlier in the
        /// same array**, so they always go last and they never leave their chunk.
        public var exceptions: [ContentRule] = []
        /// Lines we understood to be rules but could not express. Not an error — EasyList
        /// carries plenty that WebKit has no equivalent for — but a number worth watching.
        public var skipped = 0

        public var rules: [ContentRule] { blocks + hides + exceptions }
        public var count: Int { blocks.count + hides.count + exceptions.count }

        /// Splits into lists that each fit ``ContentRuleLimits/maxRulesPerList``.
        ///
        /// Every chunk carries the whole exception set, because `ignore-previous-rules`
        /// cannot reach across into another compiled list: an exception separated from the
        /// block rule it cancels is a site that mysteriously breaks. Exceptions are a few
        /// percent of a list, so paying for them per chunk is cheaper than being wrong.
        public func chunked(maxRules: Int = ContentRuleLimits.maxRulesPerList) -> [[ContentRule]] {
            let positives = blocks + hides
            let room = max(1, maxRules - exceptions.count)
            guard !positives.isEmpty else { return exceptions.isEmpty ? [] : [Array(exceptions.prefix(maxRules))] }
            return stride(from: 0, to: positives.count, by: room).map {
                Array(positives[$0 ..< min($0 + room, positives.count)]) + exceptions
            }
        }
    }

    // MARK: - Entry point

    public static func convert(_ text: String) -> Conversion {
        var result = Conversion()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // `!` is a comment, `[Adblock Plus 2.0]` a header, `#` alone a legacy comment.
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { continue }
            convert(line: trimmed, into: &result)
        }
        return result
    }

    private static func convert(line: String, into result: inout Conversion) {
        if let separator = elementHidingSeparator(in: line) {
            appendHide(line: line, separator: separator, into: &result)
        } else if line.hasPrefix("@@") {
            appendNetwork(pattern: String(line.dropFirst(2)), action: .ignorePrevious, into: &result)
        } else {
            appendNetwork(pattern: line, action: .block, into: &result)
        }
    }

    // MARK: - Element hiding (§17.3)

    /// The range of a plain `##` separator, or nil when this is not an element-hiding
    /// rule or is one of the extended syntaxes WebKit has no answer for (`#@#` unhide,
    /// `#?#`/`#$?#` extended CSS, `#$#`/`#%#` scriptlets).
    private static func elementHidingSeparator(in line: String) -> Range<String.Index>? {
        guard let hash = line.range(of: "##") else { return nil }
        let before = line[..<hash.lowerBound]
        if before.hasSuffix("#") || before.hasSuffix("@") || before.hasSuffix("?") || before.hasSuffix("$") {
            return nil
        }
        return hash
    }

    private static func appendHide(line: String, separator: Range<String.Index>, into result: inout Conversion) {
        let selector = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard isSupportedSelector(selector) else { result.skipped += 1; return }

        let domainText = String(line[..<separator.lowerBound])
        var trigger = ContentRule.Trigger(urlFilter: ".*")
        if !domainText.isEmpty {
            guard let domains = domainList(domainText, separator: ",") else { result.skipped += 1; return }
            trigger.ifDomain = domains.include.isEmpty ? nil : domains.include
            trigger.unlessDomain = domains.exclude.isEmpty ? nil : domains.exclude
        }
        result.hides.append(ContentRule(trigger: trigger, action: .hide(selector)))
    }

    /// EasyList's procedural pseudo-classes are uBlock/ABP extensions, not CSS. WebKit
    /// rejects the list outright if one reaches it, so they are dropped by name.
    /// `:has()` is deliberately not on this list: it is real CSS and WebKit ships it.
    private static let unsupportedSelectorTokens = [
        ":-abp-", ":style(", ":remove(", ":matches-", ":contains(", ":has-text(", ":xpath(",
        ":upward(", ":nth-ancestor(", ":watch-attr(", ":min-text-length(", ":others(", ":if("
    ]

    private static func isSupportedSelector(_ selector: String) -> Bool {
        guard !selector.isEmpty, selector.allSatisfy(\.isASCII) else { return false }
        // `##^responseheader(...)` and `##+js(...)` are HTML filtering and scriptlets.
        guard !selector.hasPrefix("^"), !selector.hasPrefix("+js") else { return false }
        return !unsupportedSelectorTokens.contains { selector.contains($0) }
    }

    // MARK: - Network rules

    private static func appendNetwork(pattern: String, action: ContentRule.Action, into result: inout Conversion) {
        var body = pattern
        var options = ""
        // The option separator is the last unescaped `$`; a `$` inside the pattern is
        // legal (query strings have them).
        if let dollar = body.lastIndex(of: "$"), dollar != body.startIndex,
           body[body.index(before: dollar)] != "\\" {
            options = String(body[body.index(after: dollar)...])
            body = String(body[..<dollar])
        }

        var trigger = ContentRule.Trigger(urlFilter: ".*")
        guard let parsed = Options.parse(options) else { result.skipped += 1; return }

        // `@@…$document` (and its `elemhide`/`generichide` cousins) is EasyList's "turn
        // blocking off on this site" rule. It is about the page, not the resource, so it
        // becomes an `if-domain` exception rather than a URL match — the one mapping that
        // makes a whitelisted site actually work.
        if action.type == ContentRule.Action.ignorePrevious.type, parsed.isDocumentScope,
           let host = hostAnchor(in: body) {
            guard let domain = Punycode.asciiDomain("*" + host) else { result.skipped += 1; return }
            result.exceptions.append(ContentRule(trigger: .init(urlFilter: ".*", ifDomain: [domain]), action: action))
            return
        }

        guard let filter = urlFilter(for: body) else { result.skipped += 1; return }
        trigger.urlFilter = filter
        trigger.urlFilterIsCaseSensitive = parsed.matchCase ? true : nil
        trigger.resourceType = parsed.resourceTypes
        trigger.loadType = parsed.loadType
        trigger.loadContext = parsed.loadContext
        if let domains = parsed.domains {
            trigger.ifDomain = domains.include.isEmpty ? nil : domains.include
            trigger.unlessDomain = domains.exclude.isEmpty ? nil : domains.exclude
        }
        // Measured: a trigger carrying both fails the list with "A trigger cannot have
        // more than one condition (if-domain, unless-domain, if-top-url, or
        // unless-top-url)". `if-domain` is the one to keep — losing the `~` exclusion
        // over-blocks one subdomain, where dropping the rule would not block at all.
        if trigger.ifDomain != nil { trigger.unlessDomain = nil }

        let rule = ContentRule(trigger: trigger, action: action)
        if action.type == ContentRule.Action.ignorePrevious.type {
            result.exceptions.append(rule)
        } else {
            result.blocks.append(rule)
        }
    }

    /// The host of a `||host^…` rule, used only for `$document` exceptions.
    private static func hostAnchor(in pattern: String) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        let rest = pattern.dropFirst(2)
        let host = rest.prefix { $0 != "^" && $0 != "/" && $0 != "*" && $0 != "|" }
        return host.isEmpty ? nil : String(host)
    }

    // MARK: - Pattern → url-filter

    /// Metacharacters of the dialect WebKit does support. Everything else is a literal
    /// and is passed through untouched — escaping punctuation WebKit does not treat as
    /// special risks "unsupported escape", which fails the list.
    private static let metacharacters: Set<Character> = [".", "^", "$", "+", "?", "(", ")", "[", "]", "{", "}", "|", "\\"]

    /// Returns nil for any pattern we cannot express, which the caller then drops.
    static func urlFilter(for pattern: String) -> String? {
        var body = Substring(pattern)
        var out = ""

        if body.hasPrefix("||") {
            // Domain anchor. `([^/?#]*\.)?` spans the optional subdomain part and cannot
            // run past the host, because it may not contain a path, query or fragment
            // delimiter. No alternation is available for the scheme, so `https?` covers
            // the web and `ws`/`ftp` rules are simply not expressed.
            out += "^https?://([^/?#]*\\.)?"
            body = body.dropFirst(2)
        } else if body.hasPrefix("|") {
            out += "^"
            body = body.dropFirst()
        }

        var anchoredEnd = false
        if body.hasSuffix("|") {
            anchoredEnd = true
            body = body.dropLast()
        }

        for character in body {
            guard let translated = translate(character) else { return nil }
            out += translated
        }

        if anchoredEnd { out += "$" }
        guard !out.isEmpty else { return nil }
        // A bare `.*` blocks the entire web. It only ever comes from a malformed line.
        return out == ".*" ? nil : out
    }

    /// One filter-list character as WebKit regex, or nil when it can never match.
    private static func translate(_ character: Character) -> String? {
        switch character {
        case "*":
            return ".*"
        case "^":
            // ABP's separator is "any character that is not a letter, digit, `_`, `-`,
            // `.` or `%`, or the end of the address". The "or end" half needs
            // alternation, which WebKit does not have (measured: "Disjunctions are not
            // supported yet"), so only the character class survives. In practice the loss
            // is nil for `||host^` rules: WebKit hands the matcher a canonical URL, which
            // always has at least the `/`.
            return "[^a-zA-Z0-9._%-]"
        case _ where metacharacters.contains(character):
            return "\\" + String(character)
        case _ where character.isASCII:
            return String(character)
        default:
            // A non-ASCII literal can never match: WebKit matches the percent-encoded URL.
            return nil
        }
    }

    // MARK: - Domain lists

    static func domainList(_ text: String, separator: Character) -> (include: [String], exclude: [String])? {
        var include: [String] = []
        var exclude: [String] = []
        for entry in text.split(separator: separator) where !entry.isEmpty {
            let negated = entry.hasPrefix("~")
            let raw = negated ? String(entry.dropFirst()) : String(entry)
            // Regex-valued domains (`/…/`) are an ABP extension with no WebKit form.
            guard !raw.hasPrefix("/") else { return nil }
            // EasyList's `domain=` means the domain and its subdomains; WebKit's bare
            // entry means that host exactly, and `*` in front is what widens it
            // (measured: `example.com` does not match `ads.example.com`; `*example.com`
            // matches both). Getting this wrong is a rule that compiles and never fires.
            guard let domain = Punycode.asciiDomain("*" + raw) else { return nil }
            if negated { exclude.append(domain) } else { include.append(domain) }
        }
        return include.isEmpty && exclude.isEmpty ? nil : (include, exclude)
    }
}

extension FilterListConverter {

    /// The `$`-options of one network rule, reduced to what WebKit can express.
    struct Options {
        var resourceTypes: [String]?
        var loadType: [String]?
        var loadContext: [String]?
        var domains: (include: [String], exclude: [String])?
        var matchCase = false
        /// `$document`, `$elemhide`, `$generichide`, `$specifichide` — page-scoped, which
        /// only means anything on an `@@` exception.
        var isDocumentScope = false

        /// ABP type token → a measured-valid WebKit `resource-type`. Anything not in
        /// here is either handled as a flag below or makes the rule unconvertible.
        static let types: [String: String] = [
            "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
            "font": "font", "media": "media", "websocket": "websocket",
            "ping": "ping", "beacon": "ping",
            // WebKit has no `xmlhttprequest`; `fetch` is the same class of load and is the
            // only one of the two the engine accepts.
            "xmlhttprequest": "fetch", "xhr": "fetch",
            "object": "other", "object-subrequest": "other", "other": "other",
            "popup": "popup"
        ]

        /// Options with no WebKit equivalent at all. A rule carrying one is dropped
        /// rather than approximated: `$redirect` silently degraded to `block` breaks
        /// sites that expect the stub resource, and `$badfilter` means the opposite of
        /// what blindly keeping it would do.
        static let unconvertible: Set<String> = [
            "csp", "redirect", "redirect-rule", "rewrite", "removeparam", "replace", "badfilter",
            "genericblock", "inline-script", "inline-font", "webrtc", "empty", "mp4", "stealth",
            "cookie", "network", "app", "denyallow", "to", "method", "header", "permissions",
            "urltransform", "extension", "jsonprune", "hls", "referrerpolicy"
        ]

        // swiftlint:disable cyclomatic_complexity
        /// Returns nil when the rule cannot be converted at all.
        ///
        /// One flat switch over a token vocabulary. Splitting it to lower the complexity
        /// count would spread one table across three functions and hide nothing.
        static func parse(_ text: String) -> Options? {
            var options = Options()
            var include: Set<String> = []
            var exclude: Set<String> = []
            guard !text.isEmpty else { return options }

            for raw in text.split(separator: ",") {
                let negated = raw.hasPrefix("~")
                let token = String(negated ? raw.dropFirst() : raw)
                let name = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
                let value = token.contains("=") ? String(token.split(separator: "=", maxSplits: 1)[1]) : nil

                switch name {
                case "domain":
                    guard let value, let list = domainList(value, separator: "|") else { return nil }
                    options.domains = list
                case "third-party", "3p":
                    options.loadType = [negated ? "first-party" : "third-party"]
                case "first-party", "1p", "strict1p":
                    options.loadType = [negated ? "third-party" : "first-party"]
                case "match-case":
                    options.matchCase = true
                case "document", "doc":
                    if negated { continue }
                    options.isDocumentScope = true
                    include.insert("document")
                    options.loadContext = ["top-frame"]
                case "elemhide", "generichide", "specifichide", "ehide", "ghide":
                    options.isDocumentScope = true
                case "subdocument", "frame":
                    // Not `document` on its own: that would also match the top-level page
                    // load and turn an iframe rule into "this site will not open".
                    if negated { exclude.insert("document") } else {
                        include.insert("document")
                        options.loadContext = ["child-frame"]
                    }
                case "all", "popunder", "important":
                    continue
                case _ where unconvertible.contains(name):
                    return nil
                case _ where types[name] != nil:
                    guard let mapped = types[name] else { return nil }
                    if negated { exclude.insert(mapped) } else { include.insert(mapped) }
                default:
                    // An option nobody here has seen. Dropping the rule is the safe half
                    // of the bet: keeping it means guessing at a restriction we did not
                    // apply, which over-blocks.
                    return nil
                }
            }

            if !include.isEmpty {
                options.resourceTypes = include.sorted()
            } else if !exclude.isEmpty {
                // `$~script` is "everything except scripts", which WebKit can only say by
                // listing the rest.
                options.resourceTypes = ContentRuleLimits.resourceTypes.subtracting(exclude).sorted()
            }
            return options
        }
        // swiftlint:enable cyclomatic_complexity
    }
}
