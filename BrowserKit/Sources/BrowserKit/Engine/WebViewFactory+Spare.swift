import Foundation
import WebKit

/// One web view built ahead of the next tab that asks for it, its WebContent
/// process already running.
///
/// Measured on the real web against a view built at the moment of the load:
/// the page commits 20 to 35 ms sooner and finishes 25 to 60 ms sooner
/// (Wikipedia, The Verge, BBC, Apple; 11 rounds each). A view that is only
/// built gains nothing, so the spare loads an empty document, which leaves
/// nothing in the back list. One spare, for the Space last used: a second
/// is another idle process for a tab that may never come.
extension WebViewFactory {

    private struct Spare {
        let webView: WKWebView
        let dataStore: ObjectIdentifier
        let extensions: ObjectIdentifier?
    }

    /// Off until the app turns it on, so a test or a tool that builds web
    /// views is not left with an extra one running behind it.
    @MainActor public static var keepsSpare = false

    @MainActor private static var spare: Spare?
    @MainActor static var spareWebView: WKWebView? { spare?.webView }
    @MainActor private static var refill: Task<Void, Never>?

    /// Long enough after a tab took the spare that building the next one does
    /// not compete with that tab's own load.
    static let refillDelay: Duration = .seconds(2)

    /// Builds the spare for this Space now, unless it is already there. For
    /// the moments a new tab is close: the command bar opening on `⌘T`.
    @MainActor
    public static func prepareSpare(dataStore: WKWebsiteDataStore, webExtensionController: WKWebExtensionController?) {
        refill?.cancel()
        refill = nil
        guard keepsSpare else { return }
        let key = (ObjectIdentifier(dataStore), webExtensionController.map(ObjectIdentifier.init))
        if let spare, spare.dataStore == key.0, spare.extensions == key.1 { return }
        let configuration = makeConfiguration(dataStore: dataStore)
        configuration.webExtensionController = webExtensionController
        let webView = makeWebView(configuration: configuration)
        webView.loadHTMLString("", baseURL: nil)
        spare = Spare(webView: webView, dataStore: key.0, extensions: key.1)
    }

    /// Lets the spare go: under memory pressure, an idle process is the first
    /// thing to give back.
    @MainActor
    public static func dropSpare() {
        refill?.cancel()
        refill = nil
        spare = nil
    }

    /// The spare, if it was built for this Space and its empty document has
    /// loaded, with what may have changed since it was built applied again.
    /// Either way another is built for the next tab.
    @MainActor
    static func takeSpare(dataStore: WKWebsiteDataStore, webExtensionController: WKWebExtensionController?) -> WKWebView? {
        defer { scheduleRefill(dataStore: dataStore, webExtensionController: webExtensionController) }
        guard let spare, spare.dataStore == ObjectIdentifier(dataStore),
              spare.extensions == webExtensionController.map(ObjectIdentifier.init),
              !spare.webView.isLoading
        else { return nil }
        self.spare = nil
        let webView = spare.webView
        ContentBlocker.shared.apply(to: webView.configuration.userContentController)
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = PopupPolicy.mode() == .off
        applyAdvancedSettings(to: webView)
        return webView
    }

    @MainActor
    private static func scheduleRefill(dataStore: WKWebsiteDataStore, webExtensionController: WKWebExtensionController?) {
        guard keepsSpare else { return }
        refill?.cancel()
        refill = Task { [weak dataStore, weak webExtensionController] in
            do { try await Task.sleep(for: refillDelay) } catch { return }
            guard let dataStore else { return }
            prepareSpare(dataStore: dataStore, webExtensionController: webExtensionController)
        }
    }
}
