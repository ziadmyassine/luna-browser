import Foundation

/// §17.6's HTTPS-only mode. Split from `ContentBlocker.swift` only to keep both files
/// under the linter's length limit; it is the same object.
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
    public func httpsDecision(for url: URL) -> HTTPSDecision {
        guard isHTTPSOnlyEnabled, url.scheme?.lowercased() == "http" else { return .proceed }
        guard let host = Self.normalise(url.host()) else { return .proceed }
        // A private address has no path to a certificate, so upgrading it only breaks it.
        guard !insecureHosts.contains(host), !Self.isPrivateHost(host) else { return .proceed }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let upgraded = components?.url else { return .proceed }
        upgrades[upgraded.absoluteString] = url
        if upgrades.count > 32 { upgrades.removeAll() }
        return .upgrade(upgraded)
    }

    /// The http URL an https failure came from, if we are the reason it was https.
    /// Non-nil means "show the downgrade interstitial", nil means an ordinary failure.
    public func downgradeOrigin(for url: URL) -> URL? { upgrades[url.absoluteString] }

    /// "Continue to the insecure site" — persisted in `siteSettings` beside the blocking
    /// exemption, because a user who said it once should not be asked on every link.
    public func allowInsecure(host: String) {
        guard let host = Self.normalise(host) else { return }
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
