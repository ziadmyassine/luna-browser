import Foundation
import WebKit

/// How far down the page is, and what colour it is up at the top of it, for the
/// one piece of chrome that needs to know: §3.2b's page bar, which collapses as
/// the page moves away from its top and is painted in the page's own colour.
///
/// WebKit publishes no scroll position on macOS. `WKWebView` has no
/// `scrollView` outside UIKit and no KVO-able offset, so the only supported way
/// to ask is to have the page tell us — the same shape `mediaScript` and
/// `ContentBlocker.blockedCountScript` already use, and for the same reason.
///
/// And it publishes no colour but the document's. `underPageBackgroundColor`
/// is one answer for the whole page, so a bar taking it stayed white all the way
/// down a site whose next section is black. What is actually under the bar's
/// bottom edge is a question only the page can answer, so it is asked in the
/// same script, on the same frame boundary, and travels with the offset.
///
/// Both are delivered through closures rather than `TabState`: a `TabState`
/// change re-renders a sidebar row, and a scroll is not news to one. This fires
/// on a frame boundary for as long as a drag lasts, so nothing that reads tab
/// state may be woken by it.
extension TabController {

    static let scrollMessageName = "lunaScroll"

    func handleScrollMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let offset = body["y"] as? Double
        else { return }
        onScroll?(offset)
        setTopColour(Self.sampledColour(from: body["top"]))
    }

    /// The colour the page reported for the strip under the bar, or nil for "no
    /// single colour" — which is what the script says when its sample points
    /// disagree, and is a different answer from black.
    ///
    /// Held as well as published, because it is the tab's and not the bar's: a
    /// tab that comes back into view is already scrolled, and its chrome should
    /// not have to wait for the next drag to find that out.
    func setTopColour(_ colour: RGBA?) {
        guard colour != topColour else { return }
        topColour = colour
        onTopColour?(colour)
    }

    /// The sample as posted: three sRGB components in 0...1, or nothing. Kept
    /// pure and separate from the message so the shape the script promises can
    /// be asserted without a web view to post it.
    static func sampledColour(from sample: Any?) -> RGBA? {
        guard let parts = sample as? [NSNumber], parts.count == 3 else { return nil }
        let values = parts.map(\.doubleValue)
        guard values.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
        return RGBA(r: values[0], g: values[1], b: values[2], a: 1)
    }

    /// Posts `window.scrollY` and the colour under the top of the viewport on a
    /// frame boundary, once at document end and again on `pageshow`, so a bar
    /// that is already showing learns where a restored page resumed and what it
    /// resumed on.
    ///
    /// `passive`, so the listener can never delay a scroll, and `capture`, so it
    /// also sees the app-shell sites that scroll an inner element rather than
    /// the document — `scroll` does not bubble, but it does capture.
    ///
    /// Three points, and they have to agree. The bar is one colour across the
    /// pane, so a top edge that is two colours has no right answer and the
    /// sample says so; the bar then falls back to the document's own
    /// background. Each point goes down the z-order rather than up the DOM:
    /// `elementsFromPoint` gives everything painted at that pixel front to
    /// back, and the walk stops at the first opaque background, because the
    /// element on top is very often a transparent `<div>`.
    ///
    /// It was an ancestor walk first, which is wrong in the ordinary case: a
    /// site with a sticky transparent header over a dark section answered
    /// white. The header is what is under the point, its ancestors are the
    /// body, and the dark section is a sibling painted behind it, which no walk
    /// up the tree can reach. Measured on `getroosta.app`: the ancestor walk
    /// said `255,255,255`, the stack says `12,12,13`.
    ///
    /// A background image means that element cannot answer, so it is skipped
    /// and the walk goes on behind it. Ending the sample there is the bug
    /// reported as "the bar goes white over a black page": `getroosta.app` lays
    /// a two-stop `linear-gradient` (`div.horizon`) over `footer.night`, so
    /// from roughly 6500 pt down every sample came back empty and the bar fell
    /// to the document's background — white, over a footer measured at
    /// `12,12,13`.
    ///
    /// Giving up there never bought anything: "no answer" falls back to the
    /// document's background, which is what the last entries of any stack are,
    /// so stopping at the image only throws away the opaque surfaces painted
    /// between it and the document.
    ///
    /// And a restored page says so itself. Back and forward are served from
    /// WebKit's page cache, which restores the document without re-running user
    /// scripts — so nothing posted, `resetPerDocumentState` had already cleared
    /// the colour, and the bar wore the page it had just left until the next
    /// scroll. The listeners are still live in a restored document, so
    /// `pageshow` is the one event that covers both: it fires on every load
    /// after this script is injected, and on every restore out of the cache.
    ///
    /// Sampled at most every 4 pt of travel. `elementFromPoint` is a hit test,
    /// and three of them per frame of every drag for a colour that cannot have
    /// changed in four points is work the page pays for. A resize clears the
    /// cache and asks again — the viewport's top edge moves without a scroll
    /// when the bar changes height, and a responsive layout can put something
    /// else under it. `pageshow` clears it for the same reason.
    static let scrollScript = """
    (function () {
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaScroll;
      if (!h) { return; }
      var painted = function (x, y) {
        if (!document.elementsFromPoint) { return null; }
        var stack = document.elementsFromPoint(x, y);
        for (var i = 0; i < stack.length; i++) {
          var style = window.getComputedStyle(stack[i]);
          if (style.backgroundImage && style.backgroundImage !== 'none') { continue; }
          var text = style.backgroundColor || '';
          var open = text.indexOf('(');
          if (open < 0) { continue; }
          var parts = text.slice(open + 1, text.lastIndexOf(')')).split(',');
          if (parts.length < 3) { continue; }
          if (parts.length > 3 && parseFloat(parts[3]) < 0.99) { continue; }
          return [parseFloat(parts[0]) / 255, parseFloat(parts[1]) / 255, parseFloat(parts[2]) / 255];
        }
        return null;
      };
      var sample = function () {
        var width = window.innerWidth || 0;
        var y = Math.min(6, Math.max((window.innerHeight || 0) - 1, 0));
        var found = null;
        for (var i = 1; i <= 3; i++) {
          var colour = painted(width * i / 4, y);
          if (!colour) { return null; }
          if (found && (found[0] !== colour[0] || found[1] !== colour[1] || found[2] !== colour[2])) {
            return null;
          }
          found = colour;
        }
        return found;
      };
      var lastY = null;
      var lastTop = null;
      var top = function (y) {
        if (lastY !== null && Math.abs(y - lastY) < 4) { return lastTop; }
        lastY = y;
        lastTop = sample();
        return lastTop;
      };
      var pending = false;
      var post = function () {
        pending = false;
        var target = document.scrollingElement;
        var y = window.scrollY || (target ? target.scrollTop : 0) || 0;
        h.postMessage({ y: y, top: top(y) });
      };
      var schedule = function () {
        if (pending) { return; }
        pending = true;
        window.requestAnimationFrame(post);
      };
      window.addEventListener('scroll', schedule, { passive: true, capture: true });
      window.addEventListener('resize', function () {
        lastY = null;
        schedule();
      }, { passive: true });
      window.addEventListener('pageshow', function () {
        lastY = null;
        schedule();
      }, { passive: true });
      post();
    })();
    """
}
