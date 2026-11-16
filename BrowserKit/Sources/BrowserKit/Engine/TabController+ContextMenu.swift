import Foundation
import WebKit

/// What the page's right-click menu was opened on: the image, the link and the
/// video or audio under the pointer, any of them nil.
public struct ContextMenuHit: Equatable, Sendable {
    public var image: URL?
    public var link: URL?
    public var media: URL?

    public func url(for kind: ContextMenuDownload) -> URL? {
        switch kind {
        case .image: image
        case .link: link
        case .media: media
        }
    }
}

/// The three downloads WebKit's right-click menu offers.
public enum ContextMenuDownload: Sendable {
    case image, link, media
}

/// WebKit's own Download Image, Download Linked File and Download Video start
/// their download through a navigation-delegate method that is not public
/// (`docs/DECISIONS.md` D10), and with nobody taking it the download ended
/// before it began: no file, no prompt, nothing in Downloads. WebKit gives no
/// public way to learn what was right-clicked, so every frame says so itself
/// as the menu opens, and the app's own items download that through
/// `startDownload`, Luna's ordinary path. In `.defaultClient`, the world the
/// page cannot see, so a page cannot post what the menu will download.
extension TabController {

    static let contextMenuMessageName = "lunaContextMenu"

    /// Downloads what the last right-click was on. False when the page never
    /// said, and nothing was started.
    @discardableResult
    public func downloadFromContextMenu(_ kind: ContextMenuDownload) -> Bool {
        guard let webView, let url = contextMenuHit?.url(for: kind) else { return false }
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            guard let self, let delegate else { return download.cancel() }
            delegate.tabController(self, didStartDownload: download)
        }
        return true
    }

    func attachContextMenu(to controller: WKUserContentController, relay: WKScriptMessageHandler) {
        controller.removeScriptMessageHandler(forName: Self.contextMenuMessageName, contentWorld: .defaultClient)
        controller.add(relay, contentWorld: .defaultClient, name: Self.contextMenuMessageName)
    }

    func handleContextMenuMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        func url(_ key: String) -> URL? {
            guard let text = body[key] as? String, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), Self.downloadableSchemes.contains(scheme) else { return nil }
            return url
        }
        contextMenuHit = ContextMenuHit(image: url("image"), link: url("link"), media: url("media"))
    }

    /// `javascript:` and the like are not something to download.
    private static let downloadableSchemes: Set<String> = ["http", "https", "data", "blob", "file"]

    /// At document start, so the listener on `window` is the first, ahead of
    /// any the page adds. Every frame, because an image in an iframe opens the
    /// same menu; the event does not leave its frame, so only that one reports.
    static let contextMenuUserScript = WKUserScript(
        source: contextMenuScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient
    )

    /// Every right-click reports, an empty one included, so a menu opened on
    /// text never downloads the image right-clicked before it. The path rather
    /// than the target, which a shadow root retargets to its host. Only the
    /// browser's own events count. `__lunaContextMenuNote` is reachable from
    /// this world alone, for the tests.
    static let contextMenuScript = """
    (function () {
      var handlers = window.webkit && window.webkit.messageHandlers;
      var handler = handlers && handlers.lunaContextMenu;
      if (!handler) { return; }
      function resolve(href) { return href ? new URL(href, document.baseURI).href : null; }
      function note(path) {
        var hit = { image: null, link: null, media: null };
        for (var i = 0; i < path.length; i++) {
          var e = path[i];
          if (!hit.image) {
            if (e instanceof HTMLImageElement) { hit.image = e.currentSrc || e.src || null; }
            else if (e instanceof HTMLInputElement && e.type === 'image') { hit.image = e.src || null; }
            else if (e instanceof SVGImageElement) { hit.image = resolve(e.href.baseVal); }
          }
          if (!hit.media && e instanceof HTMLMediaElement) { hit.media = e.currentSrc || e.src || null; }
          if (!hit.link) {
            if ((e instanceof HTMLAnchorElement || e instanceof HTMLAreaElement) && e.href) { hit.link = e.href; }
            else if (e instanceof SVGAElement) { hit.link = resolve(e.href.baseVal); }
          }
        }
        handler.postMessage(hit);
      }
      window.__lunaContextMenuNote = note;
      window.addEventListener('contextmenu', function (event) {
        if (event.isTrusted) { note(event.composedPath()); }
      }, true);
    })();
    """
}
