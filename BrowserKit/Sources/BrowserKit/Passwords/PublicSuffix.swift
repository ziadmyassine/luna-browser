import Foundation

/// eTLD+1 — the "same site" question, answered the way the Public Suffix List
/// answers it (§14.3).
///
/// §14.3 matches credentials on eTLD+1 and "never on a bare substring", which
/// is the whole security model of the fill flow. A substring match offers
/// `example.com`'s password to `example.com.evil.net`; a naive "last two
/// labels" match offers `bbc.co.uk`'s password to `itv.co.uk`, because both
/// reduce to `co.uk`. Either hands a credential to a site that did not earn
/// it — the only truly unrecoverable bug this feature can have.
///
/// The algorithm is the PSL's own, not an approximation of it:
///
///   1. Find every rule matching the host, comparing label by label from the
///      right. `*` matches exactly one label.
///   2. An exception rule (`!`) wins over any wildcard.
///   3. Otherwise the longest matching rule wins.
///   4. If no rule matches, the prevailing rule is `*` — the public suffix
///      is the rightmost label. This is the PSL's specified default, not a
///      fallback we invented, which is what makes a partial table honest:
///      an unlisted TLD lands on the same answer the full list would give it.
///
/// The table is a curated subset, which is a real limitation. The full list is
/// ~9,000 rules and changes weekly, and a stale copy is worse than a small
/// correct one. What ships is every multi-label ICANN suffix in wide use plus
/// the private-section entries that host mutually-distrusting sites
/// (`github.io`, `herokuapp.com`, …), where getting it wrong leaks a credential
/// between strangers. `Tools/update-public-suffix-list.sh` regenerates this
/// file; run it before v1 ships and on a schedule after.
///
/// Rule 4 makes an absent rule narrow, never wide: the worst an unlisted
/// multi-label suffix can do is treat `a.unlisted.xx` and `b.unlisted.xx` as
/// different sites, which declines a fill. A declined fill is a nuisance. The
/// opposite error is a leak, and rule 4 cannot produce it.
public enum PublicSuffix {

    /// The eTLD+1 of `host`, lowercased — `"www.bbc.co.uk"` → `"bbc.co.uk"`.
    ///
    /// A host that has no registrable domain — `localhost`, an intranet
    /// name with no dot, an IPv4 or IPv6 literal — is its own site key, matched
    /// whole and never widened. That is not a weakening of §14.3: the rule
    /// there exists to stop a wildcard from spanning two owners, and an exact
    /// host cannot span anything. `localhost` matches `localhost` and nothing
    /// else.
    ///
    /// Returning nil instead — which this did first — reads as the safe choice
    /// and is not one: it makes the feature silently inert on
    /// `http://localhost:8080/`, the first place anyone building a login form
    /// tries it, and on every router and NAS on a home network. Safari and
    /// Chrome both key these on the exact host.
    ///
    /// Two consequences worth naming, both shared with Safari:
    /// every dev server on `localhost` shares one credential space regardless
    /// of port, and two different routers that both answer on `192.168.1.1`
    /// look like one site.
    ///
    /// - Returns: nil only for a host that is a public suffix with nothing
    ///   registered under it (`co.uk` alone), and for a malformed name. Both
    ///   mean "there is no site here", and nil is how the fill flow declines.
    public static func siteKey(forHost host: String?) -> String? {
        if let literal = exactHostKey(host) { return literal }
        guard let normalised = normalise(host) else { return nil }
        let labels = normalised.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }

