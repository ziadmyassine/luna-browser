import Foundation
import WebKit

/// Hiding a part of a page for good: the picker that chooses it, and the stylesheet
/// that keeps it hidden on every later visit.
///
/// The stylesheet goes in at `documentStart`, so a hidden banner is never seen
/// arriving and then leaving. The picker is not injected into every page — it costs
/// nothing until someone asks for it — and both run in `.defaultClient`, where the
/// page can neither see the picker nor post to it.

/// A picker that is on, and who to tell what it picks.
struct ElementPicking {
    let onPick: @MainActor (HiddenElements.Element) -> Void
    let onEnd: @MainActor () -> Void
}

extension TabController {

    static let pickMessageName = "lunaPick"

    /// Whose hidden elements this tab wears — a private window's own, like `sitePermissions`.
    public var hiddenElements: HiddenElements { .scope(for: dataStore) }

    /// The picker runs where the page can neither see it nor post as it.
    func attachPicker(to controller: WKUserContentController, relay: WKScriptMessageHandler) {
        controller.removeScriptMessageHandler(forName: Self.pickMessageName, contentWorld: .defaultClient)
        controller.add(relay, contentWorld: .defaultClient, name: Self.pickMessageName)
    }

    func detachPicker(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: Self.pickMessageName, contentWorld: .defaultClient)
        endPicking()
    }

    /// The reader and the picker were both things done to a document that has gone.
    func forgetPageTools() {
        readerIsOn = false
        endPicking()
    }

    func installHiddenStyle(into controller: WKUserContentController, host: String?) {
        hiddenStyleInstalled = hiddenElements.css(forHost: host)
        if let script = Self.hiddenStyleScript(hiddenStyleInstalled) { controller.addUserScript(script) }
    }

    func hiddenStyleIsStale(for host: String?) -> Bool {
        hiddenElements.css(forHost: host) != hiddenStyleInstalled
    }

    public var isPickingElements: Bool { picking != nil }

    /// Turns the picker on. Every element clicked is handed to `onPick` until the
    /// user presses Escape, the page goes away, or `stopPickingElements()`; then
    /// `onEnd` runs once.
    public func startPickingElements(
        onPick: @escaping @MainActor (HiddenElements.Element) -> Void,
        onEnd: @escaping @MainActor () -> Void
    ) {
        guard let webView, picking == nil else { return }
        picking = ElementPicking(onPick: onPick, onEnd: onEnd)
        webView.callAsyncJavaScript(
            Self.pickerScript + "\nwindow.__lunaPicker.on(palette);",
            arguments: ["palette": InternalPages.palette],
            in: nil,
            in: .defaultClient
        )
    }

    public func stopPickingElements() {
        guard picking != nil else { return }
        webView?.evaluateJavaScript("window.__lunaPicker && window.__lunaPicker.off();", in: nil, in: .defaultClient)
        endPicking()
    }

    func endPicking() {
        guard let ended = picking else { return }
        picking = nil
        ended.onEnd()
    }

    /// Main frame only: the picker is only ever put there, and a frame posting a
    /// selector of its own must not get one hidden on the page around it.
    func handlePickMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        if body["off"] as? Bool == true {
            endPicking()
        } else if let selector = body["selector"] as? String, !selector.isEmpty {
            let label = body["label"] as? String ?? selector
            picking?.onPick(HiddenElements.Element(selector: selector, label: label))
        }
    }

    /// Re-dresses the page on screen after its site's list changed, and swaps the
    /// script set so the next page on the site starts with the same list.
    public func applyHiddenElements() {
        guard let webView else { return }
        let css = hiddenElements.css(forHost: webView.url?.host())
        webView.callAsyncJavaScript(Self.setStyleFunction, arguments: ["css": css], in: nil, in: .defaultClient)
        guard css != hiddenStyleInstalled else { return }
        installUserScripts(
            into: webView.configuration.userContentController,
            host: webView.url?.host(),
            isFile: webView.url?.isFileURL ?? false
        )
    }

    /// Nil when the site has nothing hidden, so a page with no list pays nothing.
    static func hiddenStyleScript(_ css: String) -> WKUserScript? {
        guard !css.isEmpty else { return nil }
        let literal = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return WKUserScript(
            source: "(function (css) {\n\(setStyleFunction)\n})(\(literal));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        )
    }

    /// Before the document has a head, the root element is the only place to put it.
    private static let setStyleFunction = """
    var sheet = document.getElementById('luna-hidden');
    if (!sheet) {
      if (!css) { return; }
      sheet = document.createElement('style');
      sheet.id = 'luna-hidden';
      (document.head || document.documentElement).appendChild(sheet);
    }
    sheet.textContent = css;
    """

    /// The pointing mode. Its outline is drawn in a closed shadow root, so the
    /// page's own stylesheets cannot reach it and the internal pages' palette
    /// can, with `:root` read as the shadow host.
    ///
    /// Every kind of press is swallowed, not only `click`: pages act on
    /// `pointerdown` and `mousedown` and are gone before a click completes.
    static let pickerScript = """
    if (!window.__lunaPicker) {
      window.__lunaPicker = (function () {
        var live = false, host = null, box = null, tag = null, target = null;
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
            'border:2px solid var(--luna-text-primary);background:var(--luna-surface-selected);' +
            'border-radius:var(--luna-row-radius);transition-property:left,top,width,height;' +
            'transition-duration:var(--luna-motion-hover);transition-timing-function:ease-out}' +
            '.tag{position:absolute;left:-2px;max-width:320px;overflow:hidden;text-overflow:ellipsis;' +
            'white-space:nowrap;padding:0 8px;border-radius:var(--luna-row-radius);' +
            'font:500 var(--luna-size-label)/20px -apple-system,BlinkMacSystemFont,sans-serif;' +
            'color:var(--luna-surface-base);background:var(--luna-text-primary)}' +
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

        // What a person would call it: its own label, then its kind, then its words.
        function name(el) {
          var said = el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('alt');
          if (said && said.trim()) { return clip(said.trim(), 40); }
          var kind = el.tagName.toLowerCase();
          if (known[kind]) { return known[kind]; }
          var role = el.getAttribute('role');
          if (role) { return role.charAt(0).toUpperCase() + role.slice(1); }
          var words = (el.innerText || '').trim().replace(/\\s+/g, ' ');
          return words ? clip(words, 40) : kind;
        }

        function unique(selector) {
          try { return document.querySelectorAll(selector).length === 1; } catch (e) { return false; }
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
          if (!el) { return; }
          var selector = selectorFor(el);
          if (!selector || !unique(selector)) { return; }
          post({ selector: selector, label: name(el) });
          target = null;
          box.style.display = 'none';
        }

        function onKey(event) {
          if (event.key !== 'Escape') { return; }
          swallow(event);
          off();
        }

        function on(palette) {
          if (live) { return; }
          live = true;
          build(palette);
          document.documentElement.style.cursor = 'crosshair';
          window.addEventListener('mousemove', onMove, true);
          window.addEventListener('keydown', onKey, true);
          presses.forEach(function (kind) { window.addEventListener(kind, onPress, true); });
        }

        function off() {
          if (!live) { return; }
          live = false;
          target = null;
          document.documentElement.style.cursor = '';
          window.removeEventListener('mousemove', onMove, true);
          window.removeEventListener('keydown', onKey, true);
          presses.forEach(function (kind) { window.removeEventListener(kind, onPress, true); });
          if (host) { host.remove(); host = null; }
          post({ off: true });
        }

        return { on: on, off: off };
      })();
    }
    """
}
