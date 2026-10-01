//
//  TabController+Media.swift
//  BrowserKit
//
//  Which frames of the tab are making a sound — the speaker on its row, and
//  §19.2's rule that a tab playing audio is not put to sleep. The mute that
//  silences them is next door in `TabController+Mute.swift`.
//

import WebKit

extension TabController {

    func handleMediaMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let audible = body["audible"] as? Bool
        else { return }
        let frame = message.frameInfo.isMainFrame
            ? "" : (message.frameInfo.request.url?.absoluteString ?? "subframe")
        // Only when the set actually moved. `publishState` reads eight properties
        // off the web view and converts two colours, and a message that says what
        // the last one said is not news — the script below already drops most of
        // those, and this is the half of the guard that does not trust a page.
        if audible { playedAudio = true }
        let changed = audible ? audibleFrames.insert(frame).inserted : audibleFrames.remove(frame) != nil
        guard changed else { return }
        publishState()
    }

    /// Reports whether any media element in the frame is audible — playing, unmuted
    /// and above zero volume. `requestMediaPlaybackState()` would call a muted autoplay
    /// video "playing" and put a speaker badge on half the sidebar.
    ///
    /// Media events do not bubble, so the listeners are registered in the capture phase;
    /// that is the only way one document-level listener sees every `<video>`.
    ///
    /// It only speaks when the answer changes. This runs in every frame
    /// (`forMainFrameOnly: false`, because an embedded player lives in a
    /// subframe), and posting from each at document end to say what silence
    /// already says makes a page with ten ad iframes ten messages across the
    /// process boundary and ten `publishState` calls before it has loaded.
    /// `false` is what the tab already is — `resetPerDocumentState` empties
    /// `audibleFrames` on every navigation — so the opening `post()` reports
    /// only a frame already making noise, the autoplay case. The same latch
    /// drops the `volumechange` ticks of a volume drag that do not cross zero.
    ///
    /// Internal rather than private so `MediaScriptTests` can run it — the
    /// same reason `scrollScript` is.
    static let mediaScript = """
    (function () {
      var last = false;
      var post = function () {
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaMedia;
        if (!h) { return; }
        var audible = false;
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
          var m = media[i];
          if (!m.paused && !m.muted && m.volume > 0) { audible = true; break; }
        }
        if (audible === last) { return; }
        last = audible;
        h.postMessage({ audible: audible });
      };
      ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied'].forEach(function (name) {
        document.addEventListener(name, post, true);
      });
      post();
    })();
    """
}
