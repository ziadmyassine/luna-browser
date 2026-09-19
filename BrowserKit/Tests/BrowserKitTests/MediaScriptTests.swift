import Foundation
import JavaScriptCore
import Testing
@testable import BrowserKit

/// §3.4a's speaker badge, **run** rather than read — the same reason
/// `PageColourScriptTests` evaluates `scrollScript` instead of grepping it.
///
/// What is asserted here is mostly a *count*, because that is what the script
/// was changed to fix and a count has no noise in it. `mediaScript` is injected
/// into every frame on the page (`forMainFrameOnly: false`, because an embedded
/// player lives in a subframe), so a page with ten ad iframes used to send
/// eleven messages across the process boundary before it had finished loading —
/// eleven `handleMediaMessage` calls and eleven `publishState`s, every one of
/// them to say that silence is still silent.
@Suite("Media script (§3.4a)")
@MainActor
struct MediaScriptTests {

    /// Enough of a document for the script to run in: the handler it posts to,
    /// the capture-phase listeners it registers, and a `querySelectorAll` that
    /// answers with whatever media the test put in the page.
    private static let document = """
    var __posts = [];
    var __listeners = {};
    var __media = [];
    var window = this;
    window.webkit = { messageHandlers: { lunaMedia: {
      postMessage: function (message) { __posts.push(message); }
    } } };
    var document = {
      addEventListener: function (name, fn) { (__listeners[name] = __listeners[name] || []).push(fn); },
      querySelectorAll: function () { return __media; }
    };
    function __fire(name) {
      var listeners = __listeners[name] || [];
      for (var i = 0; i < listeners.length; i++) { listeners[i](); }
    }
    function __playing(paused, muted, volume) {
      return { paused: paused, muted: muted, volume: volume };
    }
    """

    /// A context with the stand-in document and `script` already run in it,
    /// with `media` as the frame's `<video>`/`<audio>` elements at that moment.
    private func context(media: String = "[]", running script: String? = nil) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, value in
            Issue.record("JavaScript threw: \(value?.toString() ?? "?")")
        }
        context.evaluateScript(Self.document)
        context.evaluateScript("__media = \(media);")
        context.evaluateScript(script ?? TabController.mediaScript)
        return context
    }

    private func posts(_ context: JSContext) throws -> [[String: Any]] {
        try #require(context.objectForKeyedSubscript("__posts")?.toArray() as? [[String: Any]])
    }

    // MARK: - The count

    /// **The one that matters for every page load.** A frame with no media in it
    /// has nothing to report, and `false` is what the tab already is: nothing
    /// reaches `audibleFrames` until something says otherwise, and
    /// `resetPerDocumentState` empties it on every navigation.
    @Test func aSilentFrameSaysNothingAtDocumentEnd() throws {
        #expect(try posts(context()).isEmpty)
    }

    /// A frame that is already making noise when the script arrives — autoplay,
    /// and the reason the opening call is still there at all.
    @Test func aFrameAlreadyPlayingReportsItselfImmediately() throws {
        let context = try context(media: "[__playing(false, false, 1)]")
        let reported = try posts(context)
        #expect(reported.count == 1)
        #expect(reported.first?["audible"] as? Bool == true)
    }

    /// `volumechange` fires on every tick of a volume drag, and all but the one
    /// that crosses zero say what the last one did.
    @Test func repeatedEventsWithTheSameAnswerAreNotSentAgain() throws {
        let context = try context(media: "[__playing(false, false, 1)]")
        for _ in 0 ..< 20 { context.evaluateScript("__fire('volumechange');") }
        #expect(try posts(context).count == 1)
    }

    /// The latch must not swallow the news, only the repetition: going quiet is
    /// a change, and so is starting again.
    @Test func everyChangeOfAnswerIsSent() throws {
        let context = try context(media: "[__playing(false, false, 1)]")
        context.evaluateScript("__media = [__playing(true, false, 1)]; __fire('pause');")
        context.evaluateScript("__fire('pause');")
        context.evaluateScript("__media = [__playing(false, false, 1)]; __fire('play');")
        let reported = try posts(context).compactMap { $0["audible"] as? Bool }
        #expect(reported == [true, false, true])
    }

    /// Muted autoplay is the case `requestMediaPlaybackState()` gets wrong and
    /// the reason this script exists; a silent video must stay silent here too.
    @Test func mutedAndSilentMediaAreNotAudible() throws {
        #expect(try posts(context(media: "[__playing(false, true, 1)]")).isEmpty)
        #expect(try posts(context(media: "[__playing(false, false, 0)]")).isEmpty)
    }

    // MARK: - Still true once it is not injected on its own

    /// The three per-frame scripts go into a frame as **one** `WKUserScript`
    /// (`UserScriptsTests`), which means this one now runs with the other two
    /// either side of it. So the behaviour above is asserted again against the
    /// source that actually ships — the merged one, with the real blocked-count
    /// and form-detection sources in it, not a copy of this script alone.
    @Test func theMergedScriptBehavesAsThisOneDid() throws {
        let merged = TabController.documentEndScript().source
        #expect(try posts(context(running: merged)).isEmpty)

        let playing = try context(media: "[__playing(false, false, 1)]", running: merged)
        #expect(try posts(playing).count == 1)
        for _ in 0 ..< 20 { playing.evaluateScript("__fire('volumechange');") }
        #expect(try posts(playing).count == 1)
    }
}
