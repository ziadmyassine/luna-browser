import Foundation
import WebKit

/// §3.2's **Automatic Picture-In-Picture**: a video you leave keeps playing in a floating
/// window instead of going quiet behind a tab you cannot see.
///
/// **It is JavaScript because WebKit gives no other door.** `WKWebView` can *close* every
/// media presentation — `closeAllMediaPresentations`, which §19.2 already uses so a
/// hibernated tab does not leave an orphan window — and there is no matching call to open
/// one. What the page itself has is `HTMLVideoElement.webkitSetPresentationMode`, which
/// Safari has honoured since 9 and which is the API Safari's own automatic PiP drives.
///
/// The video has to be **playing, audible and big enough to be worth floating**. Switching
/// tabs away from a muted background autoplay banner and having it pop out over the screen
/// would be the feature at its worst, and a 320-pixel test is what separates the video the
/// user was watching from the one they never noticed.
extension TabController {

    /// Called when this tab stops being the one on screen. A no-op for a cold tab, a
    /// silent tab, or a page with nothing worth floating.
    public func enterAutomaticPictureInPicture() {
        webView?.evaluateJavaScript(Self.enterPictureInPictureScript)
    }

    /// And the other edge: coming back to the tab puts the video back in the page, which
    /// is what makes the floating window feel like the tab rather than like a third thing
    /// to tidy up.
    public func leaveAutomaticPictureInPicture() {
        webView?.evaluateJavaScript(Self.leavePictureInPictureScript)
    }

    private static let enterPictureInPictureScript = """
    (function () {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.paused || v.muted || v.volume === 0) { continue; }
        if (v.videoWidth < 320 || v.readyState < 2) { continue; }
        if (typeof v.webkitSetPresentationMode !== 'function') { continue; }
        if (!v.webkitSupportsPresentationMode('picture-in-picture')) { continue; }
        if (v.webkitPresentationMode === 'picture-in-picture') { return; }
        v.webkitSetPresentationMode('picture-in-picture');
        return;
      }
    })();
    """

    private static let leavePictureInPictureScript = """
    (function () {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (typeof v.webkitSetPresentationMode !== 'function') { continue; }
        if (v.webkitPresentationMode === 'picture-in-picture') { v.webkitSetPresentationMode('inline'); }
      }
    })();
    """
}
