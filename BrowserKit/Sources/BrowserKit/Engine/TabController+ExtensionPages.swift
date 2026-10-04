import Foundation
import WebKit

/// A tab crossing between an extension's own pages and the web.
///
/// An extension's pages need a web view built from that extension's
/// `webViewConfiguration`, and WebKit lets such a view load nothing but the
/// extension's own URLs: a page in it that sends itself to the web is
/// dropped without a word, and so is a web page sending itself to an
/// extension URL (`WKWebExtensionContext.webViewConfiguration`, whose header
/// says the app must swap the tab's web view). 1Password's welcome page did
/// the first — its Sign in button sets `location.href` to its website — and
/// the button did nothing.
extension TabController {

    nonisolated static let extensionScheme = "webkit-extension"

    /// Whether a main-frame navigation to `url` crosses the boundary, and so
    /// needs another web view rather than this one.
    func crossesExtensionBoundary(to url: URL, in webView: WKWebView) -> Bool {
        Self.crossesExtensionBoundary(from: webView.url, to: url)
    }

    /// `here` is the page the view is showing, nil before its first load.
    nonisolated static func crossesExtensionBoundary(from here: URL?, to url: URL) -> Bool {
        let fromExtension = here?.scheme?.lowercased() == Self.extensionScheme
        let toExtension = url.scheme?.lowercased() == Self.extensionScheme
        if fromExtension { return !toExtension || url.host() != here?.host() }
        // Only once a web page is showing: an extension tab's first load
        // arrives before the view has a URL, in a view already built for it.
        return toExtension && here != nil
    }

    /// A main-frame navigation that crosses, sent to the view it needs. True
    /// when it was, so the navigation here is cancelled.
    func crossedExtensionBoundary(_ action: WKNavigationAction, to url: URL, in webView: WKWebView) -> Bool {
        guard action.targetFrame?.isMainFrame ?? false, crossesExtensionBoundary(to: url, in: webView) else { return false }
        crossExtensionBoundary(to: url)
        return true
    }

    /// Builds the web view `url` needs and loads it there. Run after the
    /// navigation has been cancelled, never inside the policy callback: the
    /// view being replaced is the one asking.
    func crossExtensionBoundary(to url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            hibernate()
            savedInteractionState = nil
            if url.scheme?.lowercased() == Self.extensionScheme,
               let configuration = webExtensionController?.extensionContext(for: url)?.webViewConfiguration {
                activate(with: configuration)
            }
            load(url)
            delegate?.tabControllerDidReplaceWebView(self)
        }
    }
}
