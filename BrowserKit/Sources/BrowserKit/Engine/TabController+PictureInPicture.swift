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
///
/// Every frame, not only the page: an embedded player — a YouTube or Vimeo embed in an
/// article — is a cross-origin iframe the page's own script cannot reach. Each subframe
/// with a video says so once (`pictureInPictureScript`), and the scripts here run in the
/// main frame and then in those, through `callAsyncJavaScript`'s frame argument. They run
/// in `.defaultClient`, the world the page cannot see, so a page cannot fake the
/// "back to tab" report that brings Luna forward.
extension TabController {

    static let pictureInPictureMessageName = "lunaPictureInPicture"

    /// The main frame (nil), then every subframe that has reported a video.
    private var pictureInPictureFrames: [WKFrameInfo?] { [nil] + videoFrames }

    /// Called when this tab stops being the one on screen. A no-op for a cold tab, a
    /// silent tab, or a page with nothing worth floating. The first frame that floats
    /// something ends the search: the system has one Picture in Picture window.
    public func enterAutomaticPictureInPicture() {
        Task { [weak self] in
            guard let frames = self?.pictureInPictureFrames else { return }
            for frame in frames {
                let answer = await self?.run(Self.enterScript, in: frame) as? String
                if answer == "picture-in-picture" { return }
            }
        }
    }

    /// And the other edge: coming back to the tab puts the video back in the page, which
    /// is what makes the floating window feel like the tab rather than like a third thing
    /// to tidy up.
    public func leaveAutomaticPictureInPicture() {
        Task { [weak self] in
            guard let frames = self?.pictureInPictureFrames else { return }
            for frame in frames { _ = await self?.run(Self.leaveScript, in: frame) }
        }
    }

    /// ⇧⌘P: floats the page's video, or puts back the one already floating.
    /// Unlike the automatic path, a muted or paused video counts — the user
    /// asked for this one. A playing video wins over a larger paused one,
    /// whichever frame each is in.
    ///
    /// `done` hears which of the three happened, and nothing when the page could
    /// not be asked at all.
    public func togglePictureInPicture(_ done: @escaping @MainActor (PictureInPictureAnswer) -> Void = { _ in }) {
        guard webView != nil else { return }
        Task { [weak self] in
            guard let frames = self?.pictureInPictureFrames else { return }
            var answers: [String] = []
            for frame in frames { answers.append(await self?.run(Self.leaveScript, in: frame) as? String ?? "") }
            if answers.contains("inline") { return done(.backInPage) }
            var best: (frame: WKFrameInfo?, weight: Double)?
            for frame in frames {
                guard let weight = await self?.run(Self.weighScript, in: frame) as? Double, weight > 0 else { continue }
                if weight > best?.weight ?? 0 { best = (frame, weight) }
            }
            guard let best else { return done(.noVideo) }
            _ = await self?.run(Self.floatScript, in: best.frame)
            done(.floating)
        }
    }

    /// The script's answer, or nil when the frame is gone — and then it is
    /// forgotten, which is how a subframe that navigated or was removed leaves
    /// the list.
    private func run(_ body: String, in frame: WKFrameInfo?) async -> Any? {
        guard let webView else { return nil }
        do {
            return try await webView.callAsyncJavaScript(body, in: frame, contentWorld: .defaultClient)
        } catch {
            if let frame { videoFrames.removeAll { $0 === frame } }
            return nil
        }
    }

    // MARK: - What the frames report

    func attachPictureInPicture(to controller: WKUserContentController, relay: WKScriptMessageHandler) {
        controller.removeScriptMessageHandler(forName: Self.pictureInPictureMessageName, contentWorld: .defaultClient)
        controller.add(relay, contentWorld: .defaultClient, name: Self.pictureInPictureMessageName)
    }

