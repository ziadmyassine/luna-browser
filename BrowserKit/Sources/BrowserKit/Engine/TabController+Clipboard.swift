//
//  TabController+Clipboard.swift
//  BrowserKit
//
//  §18.8: a page reading the clipboard is asked about, like the camera, and the
//  answer is kept for the site in the Space (`SitePermission.clipboard`).
//
//  WebKit has no public hook for it. Measured on macOS 27 in a plain
//  `WKWebView`: `readText()`, `read()` and `execCommand('paste')` each pop
//  WebKit's own one-item "Paste" menu at the page and give the page nothing
//  unless that item is clicked, every time, with nothing for the app to hear
//  or remember; text the same site copied is read back with no menu. The SDK
//  has no clipboard preference and no `WKUIDelegate` method for it; the switch
//  that skips the menu is the private `DOMPasteAllowed` (D10).
//
//  So the three calls are replaced in the page with ones that ask Luna, and
//  Luna reads the pasteboard itself for a site that may. A page that digs the
//  originals out from somewhere this script has not reached gets WebKit's
//  menu, which still asks every time: the page can skip Luna's question, never
//  the user's.
//

import WebKit

/// What a page asked to do with the clipboard.
public enum ClipboardRequest: String, Sendable {
    /// `navigator.clipboard.readText()`: the plain text.
    case readText
    /// `navigator.clipboard.read()`: the text, the HTML and a PNG, where there are any.
    case read
    /// `document.execCommand('paste')`: the clipboard into what has focus, as Edit ▸
    /// Paste would. The call returns false at once, since it cannot wait for a question.
    case paste
}

extension TabController {

    static let clipboardMessageName = "lunaClipboard"

    /// The reply handler is registered in the page's own world, because that is where
    /// the calls it replaces live. A page can post to it directly as well, which buys
    /// it nothing: the answer is decided here, for the frame that posted.
    func attachClipboard(to controller: WKUserContentController, relay: ScriptMessageRelay) {
        controller.removeScriptMessageHandler(forName: Self.clipboardMessageName, contentWorld: .page)
        controller.addScriptMessageHandler(relay, contentWorld: .page, name: Self.clipboardMessageName)
    }

    func detachClipboard(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: Self.clipboardMessageName, contentWorld: .page)
    }

    /// The clipboard as the page will get it, keyed by MIME type, or nil for a refusal.
    ///
    /// The host is the frame's origin, as for the camera: an embedded site asks as
    /// itself. A standing yes still reads only for the tab in front, which the delegate
    /// decides; a page in the background reading what was just copied is the thing
    /// this is here to stop.
    func handleClipboardMessage(_ message: WKScriptMessage) async -> [String: String]? {
        guard let body = message.body as? [String: Any],
              let request = (body["op"] as? String).flatMap(ClipboardRequest.init(rawValue:))
        else { return nil }
        let host = message.frameInfo.securityOrigin.host
        guard await decide([.clipboard], host: host) == .grant else { return nil }
        return await delegate?.tabController(self, readsClipboard: request)
    }

    /// `documentStart`, so the page's own scripts only ever see these; every frame,
    /// because an embedded editor reads the clipboard as often as a page does.
    static func clipboardUserScript() -> WKUserScript {
        WKUserScript(source: clipboardScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static let clipboardScript = """
    (function () {
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaClipboard;
      if (!h) { return; }
      function ask(op) { return h.postMessage({ op: op }); }
      function refused() { return new DOMException('Reading the clipboard is not allowed.', 'NotAllowedError'); }
      function bytes(base64) {
        var raw = atob(base64), out = new Uint8Array(raw.length);
        for (var i = 0; i < raw.length; i++) { out[i] = raw.charCodeAt(i); }
        return out;
      }
      if (typeof Clipboard !== 'undefined') {
        Clipboard.prototype.readText = function () {
          return ask('readText').then(function (got) {
            if (!got) { throw refused(); }
            return got['text/plain'] || '';
          });
        };
        Clipboard.prototype.read = function () {
          return ask('read').then(function (got) {
            if (!got) { throw refused(); }
            var parts = {}, any = false;
            Object.keys(got).forEach(function (type) {
              var data = type.indexOf('image/') === 0 ? bytes(got[type]) : got[type];
              parts[type] = new Blob([data], { type: type });
              any = true;
            });
            return any ? [new ClipboardItem(parts)] : [];
          });
        };
      }
      var exec = Document.prototype.execCommand;
      Document.prototype.execCommand = function (command) {
        if (String(command).toLowerCase() === 'paste') { ask('paste').catch(function () {}); return false; }
        return exec.apply(this, arguments);
      };
    })();
    """
}
