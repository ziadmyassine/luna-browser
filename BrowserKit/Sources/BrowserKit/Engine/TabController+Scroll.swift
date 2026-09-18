import Foundation
import WebKit

/// How far down the page is, for the one piece of chrome that needs to know:
/// §3.2b's page bar, which collapses as the page moves away from its top.
///
/// **WebKit publishes no scroll position on macOS.** `WKWebView` has no
/// `scrollView` outside UIKit and no KVO-able offset, so the only supported way
/// to ask is to have the page tell us — the same shape `mediaScript` and
/// `ContentBlocker.blockedCountScript` already use, and for the same reason.
///
/// The offset is delivered through a closure rather than through `TabState`: a
/// `TabState` change re-renders a sidebar row, and a scroll is not news to a
/// sidebar row. This fires on a frame boundary for as long as a drag lasts, so
/// nothing that reads tab state may be woken by it.
extension TabController {

    static let scrollMessageName = "lunaScroll"

    func handleScrollMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let offset = body["y"] as? Double
        else { return }
        onScroll?(offset)
    }

    /// Posts `window.scrollY` on a frame boundary, and once at document end so
    /// a bar that is already showing learns where a restored page resumed.
    ///
    /// `passive`, so the listener can never delay a scroll, and `capture`, so it
    /// also sees the app-shell sites that scroll an inner element rather than
    /// the document — `scroll` does not bubble, but it does capture.
    static let scrollScript = """
    (function () {
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaScroll;
      if (!h) { return; }
      var pending = false;
      var post = function () {
        pending = false;
        var target = document.scrollingElement;
        h.postMessage({ y: window.scrollY || (target ? target.scrollTop : 0) || 0 });
      };
      window.addEventListener('scroll', function () {
        if (pending) { return; }
        pending = true;
        window.requestAnimationFrame(post);
      }, { passive: true, capture: true });
      post();
    })();
    """
}
