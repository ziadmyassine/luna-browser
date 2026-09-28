import AppKit
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

    /// D10's second exception. Without it a page's video reports it cannot float
    /// at all, and both ⇧⌘P and the automatic path silently do nothing. Asked of a
    /// video with media loaded: an empty `<video>` answers no either way.
    @Test func videosCanFloat() async throws {
        let folder = try #require(Bundle.module.url(forResource: "Fixtures/PictureInPicture", withExtension: nil))
        let webView = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        // WebKit loads no media for a page that is in no window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        webView.frame = window.contentLayoutRect
        window.contentView?.addSubview(webView)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        webView.loadFileURL(folder.appending(path: "index.html"), allowingReadAccessTo: folder)
        var answer: String?
        for _ in 0..<50 {
            answer = try? await webView.evaluateJavaScript("""
            (function () {
              var v = document.querySelector('video');
              if (!v || v.readyState < 1) { return 'loading'; }
              return String(v.webkitSupportsPresentationMode('picture-in-picture'));
            })();
            """) as? String
            if let answer, answer != "loading" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(answer == "true", "the video answered \(answer ?? "nothing")")
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
