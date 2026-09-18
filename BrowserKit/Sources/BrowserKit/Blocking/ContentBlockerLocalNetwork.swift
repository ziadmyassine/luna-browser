import Foundation
import WebKit

/// §3.2's **Local Network** permission, as a content rule list.
///
/// macOS asks an app once whether it may talk to the local network; a browser has to ask
/// it per *site*, because the app is only ever the messenger. WebKit exposes no per-origin
/// hook for that — there is no delegate callback and no `WKWebpagePreferences` flag — so
/// what Luna can honestly offer is the thing a content rule list already does well: refuse
/// the loads. A page that has not been given the permission cannot fetch `192.168.1.1`,
/// `printer.local` or `localhost`, and one that has been given it can.
///
/// **A page served *from* the local network is exempt.** `unless-top-url` carries the same
/// patterns as the trigger, so `localhost:3000` may load its own assets, talk to its own
/// API and reach the rest of the LAN without ever being asked — which is the difference
/// between a permission and a firewall, and the difference between this shipping and this
/// making Luna useless to develop in.
///
/// Twenty-one rules. Compiling them measured at 0.006 s, four hundred times cheaper than
/// §17.1's smallest filter list — so unlike those it is compiled on the spot rather than
/// cached against a content hash.
///
/// The patterns and the JSON are `public` so a test can hand them to WebKit and find out
/// whether it accepts them. It has to: the compile is a fire-and-forget `Task`, so a
/// pattern WebKit refuses leaves the list nil, nothing blocked and a checkmark in §3.2's
/// menu that means nothing — the one failure here that is completely silent.
extension ContentBlocker {

    public static let localNetworkIdentifier = "\(prefix)localnetwork-1"

    /// The host halves of the patterns: addresses that are on this Mac or on the network
    /// it is plugged into. RFC 1918's three ranges, loopback in both families, link-local,
    /// and Bonjour's `.local`.
    ///
    /// **No `|` anywhere.** WebKit's URL-filter engine takes a documented subset of
    /// regular expressions, and it is smaller than it looks: `Error while parsing … :
    /// Disjunctions are not supported yet` is what a first pass got back for
    /// `([:/]|$)` — measured, by handing each pattern to `compileContentRuleList` and
    /// reading what it threw. So alternation is spelled out as separate patterns, the
    /// 172.16–172.31 range is three character classes rather than one alternation, and
    /// the shorthand classes (`\d`) are not used either.
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
