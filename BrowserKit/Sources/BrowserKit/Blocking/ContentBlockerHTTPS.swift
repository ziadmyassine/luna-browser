import Foundation

/// §17.6: every main-frame http address is tried over https first. HTTPS-only mode
/// shows the downgrade page when that fails; otherwise, HTTPS-first, the http
/// address loads quietly instead, as Chrome's HTTPS-Upgrades does. Measured on
/// a site whose port 80 never answers (2026-10-01): its http link hung until the
/// connection timed out, while its https answered in 1.2 s. Split from
/// `ContentBlocker.swift` only to keep both files under the linter's length
/// limit; it is the same object.
extension ContentBlocker {

    public enum HTTPSDecision: Sendable, Equatable {
        case proceed
        /// Cancel the navigation and load this instead.
        case upgrade(URL)
    }

    public var isHTTPSOnlyEnabled: Bool {
        get { defaults.bool(forKey: Key.httpsOnly) }
        set { defaults.set(newValue, forKey: Key.httpsOnly) }
    }

    /// The policy decision for one navigation. The interstitial itself is agent C's
    /// `luna://` page — when the upgraded load fails, the caller shows
    /// `showErrorPage(.httpsDowngrade, for:)` and its "Continue Anyway" lands in
    /// ``allowInsecure(host:)``.
    ///
    /// `WKWebpagePreferences.preferredHTTPSNavigationPolicy` is deliberately not used
    /// for this. Measured against an http-only origin: both `.errorOnFailure` and
    /// `.userMediatedFallbackToHTTP` end the navigation at `about:blank` with `didFinish`
    /// and no delegate error at all — a blank tab, no hook, nothing to explain it with.
    public func httpsDecision(
        for url: URL, in scope: SitePermissions = .shared, at now: Date = Date()
    ) -> HTTPSDecision {
        guard url.scheme?.lowercased() == "http" else { return .proceed }
        guard let host = Self.normalise(url.host()) else { return .proceed }
        // A private address has no path to a certificate, so upgrading it only breaks it.
        guard !insecureHosts.contains(host), !scope.insecureAllowed.contains(host), !Self.isPrivateHost(host)
        else { return .proceed }
        if !isHTTPSOnlyEnabled, httpOnlyHosts.contains(host) { return .proceed }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let upgraded = components?.url else { return .proceed }
        // The https address sent this one straight back: the site redirects
        // its https to http, and upgrading again would go round for ever.
        if !isHTTPSOnlyEnabled, let then = upgradedAt[upgraded.absoluteString],
           now.timeIntervalSince(then) < Self.httpsFirstPatience {
            httpOnlyHosts.insert(host)
            return .proceed
        }
        if upgrades.count > 32 { upgrades.removeAll(); upgradedAt.removeAll() }
        upgrades[upgraded.absoluteString] = url
        upgradedAt[upgraded.absoluteString] = now
        return .upgrade(upgraded)
    }

    /// How long an upgraded load may go without an answer before HTTPS-first
    /// gives up on it and loads the http address: Chrome's HTTPS-Upgrades
    /// figure. A site that drops port 443 would otherwise hold the tab until
    /// the connection timed out, the very wait the upgrade is there to spare.
    public static let httpsFirstPatience: TimeInterval = 3

    /// The http address to load instead of an upgraded one that failed, under
    /// HTTPS-first. Nil under HTTPS-only, which shows the downgrade page, and
    /// for a failure Luna's upgrade had nothing to do with. The host is
    /// remembered, so the rest of the session does not try its https again.
    public func httpsFirstFallback(for url: URL) -> URL? {
        guard !isHTTPSOnlyEnabled, let origin = upgrades[url.absoluteString],
              let host = Self.normalise(origin.host()) else { return nil }
        httpOnlyHosts.insert(host)
        return origin
    }

    /// The http URL an https failure came from, if we are the reason it was https.
    /// Non-nil means "show the downgrade interstitial", nil means an ordinary failure.
    public func downgradeOrigin(for url: URL) -> URL? { upgrades[url.absoluteString] }

    /// "Continue to the insecure site" — persisted in `siteSettings` beside the blocking
    /// exemption, because a user who said it once should not be asked on every link.
    /// A private window's answer stays in its own scope (§5.6).
    public func allowInsecure(host: String, in scope: SitePermissions = .shared) {
        guard let host = Self.normalise(host) else { return }
        guard !scope.isPrivate else {
            scope.insecureAllowed.insert(host)
            return
        }
        insecureHosts.insert(host)
        let store = browserStore
        Task { try? await store?.setInsecureAllowed(true, host: host) }
    }

    static func isPrivateHost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".onion") || host.hasSuffix(".test")
            || URL(string: "https://\(host)")?.host()?.allSatisfy { $0.isNumber || $0 == "." } == true
            || host.contains(":")
    }

}
