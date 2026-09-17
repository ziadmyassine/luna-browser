import Foundation
import WebKit

/// The single place in Luna where a `WKWebView` is constructed (§4.1).
///
/// Nothing here may import AppKit: `BrowserKit` stays UIKit-portable so an iOS
/// companion remains possible (§25.5, §32). `Tools/check-no-appkit.sh` enforces it.
public enum WebViewFactory {

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
    private static var applicationNameForUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version/26.0 Safari/605.1.15 Luna/\(version)"
    }

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
        // Required (macOS 13.3+): without it the Web Inspector silently does nothing (§4.1).
        webView.isInspectable = true
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