    func handlePictureInPictureMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["video"] as? Bool == true, !message.frameInfo.isMainFrame {
            // A handful is plenty: a page with more embedded players than this
            // is not one anybody is floating from.
            videoFrames = Array((videoFrames + [message.frameInfo]).suffix(8))
        }
        if body["returned"] as? Bool == true {
            delegate?.tabControllerDidReturnFromPictureInPicture(self)
        }
    }

    static let pictureInPictureUserScript = WKUserScript(
        source: pictureInPictureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient
    )

    /// Two reports. A subframe that has a video says so once. And a video
    /// leaving Picture in Picture still playing is the floating window's "back
    /// to tab", unless one of the scripts above put it back (`__lunaPuttingBack`).
    /// The window's close button pauses the video as it closes; the pause and
    /// the mode change are separate events, so the answer waits 300 ms for
    /// the pause before calling it a return. Only real mode changes count —
    /// a page dispatching its own event is not trusted.
    ///
    /// Internal rather than private so `PictureInPictureFrameTests` can run it.
    static let pictureInPictureScript = """
    (function () {
      var post = function (body) {
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaPictureInPicture;
        if (h) { h.postMessage(body); }
      };
      if (window !== window.top) {
        var said = false;
        var note = function (event) {
          if (said || (event && !(event.target instanceof HTMLVideoElement))) { return; }
          said = true;
          post({ video: true });
        };
        if (document.querySelector('video')) { note(); }
        ['loadedmetadata', 'play'].forEach(function (name) { document.addEventListener(name, note, true); });
      }
      var floating = new WeakSet();
      document.addEventListener('webkitpresentationmodechanged', function (event) {
        var v = event.target;
        if (!event.isTrusted || !(v instanceof HTMLVideoElement)) { return; }
        if (v.webkitPresentationMode === 'picture-in-picture') { floating.add(v); return; }
        if (!floating.has(v)) { return; }
        floating.delete(v);
        if (Date.now() - (window.__lunaPuttingBack || 0) < 1000) { return; }
        setTimeout(function () { if (!v.paused) { post({ returned: true }); } }, 300);
      }, true);
    })();
    """

    // MARK: - The scripts, one frame each

    /// Puts back a floating video. "inline" when there was one.
    private static let leaveScript = """
    var videos = document.querySelectorAll('video');
    var answer = 'none';
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (typeof v.webkitSetPresentationMode !== 'function') { continue; }
      if (v.webkitPresentationMode === 'picture-in-picture') {
        window.__lunaPuttingBack = Date.now();
        v.webkitSetPresentationMode('inline');
        answer = 'inline';
      }
    }
    return answer;
    """

    /// How much this frame's best video deserves to float: its area, and a
    /// billion more for playing. Zero for nothing that can.
    private static let weighScript = """
    var videos = document.querySelectorAll('video');
    var most = 0;
    for (var j = 0; j < videos.length; j++) {
      var v = videos[j];
      if (v.readyState < 2 || typeof v.webkitSetPresentationMode !== 'function') { continue; }
      if (!v.webkitSupportsPresentationMode('picture-in-picture')) { continue; }
      var box = v.getBoundingClientRect();
      most = Math.max(most, box.width * box.height + (v.paused ? 0 : 1e9));
    }
    return most;
    """

    /// Floats the frame's best video, by the same weighing.
    private static let floatScript = """
    var videos = document.querySelectorAll('video');
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
    """

    private static let enterScript = """
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.paused || v.muted || v.volume === 0) { continue; }
      if (v.videoWidth < 320 || v.readyState < 2) { continue; }
      if (typeof v.webkitSetPresentationMode !== 'function') { continue; }
      if (!v.webkitSupportsPresentationMode('picture-in-picture')) { continue; }
      if (v.webkitPresentationMode === 'picture-in-picture') { return 'picture-in-picture'; }
      v.webkitSetPresentationMode('picture-in-picture');
      return 'picture-in-picture';
    }
    return 'none';
    """
}
