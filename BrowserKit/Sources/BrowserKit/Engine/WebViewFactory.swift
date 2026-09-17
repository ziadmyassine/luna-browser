import Foundation
import WebKit

/// The single place in Luna where a `WKWebView` is constructed (§4.1).
///
/// Nothing here may import AppKit: `BrowserKit` stays UIKit-portable so an iOS
/// companion remains possible (§25.5, §32). `Tools/check-no-appkit.sh` enforces it.
public enum WebViewFactory {

    /// §3.9's user-agent popup. Stored in `advanced.userAgent` as its raw value.
    ///
    /// **Why only ``UserAgentMode/default`` uses `applicationNameForUserAgent`.**
    /// That property *appends* to WebKit's default UA; it cannot remove the
    /// `Luna/` token nor change `AppleWebKit/605.1.15`. So the three impersonating
    /// modes replace the whole string through `WKWebView.customUserAgent`, and the
    /// Default mode leaves `customUserAgent` nil so the appended form is untouched.
    public enum UserAgentMode: String, CaseIterable, Sendable {
        case `default`, safari, chrome, custom
    }

    /// Appended to WebKit's default user agent — it does **not** replace it (§4.6).
    ///
    /// The default UA is `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
    /// AppleWebKit/605.1.15 (KHTML, like Gecko)`, which carries no `Version/` and no
    /// `Safari/` token at all. Sites that sniff for Safari then serve a fallback page
    /// or refuse outright, so the Safari tokens come first and `Luna/` trails them the
    /// way `Edg/` and `CriOS/` do. Per-site overrides are §4.6's job, not M0's.
    ///
    /// `Version/` tracks the Safari whose web-compat profile we inherit (§26) — review
    /// it on each macOS release rather than letting it rot.
    public static var applicationNameForUserAgent: String {
        "\(safariTokens) Luna/\(shortVersion)"
    }

    /// The Safari compat tokens, without Luna's. `Version/` and `Safari/` move
    /// together; splitting them is what produces a UA no real browser sends.
    public static let safariTokens = "Version/26.0 Safari/605.1.15"

    /// WebKit's own default UA prefix, measured on macOS 26.5 by reading
    /// `navigator.userAgent` out of a web view built with no application name.
    /// `SectionsBTests.testWebKitBasePrefixIsStillWhatWeThinkItIs` re-measures it,
    /// so a WebKit update that moves it fails the test rather than silently
    /// shipping a UA that names the wrong engine.
    public static let webKitBase = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko)"

    /// Chrome's macOS UA. The major version is the one thing here that is not
    /// measured from this machine — nothing on it runs Chrome — so it is a
    /// constant to review beside `Version/` above, not a derived value.
    public static let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - §3.9's two Advanced settings

    public enum Key {
        public static let userAgent = "advanced.userAgent"
        public static let customUserAgent = "advanced.userAgentCustom"
        public static let webInspector = "advanced.webInspector"
    }

    public static var userAgentMode: UserAgentMode {
        get { UserDefaults.standard.string(forKey: Key.userAgent).flatMap(UserAgentMode.init(rawValue:)) ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.userAgent) }
    }

    /// The §3.9 text field's value. Empty means "behave as Default" — a mode the
    /// user has selected but not filled in must not send an empty UA.
    public static var customUserAgentString: String {
        get { UserDefaults.standard.string(forKey: Key.customUserAgent) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.customUserAgent) }
    }

    /// Required (macOS 13.3+): without it the Web Inspector silently does nothing (§4.1).
    /// Defaults to **on**, which is what every Luna web view did before it was a setting.
    public static var isWebInspectorEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.webInspector) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.webInspector) }
    }

    /// What `WKWebView.customUserAgent` should be for `mode`.
    ///
    /// - Returns: nil for Default — and for a Custom mode with nothing typed in —
    ///   which is what leaves ``applicationNameForUserAgent``'s appended string in place.
    public static func customUserAgent(for mode: UserAgentMode) -> String? {
        switch mode {
        case .default:
            nil
        case .safari:
            "\(webKitBase) \(safariTokens)"
        case .chrome:
            chromeUserAgent
        case .custom:
            customUserAgentString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : customUserAgentString
        }
    }

    /// Re-reads both Advanced settings onto a web view that already exists.
    ///
    /// `customUserAgent` takes effect on the **next** navigation, not on the page
    /// already loaded — WebKit sends the UA with the request. The Settings window
    /// says so rather than pretending the change is instant.
    @MainActor
    public static func applyAdvancedSettings(to webView: WKWebView) {
        webView.customUserAgent = customUserAgent(for: userAgentMode)
        webView.isInspectable = isWebInspectorEnabled
    }

    // MARK: - Construction

    /// Creates a configured web view. Every Luna web view comes from here.
    @MainActor
    public static func makeWebView(dataStore: WKWebsiteDataStore = .default()) -> WKWebView {
        makeWebView(configuration: makeConfiguration(dataStore: dataStore))
    }

    /// Builds a web view around a configuration WebKit handed us — the `WKUIDelegate`
    /// `createWebViewWith` path (§4.2). The popup **must** use that exact configuration
    /// or `window.opener` and `target="_blank"` break, so only the view-level properties
    /// are applied here.
    @MainActor
    public static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        // A popup's configuration arrives carrying the *opener's* user content
        // controller. Registering a handler name that is already on it raises
        // `NSInvalidArgumentException`, and tearing the popup down would unregister the
        // opener's handlers and scripts. A fresh controller per web view is the only
        // shape where per-tab handlers are safe; it keeps the process pool, data store
        // and preferences that carry the opener relationship.
        configuration.userContentController = WKUserContentController()
        // §17.1: the popup's fresh controller starts with no rule lists on it, so a
        // `target="_blank"` window would load unfiltered without this second call.
        ContentBlocker.shared.apply(to: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        applyAdvancedSettings(to: webView)
        return webView
    }

    @MainActor
    public static func makeConfiguration(dataStore: WKWebsiteDataStore = .default()) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        // §18.8: must stay empty to match Safari. `[.audio]` blocks the programmatic
        // `play()` an SPA navigation makes outside a user gesture, which breaks YouTube.
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        // One controller per web view: script message handler names are registered on
        // the controller, so a shared one makes handlers collide across tabs.
        configuration.userContentController = WKUserContentController()
        // §17.1's compiled `WKContentRuleList`s. Per-site exemptions re-apply on
        // navigation (`TabController.decidePolicyFor`); this is the resting set.
        ContentBlocker.shared.apply(to: configuration.userContentController)

        // §4.4. Registered here and nowhere else: `setURLSchemeHandler` raises
        // `NSInvalidArgumentException` for a scheme that already has one, and the
        // `createWebViewWith` path above deliberately does **not** re-register —
        // a popup arrives carrying the opener's configuration, which already has it.
        configuration.setURLSchemeHandler(InternalPageHandler.shared, forURLScheme: InternalPages.scheme)
        return configuration
    }
}
