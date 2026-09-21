import BrowserKit
import Testing
import WebKit

@Suite("WebViewFactory (§4.1)")
@MainActor
struct WebViewFactoryTests {

    /// Every property §4.1 names, on the configuration and on the web view itself.
    @Test func appliesSharedConfiguration() {
        // Non-persistent so the test never writes into the real profile's data store.
        let webView = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        let configuration = webView.configuration

        #expect(configuration.websiteDataStore.isPersistent == false, "the dataStore argument was ignored")
        #expect(configuration.preferences.isElementFullscreenEnabled)
        #expect(configuration.allowsAirPlayForMediaPlayback)
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript)

        // §4.6: applicationNameForUserAgent is appended to the system UA, so the
        // Safari compat tokens must be in it — a bare product token is a different UA.
        let applicationName = configuration.applicationNameForUserAgent ?? ""
        #expect(applicationName.hasPrefix("Version/"))
        #expect(applicationName.contains("Safari/"))
        #expect(applicationName.contains("Luna/"))

        #expect(webView.allowsBackForwardNavigationGestures)
        #expect(webView.allowsMagnification)
        // Drop this and the Web Inspector silently does nothing.
        #expect(webView.isInspectable)
    }

    /// A shared user content controller makes script message handler names collide
    /// across tabs, so each web view must get its own.
    @Test func doesNotShareUserContentControllers() {
        let store = WKWebsiteDataStore.nonPersistent()
        let first = WebViewFactory.makeWebView(dataStore: store)
        let second = WebViewFactory.makeWebView(dataStore: store)

        #expect(first.configuration.userContentController !== second.configuration.userContentController)
    }
}
