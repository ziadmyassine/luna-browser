import Foundation
import WebKit

/// §3.2's Local Network permission, as a content rule list.
///
/// macOS asks an app once whether it may talk to the local network; a browser has to ask
/// per site, because the app is only ever the messenger. WebKit has no per-origin hook for
/// that — no delegate callback, no `WKWebpagePreferences` flag — so Luna refuses the loads:
/// a page without the permission cannot fetch `192.168.1.1`, `printer.local` or
/// `localhost`.
///
/// A page served from the local network is exempt: `unless-top-url` carries the same
/// patterns as the trigger, so `localhost:3000` may reach its own assets, its own API and
/// the rest of the LAN without being asked. That is the difference between a permission
/// and a firewall.
///
/// Twenty-one rules, measured compiling in 0.006 s — so unlike §17.1's filter lists it is
/// compiled on the spot rather than cached against a content hash.
///
/// The patterns and the JSON are `public` so a test can check WebKit accepts them: the
/// compile is a fire-and-forget `Task`, so a refused pattern leaves the list nil, nothing
/// blocked, and a checkmark in §3.2's menu that means nothing.
extension ContentBlocker {

    public static let localNetworkIdentifier = "\(prefix)localnetwork-1"

    /// The host halves of the patterns: addresses that are on this Mac or on the network
    /// it is plugged into. RFC 1918's three ranges, loopback in both families, link-local,
    /// and Bonjour's `.local`.
    ///
    /// No `|` anywhere. WebKit's URL-filter engine takes a documented subset of
    /// regular expressions, and it is smaller than it looks: `([:/]|$)` is refused with
    /// `Error while parsing … : Disjunctions are not supported yet` (measured, by handing
    /// each pattern to `compileContentRuleList`). So alternation is spelled out as
    /// separate patterns, the 172.16–172.31 range is three character classes rather than
    /// one alternation, and the shorthand classes (`\d`) are not used either.
    static let privateHostPatterns = [
        "localhost",
        "127\\.[0-9]+\\.[0-9]+\\.[0-9]+",
        "10\\.[0-9]+\\.[0-9]+\\.[0-9]+",
        "192\\.168\\.[0-9]+\\.[0-9]+",
        "172\\.1[6-9]\\.[0-9]+\\.[0-9]+",
        "172\\.2[0-9]\\.[0-9]+\\.[0-9]+",
        "172\\.3[01]\\.[0-9]+\\.[0-9]+",
        "169\\.254\\.[0-9]+\\.[0-9]+",
        "\\[::1\\]",
        "[^/:]+\\.local"
    ]

    /// One pattern per host, per way a host can end: a port or a path follows it, or the
    /// URL stops there. Both are needed and neither alone is enough — `http://10.0.0.1`
    /// has nothing after the host, and `http://10.0.0.1/status` does. The terminator is
    /// also what stops `10.0.0.1` matching `10.0.0.1.example.com`.
    ///
    /// The IPv6 link-local prefix is the exception: `fe80::` addresses carry a zone and a
    /// variable tail, so the opening is the whole test.
    public static var privateAddressPatterns: [String] {
        privateHostPatterns.flatMap { host in
            ["^[^:]+://\(host)[:/]", "^[^:]+://\(host)$"]
        } + ["^[^:]+://\\[fe80:"]
    }

    /// The rule list, as WebKit's JSON. One rule per pattern, each exempting a top-level
    /// document that is itself on the local network.
    public static var localNetworkRules: String {
        let rules = privateAddressPatterns.map { pattern in
            """
            {"trigger":{"url-filter":"\(escaped(pattern))","unless-top-url":[\(topURLPatterns)]},\
            "action":{"type":"block"}}
            """
        }
        return "[\(rules.joined(separator: ","))]"
    }

    private static var topURLPatterns: String {
        privateAddressPatterns.map { "\"\(escaped($0))\"" }.joined(separator: ",")
    }

    /// The patterns are Swift string literals, so the backslashes in them are real
    /// characters by the time they get here — and JSON wants each one doubled again.
    private static func escaped(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "\\", with: "\\\\")
    }

    /// Compiles the list, or finds the one already compiled. Called from ``start``.
    func prepareLocalNetworkList() async {
        if let existing = try? await ruleListStore.contentRuleList(forIdentifier: Self.localNetworkIdentifier) {
            localNetworkList = existing
            return
        }
        localNetworkList = try? await ruleListStore.compileContentRuleList(
            forIdentifier: Self.localNetworkIdentifier,
            encodedContentRuleList: Self.localNetworkRules
        )
    }
}
