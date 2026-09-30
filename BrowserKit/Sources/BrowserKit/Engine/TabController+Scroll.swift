import Foundation
import WebKit

/// What colour the page is up at the top of it, for §3.2b's page bar, which is
/// painted in the page's own colour. And how far through the page the reader
/// is, for the sidebar's selected row, which fills from its leading edge.
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
/// same script, on the same frame boundary.
///
/// Both are delivered through closures rather than `TabState`: a
/// `TabState` change re-renders a sidebar row, and a scroll is not news to
/// one. This fires on a frame boundary for as long as a drag lasts, so nothing
/// that reads tab state may be woken by it.
extension TabController {

    static let scrollMessageName = "lunaScroll"

    func handleScrollMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        setTopColour(Self.sampledColour(from: body["top"]))
        setScrollProgress(Self.progress(from: body["p"]))
    }

    /// How far through the page the reader is, or nil for a page that does not
    /// scroll. Held for `topColour`'s reason: a tab selected again should show
    /// where it was left without waiting for a scroll.
    func setScrollProgress(_ progress: Double?) {
        guard progress != scrollProgress else { return }
        scrollProgress = progress
        onScrollProgress?(progress)
    }

    /// The fraction as posted, clamped. Anything but a finite number is the
    /// script's null — a page with nothing below the fold — and is not zero:
    /// zero is a page that can scroll and has not.
    static func progress(from value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let fraction = number.doubleValue
        guard fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
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
    /// Layers that are not opaque are mixed over the first opaque one behind
    /// them, as the screen mixes them: a translucent colour, and a gradient
    /// running straight down or up, read where the sample line crosses its box.
    /// Netflix is why: its header is a black shadow fading down over a body at
    /// `20,20,20`, and stepping over the shadow answered the body's grey under
    /// a header the screen shows near black. An element's own `opacity` scales
    /// its layers the same way.
    ///
    /// Any other background image — a photo, a gradient at an angle, a radial
    /// one — cannot be read off one line, so it is stepped over and the walk
    /// goes on behind it. It used to end the sample there, which is "the bar
    /// goes white over a black page": `getroosta.app` lays a hard-edged
    /// `linear-gradient` (`div.horizon`) over `footer.night`, every sample came
    /// back empty and the bar fell to the document's white. That gradient is
    /// now read as well, so the bar is white over its white part and dark below
    /// the edge.
    ///
    /// Behind a JPEG or a video nothing is on screen, since neither can be
    /// see-through, so mixing stops there and only an opaque colour behind can
    /// still answer. Netflix's signed-out page lays a red glow behind its hero
    /// photo. Other pictures may be see-through — `getroosta.app`'s footer is a
    /// full-width `.webp` over the horizon — so they hide nothing.
    ///
    /// A page can switch hit testing off. Netflix does while it scrolls and for
    /// a moment after, and `elementsFromPoint` then finds nothing but `<html>`:
    /// measured, 1331 of 1496 samples in one scroll answered the document's
    /// grey under a black header. A body that covers the point but is not in
    /// the stack is that state, so the sample keeps the last colour it saw and
    /// asks again every 250 ms, up to 5 s, until the page can be hit.
    ///
    /// And a restored page says so itself. Back and forward are served from
    /// WebKit's page cache, which restores the document without re-running user
    /// scripts — so nothing posted, `resetPerDocumentState` had already cleared
    /// the colour, and the bar wore the page it had just left until the next
    /// scroll. The listeners are still live in a restored document, so
    /// `pageshow` is the one event that covers both: it fires on every load
    /// after this script is injected, and on every restore out of the cache.
    ///
    /// And how far through the page the reader is, for the sidebar's selected
    /// row. The document's own scroll when it has one; otherwise the last
    /// element that scrolled, as long as it is at least half the viewport tall —
    /// an app-shell site's content pane, not a dropdown's list.
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
      var split = function (text) {
        var parts = [];
        var depth = 0;
        var from = 0;
        for (var i = 0; i < text.length; i++) {
          var c = text.charAt(i);
          if (c === '(') { depth++; } else if (c === ')') { depth--; } else if (c === ',' && depth === 0) {
            parts.push(text.slice(from, i).trim());
            from = i + 1;
          }
        }
        parts.push(text.slice(from).trim());
        return parts;
      };
      var rgba = function (text) {
        if (text === 'transparent') { return [0, 0, 0, 0]; }
        if (text.indexOf('rgb') !== 0) { return null; }
        var parts = text.slice(text.indexOf('(') + 1, text.lastIndexOf(')')).split(',');
        if (parts.length < 3) { return null; }
        var alpha = parts.length > 3 ? parseFloat(parts[3]) : 1;
        return [parseFloat(parts[0]), parseFloat(parts[1]), parseFloat(parts[2]), alpha];
      };
      var over = function (top, under) {
        var alpha = top[3] + under[3] * (1 - top[3]);
        if (alpha <= 0) { return [0, 0, 0, 0]; }
        var mixed = [0, 1, 2].map(function (i) {
          return (top[i] * top[3] + under[i] * under[3] * (1 - top[3])) / alpha;
        });
        mixed.push(alpha);
        return mixed;
      };
      var between = function (a, b, f) {
        var alpha = a[3] + (b[3] - a[3]) * f;
        var mixed = [0, 1, 2].map(function (i) {
          return alpha > 0 ? (a[i] * a[3] + (b[i] * b[3] - a[i] * a[3]) * f) / alpha : 0;
        });
        mixed.push(alpha);
        return mixed;
      };
      var gradientAt = function (image, t, height) {
        var match = /^linear-gradient\\((.*)\\)$/.exec(image);
        if (!match) { return null; }
        var args = split(match[1]);
        if (/^to |deg$|turn$|rad$/.test(args[0])) {
          var way = args.shift();
          if (way === 'to top' || way === '0deg') {
            t = 1 - t;
          } else if (way !== 'to bottom' && way !== '180deg' && way !== '0.5turn') {
            return null;
          }
        }
        var stops = [];
        for (var i = 0; i < args.length; i++) {
          var close = args[i].lastIndexOf(')');
          var colour = rgba(close < 0 ? args[i].split(' ')[0] : args[i].slice(0, close + 1));
          var at = (close < 0 ? args[i].split(' ').slice(1).join(' ') : args[i].slice(close + 1)).trim();
          if (!colour) { return null; }
          var position = null;
          if (/^-?[0-9.]+%$/.test(at)) {
            position = parseFloat(at) / 100;
          } else if (/^-?[0-9.]+px$/.test(at)) {
            position = parseFloat(at) / height;
          } else if (at !== '') {
            return null;
          }
          stops.push({ colour: colour, at: position });
        }
        if (stops.length < 2) { return null; }
        if (stops[0].at === null) { stops[0].at = 0; }
        if (stops[stops.length - 1].at === null) { stops[stops.length - 1].at = 1; }
        for (var j = 1; j < stops.length; j++) {
          if (stops[j].at === null) {
            var next = j;
            while (stops[next].at === null) { next++; }
            stops[j].at = stops[j - 1].at + (stops[next].at - stops[j - 1].at) / (next - j + 1);
          }
          stops[j].at = Math.max(stops[j].at, stops[j - 1].at);
        }
        if (t <= stops[0].at) { return stops[0].colour; }
        for (var k = 0; k < stops.length - 1; k++) {
          if (t < stops[k + 1].at) {
            return between(stops[k].colour, stops[k + 1].colour, (t - stops[k].at) / (stops[k + 1].at - stops[k].at));
          }
        }
        return stops[stops.length - 1].colour;
      };
      var imageAt = function (element, style, y) {
        var size = style.backgroundSize || 'auto';
        if (!/^(auto|auto auto|cover|contain|100%|100% 100%|100% auto|auto 100%)$/.test(size)) { return null; }
        if (!element.getBoundingClientRect) { return null; }
        var box = element.getBoundingClientRect();
        if (!(box.height > 0)) { return null; }
        var t = Math.min(Math.max((y - box.top) / box.height, 0), 1);
        var layers = split(style.backgroundImage);
        var result = [0, 0, 0, 0];
        for (var i = layers.length - 1; i >= 0; i--) {
          var layer = gradientAt(layers[i], t, box.height);
          if (!layer) { return null; }
          result = over(layer, result);
        }
        return result;
      };
      var painted = function (x, y) {
        if (!document.elementsFromPoint) { return null; }
        var stack = document.elementsFromPoint(x, y);
        var body = document.body;
        if (body && body.getBoundingClientRect && stack.indexOf(body) < 0) {
          var page = body.getBoundingClientRect();
          if (x >= page.left && x < page.right && y >= page.top && y < page.bottom) { return undefined; }
        }
        var above = [];
        var hidden = false;
        for (var i = 0; i < stack.length; i++) {
          var tag = stack[i].tagName || '';
          if (tag === 'VIDEO' || (tag === 'IMG' && /\\.jpe?g([?#]|$)/i.test(stack[i].currentSrc || ''))) {
            hidden = true;
            above = [];
          }
          var style = window.getComputedStyle(stack[i]);
          var layers = [];
          if (!hidden && style.backgroundImage && style.backgroundImage !== 'none') {
            var image = imageAt(stack[i], style, y);
            if (image) { layers.push(image); }
          }
          var colour = rgba(style.backgroundColor || '');
          if (colour) { layers.push(colour); }
          var fade = parseFloat(style.opacity);
          for (var j = 0; j < layers.length; j++) {
            if (fade >= 0 && fade < 1) { layers[j] = layers[j].slice(0, 3).concat([layers[j][3] * fade]); }
            if (layers[j][3] < 0.99) {
              if (layers[j][3] > 0 && !hidden) { above.push(layers[j]); }
              continue;
            }
            var result = layers[j];
            for (var k = above.length - 1; k >= 0; k--) { result = over(above[k], result); }
            return [0, 1, 2].map(function (c) { return Math.round(result[c]) / 255; });
          }
        }
        return null;
      };
      var sample = function () {
        var width = window.innerWidth || 0;
        var y = Math.min(6, Math.max((window.innerHeight || 0) - 1, 0));
        var found = null;
        for (var i = 1; i <= 3; i++) {
          var colour = painted(width * i / 4, y);
          if (colour === undefined) { return undefined; }
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
      var retry = null;
      var retries = 0;
      var top = function (y) {
        if (lastY !== null && Math.abs(y - lastY) < 4) { return lastTop; }
        var seen = sample();
        if (seen === undefined) {
          window.clearTimeout(retry);
          if (retries < 20) {
            retry = window.setTimeout(function () {
              retries++;
              lastY = null;
              schedule();
            }, 250);
          }
          return lastTop;
        }
        retries = 0;
        lastY = y;
        lastTop = seen;
        return lastTop;
      };
      var inner = null;
      var through = function (y) {
        var target = document.scrollingElement;
        var room = (target ? target.scrollHeight : 0) - (window.innerHeight || 0);
        if (room > 1) { return y / room; }
        if (!inner || !inner.isConnected || inner.clientHeight < (window.innerHeight || 0) / 2) { return null; }
        room = inner.scrollHeight - inner.clientHeight;
        return room > 1 ? inner.scrollTop / room : null;
      };
      var pending = false;
      var post = function () {
        pending = false;
        var target = document.scrollingElement;
        var y = window.scrollY || (target ? target.scrollTop : 0) || 0;
        h.postMessage({ y: y, top: top(y), p: through(y) });
      };
      var schedule = function () {
        if (pending) { return; }
        pending = true;
        window.requestAnimationFrame(post);
      };
      window.addEventListener('scroll', function (event) {
        if (event.target && event.target.nodeType === 1) { inner = event.target; }
        retries = 0;
        schedule();
      }, { passive: true, capture: true });
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
