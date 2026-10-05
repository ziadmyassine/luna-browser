import Foundation
import WebKit

/// §17.2's annoyances, finished: a consent dialog the list hid takes its lock with it.
///
/// fanboy-annoyance hides cookie dialogs with generic rules (`##div.cookiebanner`),
/// and a hidden dialog does not undo what the page did to show it — a dimmed
/// backdrop over everything, the page's scroll switched off, the rest of the
/// document made `inert`. The list's answer is a per-site exception for each site
/// that breaks (`FilterListConverter.Unhide`); this is the answer for the sites it
/// has not reached yet. Measured on borger.dk: the dialog hidden, and over the page
/// an empty full-window `role="dialog"` box, a backdrop and `overflow: hidden`, all
/// switched on by one `dialog-open` class, so not one click landed.
///
/// It acts only when all of it is true at once: something named for consent is not
/// rendered, no dialog with anything in it is showing, and the page is still locked. A page whose own
/// dialog is open — a sign-in, a gallery — is left alone, and so is every page the
/// list hid nothing on.
extension ContentBlocker {

    /// Whether ``consentUnlockScript`` belongs on `host`: the annoyances list is on,
    /// and blocking is not off for the site.
    public func unlocksConsent(forHost host: String?, in scope: SitePermissions = .shared) -> Bool {
        isEnabled(.annoyances) && !isDisabled(forHost: host, in: scope)
    }

    /// Its own world: the page cannot see it, and nothing the page defines can
    /// change what it reads.
    public static let consentUnlockWorld = WKContentWorld.world(name: "luna-consent-unlock")

    public static var consentUnlockUserScript: WKUserScript {
        WKUserScript(
            source: consentUnlockScript, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: consentUnlockWorld
        )
    }

    /// Watches for 20 s after the document is parsed, because consent managers
    /// inject their dialog after load, then stops.
    ///
    /// The cover is found by asking the page what is under the pointer, not by
    /// class name: whatever is topmost at the viewport's middle and corners, fixed,
    /// nearly viewport-sized and empty of text and controls is a backdrop with
    /// nothing left in front of it.
    public static let consentUnlockScript = """
    (function () {
      var named = '[id*="cookie" i], [class*="cookie" i], [id*="consent" i], [class*="consent" i], '
        + '[id*="gdpr" i], [class*="gdpr" i], [aria-label*="cookie" i], [aria-label*="consent" i]';
      var dialogs = '[aria-modal="true"], dialog[open], [role="dialog"], [role="alertdialog"]';
      var lockClass = /(^|[\\s_-])(no-?scroll|scroll-?lock|modal-open|dialog-open|has-dialog|overflow-hidden|locked|cookie|consent)/i;
      var some = Array.prototype.some;

      function rendered(el) {
        if (!el.getClientRects().length) { return false; }
        var style = getComputedStyle(el);
        return style.visibility !== 'hidden' && style.opacity !== '0';
      }
      function hasContent(el) {
        return (el.innerText || '').trim() !== ''
          || el.querySelector('a, button, input, select, textarea, img, video, canvas, iframe') !== null;
      }
      function consentHidden() {
        return some.call(document.querySelectorAll(named), function (el) { return !el.getClientRects().length; });
      }
      // An empty one is not a dialog anyone can use; it is part of the cover.
      function dialogShowing() {
        return some.call(document.querySelectorAll(dialogs), function (el) { return rendered(el) && hasContent(el); });
      }
      function cover() {
        var width = innerWidth, height = innerHeight;
        var points = [[width / 2, height / 2], [width / 4, height / 4], [width * 3 / 4, height * 3 / 4]];
        for (var i = 0; i < points.length; i++) {
          var el = document.elementFromPoint(points[i][0], points[i][1]);
          if (!el || el === document.body || el === document.documentElement) { continue; }
          var box = el.getBoundingClientRect();
          if (getComputedStyle(el).position === 'fixed' && box.width >= width * 0.9
              && box.height >= height * 0.9 && !hasContent(el)) { return el; }
        }
        return null;
      }

      function unlock() {
        if (!document.body || dialogShowing() || !consentHidden()) { return; }
        var freed = false;
        for (var i = 0, el; i < 3 && (el = cover()); i++) {
          el.style.setProperty('display', 'none', 'important');
          freed = true;
        }
        Array.prototype.forEach.call(document.body.children, function (child) {
          if (child.hasAttribute('inert')) { child.removeAttribute('inert'); freed = true; }
          if (child.getAttribute('aria-hidden') === 'true' && rendered(child) && hasContent(child)) {
            child.removeAttribute('aria-hidden');
            freed = true;
          }
        });
        [document.documentElement, document.body].forEach(function (el) {
          if (!freed && !lockClass.test(el.className || '')) { return; }
          var style = getComputedStyle(el);
          if (style.overflowY === 'hidden' || style.overflow === 'hidden') {
            el.style.setProperty('overflow', 'auto', 'important');
          }
        });
      }

      var pending = null;
      var observer = new MutationObserver(function () {
        if (pending) { return; }
        pending = setTimeout(function () { pending = null; unlock(); }, 150);
      });
      observer.observe(document.documentElement, {
        subtree: true, childList: true, attributes: true,
        attributeFilter: ['class', 'style', 'hidden', 'inert', 'aria-hidden', 'open']
      });
      setTimeout(function () { observer.disconnect(); }, 20000);
      addEventListener('load', unlock);
      unlock();
    })();
    """
}
