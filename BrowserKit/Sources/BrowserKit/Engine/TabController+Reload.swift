import Foundation
import WebKit

/// Reload, where it differs from WebKit's own: a page served from this Mac, a
/// local text file, and a Markdown document all have to be re-read rather than
/// re-rendered from the copy already in hand.
extension TabController {

    /// Past the cache for a page on this Mac (`NavigationPolicy.isLocalDevelopment`).
    /// A text file shown by `localText` is loaded again instead: its page is
    /// the text as it was read, and reloading that shows the same copy.
    /// A Markdown document from the web is fetched again: WebKit's reload
    /// would show the page Luna rendered from the first copy.
    public func reload() {
        guard let url = webView?.url, NavigationPolicy.isLocalDevelopment(url) || markdownDocument != nil
        else { webView?.reload(); return }
        reloadFromOrigin()
    }

    public func reloadFromOrigin() {
        guard let webView else { return }
        if let document = markdownDocument, !document.url.isFileURL {
            fetchMarkdown(at: document.url, into: webView)
        } else if let url = webView.url, Self.isLocalText(url) {
            Self.load(url, into: webView)
        } else {
            webView.reloadFromOrigin()
        }
    }
}
