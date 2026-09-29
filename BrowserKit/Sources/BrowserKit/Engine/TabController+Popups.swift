import Foundation
import WebKit

/// §17's pop-up blocker, where it meets WebKit: the `createWebViewWith`
/// decision, the tab-under guard in `decidePolicyFor`, and the page script that
/// witnesses what WebKit refuses without asking. The rules are `PopupPolicy`'s.
extension TabController {

    static let popupMessageName = "lunaPopup"

    /// WebKit's number for the middle button, the same as `NSEvent`'s.
    private static let middleButton = 2

    private var popupMode: PopupMode { PopupPolicy.mode(in: settings) }

    /// Whether the new window `navigationAction` asks for may open. Records it
    /// when it may not.
    func allowsPopup(_ navigationAction: WKNavigationAction) -> Bool {
        let mode = popupMode
        let url = navigationAction.request.url
        let opener = webView?.url
        let request = PopupPolicy.Request(
            url: url,
            openerURL: opener,
            isModifiedClick: navigationAction.modifierFlags.contains(.command)
                || navigationAction.buttonNumber == Self.middleButton,
            pressedLink: popups.pressedLink,
            siteAllowed: sitePermissions.isAllowed(.popups, forHost: opener?.host())
        )
        let allowed = PopupPolicy.allows(request, mode: mode)
        // Anything reaching here under a blocking mode came with a gesture —
        // WebKit refused the rest — and a gesture is what a tab-under rides.
        if mode != .off { popups.arm(exempt: url.map(PopupPolicy.isSignIn) ?? false) }
        pendingProbation = PopupPolicy.needsProbation(request, mode: mode)
            ? PopupProbation(opener: self, openerURL: opener, pressedLink: popups.pressedLink)
            : nil
        // A pop-up with no web address has nothing to open later, so there is
        // nothing to offer back.
        if !allowed, let url, PopupPolicy.reportedURL(url.absoluteString, relativeTo: nil) != nil {
            noteBlockedPopup(url)
        }
        return allowed
    }

    /// Hands the opener's context to the blank pop-up's own tab, once the
    /// delegate has built it.
    func placeOnProbation(_ child: WKWebView?) {
        defer { pendingProbation = nil }
        guard let probation = pendingProbation, let tab = child?.navigationDelegate as? TabController else { return }
        tab.popups.probation = probation
    }

    /// A blank pop-up's first navigation away from blank. Scripted, it is judged
    /// on the opener's behalf: refused, the pop-up closes and the opener records
    /// the address, so its chip opens where the pop-up was headed. One the user
    /// made inside the pop-up is theirs, and ends probation unjudged.
    func refusesOnProbation(_ navigationAction: WKNavigationAction, to url: URL) -> Bool {
        guard let probation = popups.probation, !PopupPolicy.isBlank(url) else { return false }
        popups.probation = nil
        guard navigationAction.navigationType == .other, !probation.allows(url) else { return false }
        delegate?.tabControllerWantsToClose(self)
        probation.opener?.noteBlockedPopup(url)
        return true
    }

    /// The tab-under guard, for a main-frame navigation.
    func refusesTabUnder(_ navigationAction: WKNavigationAction, to url: URL) -> Bool {
        let opener = webView?.url
        guard !sitePermissions.isAllowed(.popups, forHost: opener?.host()),
              popups.refusesTabUnder(
                  to: url, from: opener, isUserInitiated: navigationAction.navigationType != .other
              )
        else { return false }
        noteBlockedPopup(url)
        return true
    }

    /// WebKit reads the preference when a page calls `window.open`, so setting
    /// it before each main-frame navigation brings an open tab up to a mode
    /// changed in Settings.
    func applyPopupMode(to webView: WKWebView) {
        let opens = popupMode == .off
        let preferences = webView.configuration.preferences
        if preferences.javaScriptCanOpenWindowsAutomatically != opens {
            preferences.javaScriptCanOpenWindowsAutomatically = opens
        }
    }

    func noteBlockedPopup(_ url: URL) {
        guard popups.record(url) else { return }
        delegate?.tabController(self, didBlockPopup: url)
    }

    /// Either the link under a trusted press, or a `window.open` that came back
    /// null. Both are the page's to forge, so both pass `reportedURL`; a forged
    /// press can only vouch for an address the page could have linked to, and a
    /// forged report only adds a line to the page's own list.
    func handlePopupMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let frameURL = message.frameInfo.request.url
        if body.keys.contains("pressed") {
            popups.pressedLink = PopupPolicy.reportedURL(body["pressed"], relativeTo: frameURL)
        } else if popupMode != .off, let url = PopupPolicy.reportedURL(body["blocked"], relativeTo: frameURL) {
            noteBlockedPopup(url)
        }
    }

    /// Two witnesses, because WebKit has no callback for either. A trusted
    /// `pointerdown` names the link it landed on, for `PopupPolicy`'s
    /// pressed-link rule. And `window.open` is wrapped so that one WebKit
    /// refused itself — no gesture — is still reported: the original is called
    /// first and only a null result is news.
    static let popupScript = """
    (function () {
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaPopup;
      if (!h) { return; }
      document.addEventListener('pointerdown', function (event) {
        if (!event.isTrusted) { return; }
        var target = event.target;
        var link = target && target.closest ? target.closest('a[href]') : null;
        h.postMessage({ pressed: link && typeof link.href === 'string' ? link.href : '' });
      }, true);
      var open = window.open;
      window.open = function (url) {
        var opened = open.apply(this, arguments);
        if (opened === null && url) { h.postMessage({ blocked: String(url) }); }
        return opened;
      };
    })();
    """
}
