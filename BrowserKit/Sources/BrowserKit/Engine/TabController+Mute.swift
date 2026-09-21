//
//  TabController+Mute.swift
//  Luna
//
//  §3.4a's mute: silencing one tab without pausing it.
//
//  There is no public WebKit API for this. Safari's own per-tab mute rides on
//  `WKWebView._setPageMuted:`, which is SPI — this project checks every AppKit and WebKit
//  call against the installed SDK headers (`Glass.swift`'s contract, rule 4, is the same
//  argument one layer up) and a private selector that disappears in a point release is not
//  a feature, it is a future crash. The two public calls that come close are the wrong
//  shape: `pauseAllMediaPlayback()` stops the video as well as the sound, and
//  `setAllMediaPlaybackSuspended(true)` additionally refuses to let it start again. Mute
//  means keep playing, quietly, which is a property of the media elements. So it is set
//  on the media elements.
//
//  Three things make that hold up on a real page rather than only on a `<video>` that was
//  already in the DOM when the menu item fired:
//
//    · `volumechange` in the capture phase. Media events do not bubble, so one
//      document-level listener only sees every element if it is registered capturing —
//      the same finding `mediaScript` is built on. A player that un-mutes itself when the
//      user un-mutes it in its own controls is put back.
//    · A `MutationObserver` on the whole document. A `<video>` appended after the fact
//      — which is every video on every site that builds its player in JavaScript — has to
//      be caught on arrival, not on the one pass that ran when the item was clicked.
//    · `didCommit`, not `didFinish`. A new document has new media elements at their
//      own defaults, and an autoplaying page is making noise long before the load settles.
//
//  Setting `muted` to the value it already holds fires nothing, so the `volumechange`
//  listener re-asserting the flag terminates instead of looping.
//
//  The script is installed only on tabs that have actually been muted — `evaluateJavaScript`
//  on demand rather than a `WKUserScript` on every page — because un-installing a user
//  script means `removeAllUserScripts()`, which would take §17's blocked-count script and
//  §3.2b's scroll reporter with it.
//

import WebKit

public extension TabController {

    /// Whether this tab's media is silenced (§3.4a).
    ///
    /// Survives navigation within the tab and — because `BrowserSession` re-asserts it on
    /// `ensureController` — the tab going cold and waking up again. It does not survive
    /// a relaunch: a mute is a thing you do to the noise happening now, and a tab that comes
    /// back silent after a restart with no way to see why is worse than one that does not.
    var isMuted: Bool {
        get { mutedStorage }
        set {
            guard newValue != mutedStorage else { return }
            mutedStorage = newValue
            pushMuteState()
        }
    }

    /// Re-asserts the mute on a document that has just replaced the one it was set on.
    ///
    /// Only when the tab is muted, which is the whole difference between this and the
    /// setter: a fresh document's media elements are unmuted already, so there is nothing
    /// to undo and no reason to put a `MutationObserver` on a page nobody silenced.
    func reapplyMute() {
        guard mutedStorage else { return }
        pushMuteState()
    }

    /// Safe on a hibernated tab, on a page with no JavaScript, and twice in a row.
    private func pushMuteState() {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.muteScript(mutedStorage)) { _, _ in
            // A failure here is a page that cannot run scripts — a PDF, an error page, a
            // document whose process has gone. None of those are making a sound.
        }
    }

    /// Sets `muted` on every media element in the main frame and keeps doing so.
    ///
    /// Main frame only, which is this script's one honest limitation: `evaluateJavaScript`
    /// does not reach subframes, so an embedded player in an iframe keeps playing. The
    /// sidebar's speaker badge does not have that limitation — `mediaScript` is injected
    /// `forMainFrameOnly: false` — so a muted tab can still report itself audible. That is
    /// the truth rather than a bug in the badge, and it is named here rather than hidden.
    private static func muteScript(_ muted: Bool) -> String {
        """
        (function (muted) {
          window.__lunaMuted = muted;
          var apply = function () {
            var media = document.querySelectorAll('video, audio');
            for (var i = 0; i < media.length; i++) { media[i].muted = window.__lunaMuted; }
          };
          if (!window.__lunaMuteHooked) {
            window.__lunaMuteHooked = true;
            ['play', 'playing', 'loadedmetadata', 'volumechange'].forEach(function (name) {
              document.addEventListener(name, apply, true);
            });
            if (document.documentElement) {
              new MutationObserver(apply).observe(document.documentElement, {
                childList: true, subtree: true
              });
            }
          }
          apply();
        })(\(muted ? "true" : "false"));
        """
    }
}
