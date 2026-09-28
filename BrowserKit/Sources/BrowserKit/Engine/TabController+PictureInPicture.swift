import Foundation
import WebKit

public enum PictureInPictureAnswer: Sendable {
    case floating, backInPage, noVideo
}

/// §3.2's Automatic Picture-In-Picture: a video you leave keeps playing in a floating
/// window instead of going quiet behind a tab you cannot see.
///
/// It is JavaScript because WebKit gives no other door. `WKWebView` can close every
/// media presentation — `closeAllMediaPresentations`, which §19.2 already uses so a
/// hibernated tab does not leave an orphan window — and there is no matching call to open
/// one. What the page itself has is `HTMLVideoElement.webkitSetPresentationMode`, which
/// Safari has honoured since 9 and which is the API Safari's own automatic PiP drives.
///
/// The video has to be playing, audible and big enough to be worth floating. Switching
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

    /// ⇧⌘P: floats the page's video, or puts back the one already floating.
    /// Unlike the automatic path, a muted or paused video counts — the user
    /// asked for this one. A playing video wins over a larger paused one.
    ///
    /// `done` hears which of the three happened, and nothing when the page could
    /// not be asked at all.
    public func togglePictureInPicture(_ done: @escaping @MainActor (PictureInPictureAnswer) -> Void = { _ in }) {
        webView?.evaluateJavaScript(Self.togglePictureInPictureScript) { result, _ in
            switch result as? String {
            case "picture-in-picture": done(.floating)
            case "inline": done(.backInPage)
            case "none": done(.noVideo)
            default: break
            }
        }
    }

    private static let togglePictureInPictureScript = """
    (function () {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (videos[i].webkitPresentationMode === 'picture-in-picture') {
          videos[i].webkitSetPresentationMode('inline');
          return 'inline';
        }
      }
      var best = null, most = 0;
      for (var j = 0; j < videos.length; j++) {
        var v = videos[j];
        if (v.readyState < 2 || typeof v.webkitSetPresentationMode !== 'function') { continue; }
        if (!v.webkitSupportsPresentationMode('picture-in-picture')) { continue; }
        var box = v.getBoundingClientRect();
        var weight = box.width * box.height + (v.paused ? 0 : 1e9);
        if (weight > most) { most = weight; best = v; }
      }
      if (!best) { return 'none'; }
      best.webkitSetPresentationMode('picture-in-picture');
      return 'picture-in-picture';
    })();
    """

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
