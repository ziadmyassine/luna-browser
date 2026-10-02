import Foundation
import WebKit

/// The Chrome Web Store hybrid: the page script that hijacks Google's own "Add
/// to Chrome" button, and the message routing behind it.
///
/// The store is sent a Chrome UA (`WebViewFactory.userAgent(for:)`) so the
/// button renders live; this script relabels it "Add to Luna" and turns its
/// click into Luna's install. Google greys the button out and marks the item
/// unavailable when its own install path is missing, which in WebKit it always
/// is — so the script re-enables the button every pass and hides the matching
/// unavailable notice. Our click never uses Google's install (it downloads the
/// CRX itself), so the store's verdict does not apply. When the button cannot be
/// found — a Google redesign, the SPA not
/// yet rendered, a script error — nothing is said and the app falls back to its
/// toast (`WebStoreOffer`). The install target is read from `webView.url`, never
/// from the page, so the page cannot name what gets installed.
extension TabController {

    static let webStoreMessageName = "lunaWebStore"

    /// Whether this tab should carry the button-hijack script, gated on both: the
    /// extension controller is nil in a private window, where extensions cannot
    /// run, and the script has nothing to do off the store's own host.
    func wantsWebStoreScript(host: String?) -> Bool {
        webExtensionController != nil && WebViewFactory.isWebStoreHost(host)
    }

