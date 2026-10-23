import Foundation

/// The element picker's page script, shared by Hide Something… and comment mode.
/// A separate file because it is most of the picker and none of its Swift.

extension TabController {

    /// The pointing mode. Its outline is drawn in a closed shadow root, so the
    /// page's own stylesheets cannot reach it and the internal pages' palette
    /// can, with `:root` read as the shadow host.
    ///
    /// The outline and its label are black inside a white halo, not palette
    /// ink: the palette follows Luna's appearance and the page does not, so
    /// in a dark Luna the ink was white on a white page (measured 1.0:1). One
    /// of black and white clears 4.58:1 against any opaque colour, so one of
    /// the two rings always reads.
    ///
    /// Every kind of press is swallowed, not only `click`: pages act on
    /// `pointerdown` and `mousedown` and are gone before a click completes.
    ///
    /// `on(palette, { detail: true })` is comment mode: a press posts a
    /// description of the element, and is kept when its selector is not unique.
    static let pickerScript = """
    if (!window.__lunaPicker) {
      window.__lunaPicker = (function () {
        var live = false, detail = false, host = null, box = null, tag = null, target = null, cursor = null;
        // Comment mode's walk: the element under the pointer, then each parent ↑ added.
        var trail = [];
        var presses = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click',
                       'dblclick', 'auxclick', 'contextmenu', 'touchstart'];
        var known = { nav: 'Navigation', header: 'Header', footer: 'Footer', aside: 'Sidebar',
                      form: 'Form', dialog: 'Dialog', video: 'Video', img: 'Image', picture: 'Image',
                      button: 'Button', iframe: 'Embed', figure: 'Figure', table: 'Table' };

        function post(body) {
          try { window.webkit.messageHandlers.lunaPick.postMessage(body); } catch (e) {}
        }

        function build(palette) {
          if (host && host.isConnected) { return; }
          host = document.createElement('luna-picker');
          host.style.cssText = 'all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647';
          var root = host.attachShadow({ mode: 'closed' });
          var style = document.createElement('style');
          style.textContent = palette.replace(/:root/g, ':host') +
            '.box{position:fixed;display:none;box-sizing:border-box;pointer-events:none;' +
            'border:2px solid #000;box-shadow:0 0 0 2px #fff;background:var(--luna-surface-selected);' +
            'border-radius:var(--luna-row-radius);transition-property:left,top,width,height;' +
            'transition-duration:var(--luna-motion-hover);transition-timing-function:ease-out}' +
            '.tag{position:absolute;left:-2px;max-width:320px;overflow:hidden;text-overflow:ellipsis;' +
            'white-space:nowrap;padding:0 8px;border-radius:var(--luna-row-radius);' +
            'font:500 var(--luna-size-label)/20px -apple-system,BlinkMacSystemFont,sans-serif;' +
            'color:#fff;background:#000;box-shadow:0 0 0 2px #fff}' +
            '@media (prefers-reduced-motion: reduce){.box{transition:none}}';
          box = document.createElement('div');
          box.className = 'box';
          tag = document.createElement('div');
          tag.className = 'tag';
          box.appendChild(tag);
          root.appendChild(style);
          root.appendChild(box);
          document.documentElement.appendChild(host);
        }

        function clip(text, n) { return text.length > n ? text.slice(0, n - 1) + '…' : text; }

        function said(el) {
          var label = el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('alt');
          return label && label.trim() ? clip(label.trim(), 40) : '';
        }

        // What a person would call it: its own label, then its kind, then its words.
        function name(el) {
          if (said(el)) { return said(el); }
          var kind = el.tagName.toLowerCase();
          if (known[kind]) { return known[kind]; }
          var role = el.getAttribute('role');
          if (role) { return role.charAt(0).toUpperCase() + role.slice(1); }
          var words = (el.innerText || '').trim().replace(/\\s+/g, ' ');
          return words ? clip(words, 40) : kind;
        }

        function count(selector) {
          try { return document.querySelectorAll(selector).length; } catch (e) { return 0; }
        }

        function unique(selector) { return count(selector) === 1; }

        function line(text) { return (text || '').replace(/\\s+/g, ' ').trim(); }

        // Read for an agent, so every string is the page's: one line, clipped,
        // and the value attribute cut so a form's contents never leave.
        function describe(el, selector, matches) {
          var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6'), heading = null;
          for (var i = 0; i < headings.length; i++) {
            if (!(headings[i].compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)) { break; }
            heading = headings[i];
          }
          var around = el.parentElement && el.parentElement.closest('header,nav,main,aside,footer,[role]');
          var landmark = !around ? null : /^(HEADER|NAV|MAIN|ASIDE|FOOTER)$/.test(around.tagName)
            ? around.tagName.toLowerCase() : around.getAttribute('role');
          // Only what is drawn: a script beside it has no name a person would use.
          // Words before kind, unlike `name`: three neighbours all called Button
          // say nothing about which ones to leave alone.
          var siblings = !el.parentElement ? [] : Array.prototype.filter.call(el.parentElement.children, function (c) {
            return c !== el && c !== host && c.getClientRects().length > 0;
          }).slice(0, 6).map(function (c) { return line(said(c) || clip(line(c.innerText), 40) || name(c)); });
          var r = el.getBoundingClientRect();
          return {
            selector: selector, matches: matches, tag: el.tagName.toLowerCase(),
            // WebKit has no `computedRole`; the tag stands for the implicit one.
            role: el.getAttribute('role') || null,
            text: clip(line(el.innerText), 120),
            html: clip(line(el.outerHTML.replace(/\\svalue="[^"]*"/g, '')), 300),
            heading: heading ? clip(line(heading.innerText), 60) : null,
            landmark: landmark, siblings: siblings,
            box: { x: r.x, y: r.y, width: r.width, height: r.height }
          };
        }

        // A class written by a person, not one a build tool hashed and will
        // rename on the next deploy.
        function steady(word) {
          return /^[a-zA-Z][\\w-]{2,29}$/.test(word) && !/\\d{3,}/.test(word) &&
                 !/^(css|sc|jsx|emotion|svelte|styles?)-/.test(word);
        }

        function selectorFor(el) {
          var kind = el.tagName.toLowerCase();
          if (el.id && steady(el.id) && unique('#' + CSS.escape(el.id))) { return '#' + CSS.escape(el.id); }
          var hooks = ['data-testid', 'data-test', 'data-qa', 'aria-label', 'role', 'name'];
          for (var i = 0; i < hooks.length; i++) {
            var value = el.getAttribute(hooks[i]);
            if (!value) { continue; }
            var byHook = kind + '[' + hooks[i] + '="' + CSS.escape(value) + '"]';
            if (unique(byHook)) { return byHook; }
          }
          var classes = typeof el.className === 'string' ? el.className.trim().split(/\\s+/).filter(steady) : [];
          if (classes.length) {
            var byClass = kind + '.' + classes.map(CSS.escape).join('.');
            if (unique(byClass)) { return byClass; }
          }
          // A path, anchored on the nearest ancestor with a name of its own.
          var parts = [], node = el;
          while (node && node.nodeType === 1 && node !== document.documentElement) {
            if (node !== el && node.id && steady(node.id) && unique('#' + CSS.escape(node.id))) {
              parts.unshift('#' + CSS.escape(node.id));
              break;
            }
            var tag = node.tagName.toLowerCase(), parent = node.parentElement;
            if (!parent) { parts.unshift(tag); break; }
            var same = Array.prototype.filter.call(parent.children, function (c) { return c.tagName === node.tagName; });
            parts.unshift(same.length > 1 ? tag + ':nth-of-type(' + (same.indexOf(node) + 1) + ')' : tag);
            node = parent;
          }
          return parts.join(' > ');
        }

        function under(event) {
          var el = document.elementFromPoint(event.clientX, event.clientY);
          if (!el || el === host || el === document.documentElement || el === document.body) { return null; }
          return el;
        }

        function show(el) {
          var r = el.getBoundingClientRect();
          box.style.display = 'block';
          box.style.left = r.left + 'px';
          box.style.top = r.top + 'px';
          box.style.width = r.width + 'px';
          box.style.height = r.height + 'px';
          tag.textContent = name(el);
          // Above the outline when there is room, tucked inside it at the top of the window.
          tag.style.top = r.top >= 26 ? '-24px' : '2px';
        }

        function onMove(event) {
          var el = under(event);
          if (!el) { return; }
          // A walk holds the outline until the pointer reaches another element.
          if (trail.length > 1 && el === trail[0]) { return; }
          trail = [el];
          target = el;
          show(el);
        }

        function swallow(event) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
        }

        function onPress(event) {
          swallow(event);
          if (event.type !== 'pointerdown' || event.button !== 0) { return; }
          // A press with no move before it — a trackpad tap — has no target yet.
          var el = target || under(event);
          if (el) { pick(el); }
        }

        function pick(el) {
          var selector = selectorFor(el), matches = count(selector);
          if (!selector || (!detail && matches !== 1)) { return; }
          post(detail ? describe(el, selector, matches) : { selector: selector, label: name(el) });
          target = null;
          trail = [];
          box.style.display = 'none';
        }

        // Every other key is the page's.
        function onKey(event) {
          if (event.key !== 'Escape') { return; }
          swallow(event);
          off();
        }

        // Comment mode's ↑ and ↓, called from Swift: the page hears keys only
        // while it has the keyboard, and after a pick the note field has it.
        // Returns whether there was an outline to walk.
        function walk(up) {
          if (!detail || !target) { return false; }
          var parent = target.parentElement;
          if (!up) {
            if (trail.length > 1) { trail.pop(); }
          } else if (parent && parent !== document.body && parent !== document.documentElement) {
            trail.push(parent);
          }
          target = trail[trail.length - 1];
          show(target);
          return true;
        }

        // Comment mode's Return, as `walk`.
        function commit() {
          if (!detail || !target) { return false; }
          pick(target);
          return true;
        }

        function on(palette, options) {
          if (live) { return; }
          live = true;
          detail = !!(options && options.detail);
          build(palette);
          // Every element, not the root alone: a link's own pointer and the
          // text beam would otherwise win wherever the page sets one.
          cursor = document.createElement('style');
          cursor.textContent = '*, *::before, *::after { cursor: crosshair !important; }';
          document.documentElement.appendChild(cursor);
          window.addEventListener('mousemove', onMove, true);
          window.addEventListener('keydown', onKey, true);
          presses.forEach(function (kind) { window.addEventListener(kind, onPress, true); });
        }

        // Swift's own stop passes `quiet`: it has ended the picker already, and
        // a late `off` would end whichever picker was started after it.
        function off(quiet) {
          if (!live) { return; }
          live = false;
          target = null;
          trail = [];
          if (cursor) { cursor.remove(); cursor = null; }
          window.removeEventListener('mousemove', onMove, true);
          window.removeEventListener('keydown', onKey, true);
          presses.forEach(function (kind) { window.removeEventListener(kind, onPress, true); });
          if (host) { host.remove(); host = null; }
          if (!quiet) { post({ off: true }); }
        }

        // Where the outline was put, or [] while it is hidden: tests cannot
        // reach into the closed shadow root, and the box animates to its place.
        function outline() {
          if (!box || box.style.display !== 'block') { return []; }
          return [box.style.left, box.style.top, box.style.width, box.style.height].map(parseFloat);
        }

        // The outline's and its label's computed colours, for the same reason.
        function look() {
          if (!box) { return null; }
          var b = getComputedStyle(box), t = getComputedStyle(tag);
          return { border: b.borderTopColor, shadow: b.boxShadow, fill: b.backgroundColor,
                   tagInk: t.color, tagFill: t.backgroundColor, tagShadow: t.boxShadow };
        }

        return { on: on, off: off, walk: walk, commit: commit, outline: outline, look: look };
      })();
    }
    """
}
