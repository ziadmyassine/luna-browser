//
//  TabController+Mute.swift
//  Luna
//
//  §3.4a's mute: silencing one tab without pausing it.
//
//  No public WebKit API does this. Safari's per-tab mute is SPI
//  (`_setPageMuted:`), `pauseAllMediaPlayback()` stops the video with the
//  sound, and `setAllMediaPlaybackSuspended(true)` also refuses to restart it.
//  So it is `muted` on the media elements, held by a capturing `volumechange`
//  listener (media events do not bubble), a `MutationObserver` for players
//  built after the fact, and a re-assert on `didCommit`, not `didFinish`, since
//  an autoplaying page is loud before the load settles. Setting `muted` to its
//  own value fires nothing, so the listener's re-assert does not loop.
//
//  Evaluated on demand in muted tabs rather than installed as a `WKUserScript`:
//  removing one means `removeAllUserScripts()`, which would take §17's
//  blocked-count script and §3.2b's scroll reporter with it.
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
    /// the truth rather than a bug in the badge.
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