    /// Adds the script when the gate is open, and records what it did for
    /// `refreshUserScriptsIfNeeded`. Main frame only — the button is the page's,
    /// not a subframe's — and `documentEnd`, with a `MutationObserver` inside for
    /// the SPA's later renders.
    func installWebStoreScript(into controller: WKUserContentController, host: String?) {
        webStoreScriptInstalled = wantsWebStoreScript(host: host)
        guard webStoreScriptInstalled else { return }
        controller.addUserScript(
            WKUserScript(source: Self.webStoreScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }

    func handleWebStoreMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let signal = Self.webStoreSignal(from: body) else { return }
        guard let url = webView?.url else { return }
        switch signal {
        case .handled:
            onWebStoreButtonReady?(url)
        case .add:
            onWebStoreAddRequested?(url)
        }
    }

    /// Tell the store page its extension is in: the hijacked button becomes
    /// "Added". The script runs in the page world (its handler is registered with
    /// no content world), so the call is made there too, not `.defaultClient`.
    public func webStoreButtonAdded() {
        webView?.evaluateJavaScript(
            "window.__lunaStoreAdded && window.__lunaStoreAdded();", in: nil, in: .page
        )
    }

    /// What the page asked for. A test-only parsing aid, kept pure because a
    /// `WKScriptMessage` cannot be built in a unit test; the public seam is the
    /// two `on…` closures, not this.
    enum WebStoreSignal { case handled, add }

    static func webStoreSignal(from body: [String: Any]) -> WebStoreSignal? {
        switch body["kind"] as? String {
        case "handled": .handled
        case "add": .add
        default: nil
        }
    }

    /// Finds Google's button by what it says, not how it is built — the class
    /// names are hashed and renamed on each deploy, the same reason the picker
    /// matches on steady signals (`TabController+Hiding.swift`). It relabels the
    /// button, swallows its click like `pickerScript`'s `swallow`, and posts
    /// `handled` exactly once per document while the SPA re-renders the node.
    static let webStoreScript = """
    (function () {
      var MARK = 'data-luna-store';
      var RE = /add to chrome/i;
      var announced = false;
      var added = false;

      function post(body) {
        var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaWebStore;
        if (mh) { try { mh.postMessage(body); } catch (e) {} }
      }

      function swallow(event) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
      }

      function said(el) {
        return (el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '');
      }

      function findButton() {
        var all = document.querySelectorAll('button, [role="button"], a');
        for (var i = 0; i < all.length; i++) {
          // Also match our own marked node: once relabelled it no longer says
          // "add to chrome", but it still needs re-enabling if the SPA re-greys it.
          if (RE.test(said(all[i])) || all[i].hasAttribute(MARK)) { return all[i]; }
        }
        return null;
      }

      // Google disables the button (and may set aria-disabled or pointer-events)
      // for an item it will not install; a disabled button never dispatches the
      // click our listener waits on, so clear the lot on every pass.
      function enable(el) {
        if (el.removeAttribute) {
          el.removeAttribute('disabled');
          el.removeAttribute('aria-disabled');
        }
        if (el.style) {
          el.style.pointerEvents = 'auto';
          el.style.opacity = '1';
          el.style.cursor = 'pointer';
        }
      }

      // Rewrite the words in place, in the text node that holds them, so the span
      // carrying Google's white-on-blue colour survives — overwriting the button's
      // textContent flattens that span and the label turns black. Only ever write
      // when the text actually matches: a no-op textContent assignment is still a
      // childList change, and with `added` set it fed the observer an endless loop.
      function swap(el, re, to) {
        if (document.createTreeWalker && typeof NodeFilter !== 'undefined') {
          var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false);
          var node;
          while ((node = walker.nextNode())) {
            if (re.test(node.nodeValue)) { node.nodeValue = node.nodeValue.replace(re, to); }
          }
        } else if (re.test(el.textContent || '')) {
          el.textContent = (el.textContent || '').replace(re, to);
        }
        var aria = el.getAttribute('aria-label');
        if (aria && re.test(aria)) { el.setAttribute('aria-label', aria.replace(re, to)); }
      }

      function relabel(el) { swap(el, RE, 'Add to Luna'); }

      // Once added, the button is done, not a call to action: grey out Google's
      // blue (grayscale keeps the white label readable whatever colour they use),
      // dim it, and drop the pointer cursor. Style only — never childList — so it
      // cannot feed the observer. `enable` runs first each pass, so this overrides.
      function markDone(el) {
        if (!el.style) { return; }
        el.style.filter = 'grayscale(1)';
        el.style.opacity = '0.6';
        el.style.cursor = 'default';
      }

      // The store marks every item unavailable here (its own install is missing),
      // leaving a notice that is false for Luna's install. Hide the smallest
      // element that carries it, and the guide link beside it, on every pass.
      function hideSmallest(test) {
        var all = document.querySelectorAll('div, section, p, span, a, button');
        var best = null, bestLen = Infinity;
        for (var i = 0; i < all.length; i++) {
          var text = (all[i].textContent || '').trim();
          if (text && test(text) && text.length < bestLen) { best = all[i]; bestLen = text.length; }
        }
        if (best && best.style) { best.style.display = 'none'; }
      }

      function hideUnavailable() {
        hideSmallest(function (t) { return /currently unavailable/i.test(t); });
        hideSmallest(function (t) { return t.toLowerCase() === 'view guide'; });
      }

      function apply() {
        var button = findButton();
        if (!button) { return; }
        enable(button);
        hideUnavailable();
        if (!button.hasAttribute(MARK)) {
          button.setAttribute(MARK, '1');
          relabel(button);
          button.addEventListener('click', function (event) {
            swallow(event);
            if (!added) { post({ kind: 'add' }); }
          }, true);
        }
        if (added) { swap(button, /add to luna/i, 'Added'); markDone(button); }
        // Once per document, after the button is placed: later passes relabel the
        // re-rendered node without telling native again.
        if (!announced) {
          announced = true;
          post({ kind: 'handled' });
        }
      }

      // Native calls this once the install the button asked for has gone through.
      // The flag also survives the SPA re-rendering the button (`apply` re-reads it).
      window.__lunaStoreAdded = function () {
        added = true;
        var button = findButton();
        if (button) { swap(button, /add to luna/i, 'Added'); markDone(button); }
      };

      apply();
      var observer = new MutationObserver(apply);
      observer.observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}
