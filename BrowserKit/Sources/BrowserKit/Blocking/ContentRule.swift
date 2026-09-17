import Foundation

/// One rule in WebKit's content-blocker JSON schema (§17.1).
///
/// The key names are WebKit's, not Swift's, so every one of them is spelled out in
/// `CodingKeys`. A misspelled key is **not** an error: unknown trigger keys compile
/// happily and are then ignored, so a typo here is a rule that quietly matches more than
/// it should (measured 2026-09-17 — `"totally-made-up"` compiled without complaint).
public struct ContentRule: Codable, Sendable, Hashable {

    public struct Trigger: Codable, Sendable, Hashable {
        /// A regular expression over the *whole* URL, in WebKit's own restricted dialect.
        /// See ``ContentRuleLimits`` for what that dialect does not have.
        public var urlFilter: String
        public var urlFilterIsCaseSensitive: Bool?
        /// Lowercase, punycoded domains — see ``ContentRuleLimits/domainsMustBeLowercaseASCII``.
        /// A bare domain matches that host **only**; `*` in front also matches subdomains.
        public var ifDomain: [String]?
        public var unlessDomain: [String]?
        public var resourceType: [String]?
        public var loadType: [String]?
        /// `top-frame` / `child-frame`. This is what lets `$subdocument` mean "iframes"
        /// instead of "also the page itself" — WebKit has no `subdocument` resource type.
        public var loadContext: [String]?

        public init(
            urlFilter: String,
            urlFilterIsCaseSensitive: Bool? = nil,
            ifDomain: [String]? = nil,
            unlessDomain: [String]? = nil,
            resourceType: [String]? = nil,
            loadType: [String]? = nil,
            loadContext: [String]? = nil
        ) {
            self.urlFilter = urlFilter
            self.urlFilterIsCaseSensitive = urlFilterIsCaseSensitive
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
            self.resourceType = resourceType
            self.loadType = loadType
            self.loadContext = loadContext
        }

        // WebKit's key names are not Swift's, so `CodingKeys` has to live here, one
        // level deeper than the linter likes. The alternative is hoisting `Trigger` out
        // of `ContentRule`, which costs every call site to satisfy a style rule.
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case loadContext = "load-context"
        }
    }

    public struct Action: Codable, Sendable, Hashable {
        public var type: String
        /// Only for `css-display-none`.
        public var selector: String?

        public static let block = Action(type: "block")
        public static let ignorePrevious = Action(type: "ignore-previous-rules")
        public static func hide(_ selector: String) -> Action { Action(type: "css-display-none", selector: selector) }

        public init(type: String, selector: String? = nil) {
            self.type = type
            self.selector = selector
        }
    }

    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

/// What the engine actually accepts. **Every number and every string here was measured
/// against the shipping SDK on 2026-09-17 (macOS 26, Xcode 26.6)** rather than read
/// (§0.3), because each of them fails the *whole list* rather than the one bad rule.
public enum ContentRuleLimits {

    /// Measured exactly, by bisection: 150,000 rules compile; 150,001 fails with
    /// `"Rule list compilation failed: Too many rules in JSON array."` This confirms
    /// §17.1's "~150,000" as an exact, hard cap on the JSON array length.
    public static let maxRulesPerList = 150_000

    /// The only strings `resource-type` accepts. Anything else — including ABP's own
    /// `xmlhttprequest`, `object` and `subdocument` — fails the compile with
    /// `"Invalid string in the trigger flags array."`, so the converter maps into this
    /// set and never passes a filter-list token through.
    public static let resourceTypes: Set<String> = [
        "document", "image", "style-sheet", "script", "font", "raw", "svg-document",
        "media", "popup", "ping", "fetch", "websocket", "other"
    ]

    /// `url-filter` is *not* ICU regex. Measured rejections:
    /// - `(a|b)` → "Disjunctions are not supported yet."
    /// - `a{2,4}` → "Arbitrary atom repetitions are not supported."
    /// - `\d` → "Character class is not supported."
    ///
    /// Measured acceptances: `.`, `*`, `+`, `?`, `^`, `$`, `(…)` groups and `[…]` /
    /// `[^…]` literal classes. So the ABP separator `^` cannot become
    /// `([^…]|$)` the way the common converters write it — there is no alternation.
    public static let urlFilterSupportsAlternation = false

    /// `if-domain`/`unless-domain` entries that are not lowercase ASCII fail with
    /// `"Domains must be lower case ASCII. Use punycode to encode non-ASCII characters."`
    /// — a hard compile error, **not** the silent non-match §17.1 warns about, and it
    /// takes every other rule in the list down with it.
    public static let domainsMustBeLowercaseASCII = true
}
