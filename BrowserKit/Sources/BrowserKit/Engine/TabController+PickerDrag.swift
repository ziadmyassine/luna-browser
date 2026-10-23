import Foundation

/// Comment mode's drag, as part of `pickerScript`: what a rectangle covers,
/// what holds it, and the rectangle as it follows the pointer. Its functions
/// are spliced into the picker's closure and share its state; a file of its
/// own only for SwiftLint's length limits.

extension TabController {

    static let pickerDragScript = """
        function within(b, r) {
          return b.left >= r.x && b.top >= r.y && b.right <= r.x + r.width && b.bottom <= r.y + r.height;
        }

        // The outermost drawn elements wholly inside `r`, in one pass in document
        // order: an element's descendants follow it, so one inside the last found
        // is skipped. No client rects measures as zero width.
        function inside(r) {
          var all = document.body ? document.body.getElementsByTagName('*') : [], found = [], last = null;
          for (var i = 0; i < all.length; i++) {
            var el = all[i];
            if (last && last.contains(el)) { continue; }
            var b = el.getBoundingClientRect();
            if (!b.width || !b.height || !within(b, r) || getComputedStyle(el).visibility !== 'visible') { continue; }
            last = el;
            found.push({ el: el, box: { x: b.x, y: b.y, width: b.width, height: b.height } });
          }
          return found;
        }

        // What holds the whole area: what the elements inside share, walked up
        // until it covers the rectangle, and never past the body.
        function holder(found, r) {
          var el = found.length ? found[0].el : document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
          for (var i = 1; el && i < found.length; i++) {
            while (el && !el.contains(found[i].el)) { el = el.parentElement; }
          }
          while (el && el !== document.body) {
            var b = el.getBoundingClientRect();
            if (b.left <= r.x && b.top <= r.y && b.right >= r.x + r.width && b.bottom >= r.y + r.height) { break; }
            el = el.parentElement;
          }
          return el && document.body.contains(el) ? el : document.body;
        }

        // The first 20 are listed and the rest only counted, so a drag over a
        // whole page still posts a few kilobytes.
        function area(r) {
          var found = inside(r), container = holder(found, r), selector = selectorFor(container);
          var contents = found.slice(0, 20).map(function (f) {
            var words = part(f.el);
            return { tag: f.el.tagName.toLowerCase(), text: words.text, html: words.html,
                     selector: selectorFor(f.el), box: f.box };
          });
          unmark();
          post({ region: { box: r, contents: contents, more: Math.max(0, found.length - 20) },
                 element: describe(container, selector, count(selector)) });
        }

        // 6 CSS px on either axis, twice WebKit's drag hysteresis: a jittery press stays a click.
        function dragged(event) {
          return Math.abs(event.clientX - press.x) >= 6 || Math.abs(event.clientY - press.y) >= 6;
        }

        // From the press to the pointer, cut to the viewport as the crop is.
        function spanned(event) {
          var left = Math.max(0, Math.min(press.x, event.clientX)), top = Math.max(0, Math.min(press.y, event.clientY));
          var right = Math.min(innerWidth, Math.max(press.x, event.clientX));
          var bottom = Math.min(innerHeight, Math.max(press.y, event.clientY));
          return { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
        }

        // `pointermove`, not `mousemove`: a cancelled `pointerdown` stops the
        // mouse events while the button is held (Pointer Events, "compatibility
        // mouse events").
        function onDrag(event) {
          if (!press || !(press.drawn || dragged(event))) { return; }
          press.drawn = true;
          box.classList.add('drag');
          place(spanned(event));
        }
    """
}
