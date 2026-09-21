import Foundation
import JavaScriptCore
import Testing
@testable import BrowserKit

/// §3.2b's colour sample, run rather than read.
///
/// The rest of `scrollScript`'s coverage asserts that the source contains a
/// word. That catches a deleted listener and nothing else: both bugs Martin
/// reported — a white bar over a black page, and a bar still wearing the page
/// Back had just left — were in what the script decides, and every
/// `contains` test went on passing through both of them.
///
/// So the script is evaluated here in `JSContext` against a stand-in document,
/// which is all it touches: `elementsFromPoint`, `getComputedStyle`,
/// `addEventListener`, `requestAnimationFrame` and the message handler. The
/// stand-in hands every point the same stack, because what is being asserted is
/// the walk down one, not the agreement between three.
@Suite("Page colour script (§3.2b)")
@MainActor
struct PageColourScriptTests {

    /// One layer as `getComputedStyle` reports it. The stand-in is the style,
    /// so a layer is just the two properties the walk reads.
    struct Layer {
        let colour: String
        var image = "none"
    }

    /// Enough of a document for the script to run in, plus `__fire`, which
    /// delivers an event and then runs whatever frame it scheduled — the two
    /// halves of one turn, and the script coalesces them on purpose.
    private static let document = """
    var __posts = [];
    var __listeners = {};
    var __frame = null;
    var __stack = [];
    var window = this;
    window.innerWidth = 800;
    window.innerHeight = 600;
    window.scrollY = 0;
    window.addEventListener = function (name, fn) {
      (__listeners[name] = __listeners[name] || []).push(fn);
    };
    window.requestAnimationFrame = function (fn) { __frame = fn; };
    window.getComputedStyle = function (layer) { return layer; };
    window.webkit = { messageHandlers: { lunaScroll: {
      postMessage: function (message) { __posts.push(message); }
    } } };
    var document = {
      scrollingElement: { scrollTop: 0 },
      elementsFromPoint: function (x, y) { return __stack; }
    };
    function __fire(name) {
      var listeners = __listeners[name] || [];
      for (var i = 0; i < listeners.length; i++) { listeners[i](); }
      if (__frame) { var frame = __frame; __frame = null; frame(); }
    }
    function __lastTop() {
      var last = __posts[__posts.length - 1];
      return last ? last.top : null;
    }
    """

    /// A page with `layers` under every sample point, with the script loaded and
    /// its one post at document end already made.
    @MainActor
    private struct Page {
        let context = JSContext()!

        init(_ layers: [Layer]) {
            context.evaluateScript(PageColourScriptTests.document)
            paint(layers)
            context.evaluateScript(TabController.scrollScript)
        }

        func paint(_ layers: [Layer]) {
            let written = layers
                .map { "{ backgroundColor: '\($0.colour)', backgroundImage: '\($0.image)' }" }
                .joined(separator: ", ")
            context.evaluateScript("__stack = [\(written)];")
        }

        func fire(_ event: String) {
            context.evaluateScript("__fire('\(event)');")
        }

        var posts: Int {
            Int(context.evaluateScript("__posts.length")?.toInt32() ?? -1)
        }

        /// What the page last said was under the bar, in 0...255, or nil for the
        /// page saying it has no answer.
        var answer: [Int]? {
            guard let value = context.evaluateScript("__lastTop()"), !value.isNull, !value.isUndefined,
                  let parts = value.toArray() as? [Double]
            else { return nil }
            return parts.map { Int(($0 * 255).rounded()) }
        }
    }

    @Test func theFirstOpaqueLayerDownTheStackIsTheAnswer() {
        let page = Page([
            Layer(colour: "rgba(0, 0, 0, 0)"),
            Layer(colour: "rgb(12, 12, 13)"),
            Layer(colour: "rgb(255, 255, 255)")
        ])
        #expect(page.posts == 1)
        #expect(page.answer == [12, 12, 13])
    }

    /// The bug Martin reported as "it goes white": a section painted behind a
    /// gradient used to end the sample, and the bar fell to the document's own
    /// background. Measured on `getroosta.app` from roughly 6500 pt down, where
    /// `div.horizon` carries
    /// `linear-gradient(white 0, white 65%, #0c0c0d 65%, #0c0c0d 100%)`
    /// over `footer.night` at `12,12,13` — and the screen really is `13,13,14`
    /// under the bar there, so white was not a near miss.
    @Test func aSectionPaintedBehindAGradientIsStillTheAnswer() {
        let page = Page([
            Layer(colour: "rgba(0, 0, 0, 0)"),
            Layer(
                colour: "rgba(0, 0, 0, 0)",
                image: "linear-gradient(rgb(255, 255, 255) 0px, rgb(12, 12, 13) 100%)"
            ),
            Layer(colour: "rgb(12, 12, 13)"),
            Layer(colour: "rgb(255, 255, 255)")
        ])
        #expect(page.answer == [12, 12, 13])
    }

    /// Skipping the image is not the same as reading through it. A photo with
    /// nothing but the document behind it still answers the document — which is
    /// exactly what ending the sample there answered, so nothing regressed for
    /// the case the old rule was written for.
    @Test func anImageOverNothingButTheDocumentStillAnswersTheDocument() {
        let page = Page([
            Layer(colour: "rgba(0, 0, 0, 0)", image: "url(\"https://example.com/hero.jpg\")"),
            Layer(colour: "rgb(255, 255, 255)")
        ])
        #expect(page.answer == [255, 255, 255])
    }

    /// A layer that is only mostly opaque is not the top edge's colour, so the
    /// walk goes past it — the transparent-sticky-header case the walk exists
    /// for.
    @Test func aTranslucentLayerIsNotAnAnswer() {
        let page = Page([
            Layer(colour: "rgba(255, 255, 255, 0.8)"),
            Layer(colour: "rgb(12, 12, 13)")
        ])
        #expect(page.answer == [12, 12, 13])
    }

    @Test func nothingOpaqueAnywhereInTheStackIsNoAnswerAtAll() {
        let page = Page([
            Layer(colour: "rgba(0, 0, 0, 0)"),
            Layer(colour: "rgba(0, 0, 0, 0)", image: "linear-gradient(red, blue)")
        ])
        #expect(page.answer == nil)
    }

    /// The other bug: Back and Forward are served from WebKit's page cache,
    /// which restores a document without re-running user scripts. Nothing
    /// posted, `resetPerDocumentState` had already cleared the colour, and the
    /// bar wore the page that had just been left until the next scroll. The
    /// listeners survive the restore, so `pageshow` is what asks again.
    @Test func aPageComingBackOutOfTheCacheSaysWhatItIsPaintedOn() {
        let page = Page([Layer(colour: "rgb(255, 255, 255)")])
        #expect(page.answer == [255, 255, 255])
        page.paint([Layer(colour: "rgb(10, 10, 20)")])
        page.fire("pageshow")
        #expect(page.posts == 2, "a restored page never said anything, so the bar kept the last page's colour")
        #expect(page.answer == [10, 10, 20])
    }

    /// The cache is per 4 pt of travel, and a restore does not move the page —
    /// so `pageshow` has to drop it, or the answer for the document that just
    /// went away is handed to the one that replaced it.
    @Test func theRestoreDropsTheSampleCacheRatherThanReusingIt() {
        let page = Page([Layer(colour: "rgb(255, 255, 255)")])
        page.paint([Layer(colour: "rgb(10, 10, 20)")])
        page.fire("pageshow")
        #expect(page.answer == [10, 10, 20], "the sample was still cached against the same scroll offset")
    }
}
