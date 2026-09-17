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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = applicationNameForUserAgent
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        // One controller per web view: script message handler names are registered on
        // the controller, so a shared one makes handlers collide across tabs.
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Required (macOS 13.3+): without it the Web Inspector silently does nothing (§4.1).
        webView.isInspectable = true
        return webView
    }
}