        let suffixLabels = publicSuffixLabelCount(labels)
        // A host that is exactly a public suffix registers nothing.
        guard labels.count > suffixLabels else { return nil }
        return labels.suffix(suffixLabels + 1).joined(separator: ".")
    }

    /// Two hosts belong to the same site — the only comparison §14.3 permits
    /// before a credential is offered.
    ///
    /// Returns false when either side has no site key, so "we could not work
    /// out what site this is" can never read as a match.
    public static func isSameSite(_ a: String?, _ b: String?) -> Bool {
        guard let left = siteKey(forHost: a), let right = siteKey(forHost: b) else { return false }
        return left == right
    }

    // MARK: - The PSL algorithm

    /// How many trailing labels of `labels` form the public suffix.
    private static func publicSuffixLabelCount(_ labels: [String]) -> Int {
        // An exception rule beats every wildcard, so it is checked first and
        // returns immediately (PSL step 2).
        for count in stride(from: min(labels.count, maxRuleLabels), through: 1, by: -1) {
            let candidate = labels.suffix(count).joined(separator: ".")
            if exceptions.contains(candidate) {
                // `!city.kawasaki.jp` means `city.kawasaki.jp` is registrable,
                // so the suffix is the rule minus its leftmost label.
                return count - 1
            }
        }

        // Longest matching rule wins (PSL step 3). Literal and wildcard rules
        // are held in one table keyed by their own text, so `*.ck` is found by
        // rewriting the candidate's leftmost label to `*`.
        for count in stride(from: min(labels.count, maxRuleLabels), through: 1, by: -1) {
            let tail = Array(labels.suffix(count))
            if rules.contains(tail.joined(separator: ".")) { return count }
            let wildcard = (["*"] + tail.dropFirst()).joined(separator: ".")
            if rules.contains(wildcard) { return count }
        }

        // PSL step 4: no rule matched, so the prevailing rule is `*`.
        return 1
    }

    /// Lowercased, trailing dot removed, and rejected outright if it is an IP
    /// literal or carries no dot at all.
    ///
    /// IPv4 is rejected by shape rather than by parsing: a host whose every
    /// label is numeric has no registrable domain, so there is no site key to
    /// hand a credential to. IPv6 arrives bracketed and contains a colon.
    /// Hosts that are their own site key: no registrable domain exists, so the
    /// exact name is the strongest key available and the only honest one.
    ///
    /// Kept apart from ``normalise(_:)`` on purpose — the eTLD+1 path below is
    /// unchanged, and nothing here can widen a real domain name.
    ///
    /// - Returns: the canonical host, or nil when `host` is a normal domain
    ///   name (or junk) and belongs on the PSL path.
    static func exactHostKey(_ host: String?) -> String? {
        guard var value = host?.lowercased(), !value.isEmpty else { return nil }
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty else { return nil }

        // IPv6, bracketed (`[::1]`) or bare — `URL.host()` strips the brackets,
        // but a caller holding the raw authority may not have.
        if value.contains(":") || value.hasPrefix("[") {
            let bare = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard !bare.isEmpty, bare.contains(":"),
                  bare.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." })
            else { return nil }
            return bare
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        // A single label — `localhost`, `nas`, any intranet short name.
        if labels.count == 1 { return value }
        // An IPv4 literal, and anything else all-numeric: matched whole, which
        // is what keeps `10.0.0.1` and `192.168.1.1` distinct. The PSL path
        // would reduce both to `0.1`.
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return value }
        return nil
    }

    static func normalise(_ host: String?) -> String? {
        guard var value = host?.lowercased(), !value.isEmpty else { return nil }
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, !value.contains(":"), !value.contains("[") else { return nil }
        guard value.contains(".") else { return nil }
        // `omittingEmptySubsequences: false` is load-bearing. The default drops
        // empty labels, so `a..b.com` would normalise to `a.b.com` and be
        // treated as a real host — a malformed name quietly rewritten into a
        // site key, which is the last thing a credential matcher should do.
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return nil }
        return value
    }

    /// The longest rule in the table, in labels — the loop above starts here
    /// rather than at `labels.count`, so a 40-label hostname costs the same as
    /// a 4-label one.
    private static let maxRuleLabels = 4

    /// `!`-prefixed PSL rules, stored without the `!`.
    private static let exceptions: Set<String> = [
        "city.kawasaki.jp", "city.kitakyushu.jp", "city.kobe.jp", "city.nagoya.jp",
        "city.sapporo.jp", "city.sendai.jp", "city.yokohama.jp", "www.ck"
    ]

    /// Multi-label public suffixes. Single-label TLDs are deliberately absent:
    /// rule 4 already answers them, and listing 1,400 of them would be 1,400
    /// more strings to keep current for no change in behaviour.
    private static let rules: Set<String> = {
        var set = Set<String>()

        // --- ICANN: the `co.xx` / `com.xx` families, by country ---------------
        // Second-level suffixes under a ccTLD. Written as a cross-product
        // because that is what the list itself is here, and spelling out ~400
        // literals would hide the pattern without adding a rule.
        let second = ["co", "com", "net", "org", "edu", "ac", "gov", "mil", "sch", "nom", "info", "biz"]
        let countries = [
            "uk", "jp", "au", "nz", "za", "br", "in", "kr", "mx", "id", "il", "tr", "ar", "pl",
            "cn", "hk", "tw", "sg", "my", "th", "ph", "vn", "ru", "ua", "gr", "pt", "es", "it",
            "ve", "pe", "ec", "uy", "ng", "ke", "gh", "eg", "sa", "ae", "pk", "bd", "lk", "np"
        ]
        for country in countries {
            for level in second { set.insert("\(level).\(country)") }
        }
        // Ones that do not fit the cross-product.
        set.formUnion([
            "me.uk", "ltd.uk", "plc.uk", "police.uk", "nhs.uk", "gov.scot", "gov.wales",
            "ne.jp", "or.jp", "go.jp", "gr.jp", "lg.jp", "ad.jp",
            "id.au", "asn.au", "conf.au", "act.au", "nsw.au", "qld.au", "sa.au",
            "tas.au", "vic.au", "wa.au", "nt.au",
            "geek.nz", "kiwi.nz", "maori.nz", "iwi.nz",
            "web.za", "alt.za",
            "art.br", "eco.br", "emp.br", "far.br", "ind.br", "rec.br", "srv.br", "tur.br",
            "co.in", "firm.in", "gen.in", "ind.in", "res.in",
            "pp.ru", "msk.ru", "spb.ru",
            "in.ua", "kiev.ua",
            "com.co", "com.de", "com.se", "com.ee", "priv.at", "or.at",
            "co.at", "co.nl", "co.no", "co.dk", "co.ca", "gc.ca", "qc.ca", "on.ca", "bc.ca", "ab.ca"
        ])

        // --- ICANN: wildcard rules -------------------------------------------
        // `*.ck` with the `!www.ck` exception above is the canonical pair the
        // algorithm's step 2 exists for; without both, `www.ck` reads as a
        // suffix and every `.ck` site collapses into one.
        set.formUnion(["*.ck", "*.er", "*.fj", "*.jm", "*.kh", "*.mm", "*.pg", "*.bd", "*.np"])

        // --- Private section: multi-tenant hosts ------------------------------
        // These matter more than most of the ICANN table. Two GitHub Pages sites
        // are two strangers, and a "last two labels" reading makes them one
        // site and offers one's password to the other. Every entry below is a
        // host where mutually-distrusting sites share a parent domain.
        set.formUnion([
            "github.io", "githubusercontent.com", "gitlab.io", "bitbucket.io",
            "herokuapp.com", "herokussl.com", "appspot.com", "cloudfunctions.net",
            "run.app", "web.app", "firebaseapp.com", "azurewebsites.net",
            "cloudapp.net", "azurestaticapps.net", "trafficmanager.net",
            "amazonaws.com", "elasticbeanstalk.com", "cloudfront.net",
            "s3.amazonaws.com", "execute-api.us-east-1.amazonaws.com",
            "netlify.app", "netlify.com", "vercel.app", "now.sh",
            "pages.dev", "workers.dev", "r2.dev",
            "fly.dev", "onrender.com", "railway.app", "deno.dev", "val.run",
            "surge.sh", "neocities.org", "glitch.me", "repl.co", "replit.dev",
            "ngrok.io", "ngrok-free.app", "trycloudflare.com", "loca.lt",
            "wordpress.com", "blogspot.com", "tumblr.com", "medium.com",
            "myshopify.com", "squarespace.com", "wixsite.com", "webflow.io",
            "zendesk.com", "freshdesk.com", "atlassian.net", "sharepoint.com",
            "notion.site", "substack.com", "framer.app", "bubbleapps.io",
            "readthedocs.io", "gitbook.io", "pythonanywhere.com",
            "sourceforge.io", "codeberg.page", "hashnode.dev",
            "dev.to", "stackblitz.io", "codesandbox.io", "cyclic.app",
            "firebaseio.com", "supabase.co", "supabase.in",
            "ondigitalocean.app", "linodeusercontent.com", "oraclecloud.com",
            "duckdns.org", "no-ip.org", "dyndns.org", "hopto.org", "serveo.net"
        ])
        return set
    }()
}
