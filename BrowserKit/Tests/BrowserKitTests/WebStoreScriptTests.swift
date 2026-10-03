import Foundation
import JavaScriptCore
import Testing
@testable import BrowserKit

/// The Chrome Web Store button-hijack script, run rather than read — the same
/// reason `MediaScriptTests` evaluates its script against a stand-in document.
///
/// What the script does cannot be recovered from a `contains` check: it finds a
/// button by what it says, relabels it, swallows its click, and speaks once per
/// document while the SPA re-renders it. So it is run in `JSContext` against the
/// small DOM it touches, and the button is replaced under it to prove the
/// re-render path.
@Suite("Web Store script")
@MainActor
struct WebStoreScriptTests {

    /// Enough of a document for the script: the handler it posts to, elements
    /// `querySelectorAll` hands back, and a `MutationObserver` whose callback the
    /// test fires by hand to stand in for the SPA re-rendering the button.
    private static let document = """
    var __posts = [];
    var __els = [];
    var __observer = null;
    var window = this;
    window.webkit = { messageHandlers: { lunaWebStore: {
      postMessage: function (message) { __posts.push(message); }
    } } };
    function __el(text, aria, disabled) {
      var attrs = {};
      if (aria) { attrs['aria-label'] = aria; }
      if (disabled) { attrs.disabled = ''; }
      return {
        _attrs: attrs,
        _text: text,
        // Counts writes, so a test can prove a no-op relabel does not touch the DOM
        // (the childList churn that looped the observer on installed pages).
        _writes: 0,
        get textContent() { return this._text; },
        set textContent(value) { this._text = value; this._writes++; },
        style: {},
        _click: null,
        getAttribute: function (name) { return this._attrs[name] != null ? this._attrs[name] : null; },
        setAttribute: function (name, value) { this._attrs[name] = value; },
        hasAttribute: function (name) { return this._attrs[name] != null; },
        removeAttribute: function (name) { delete this._attrs[name]; },
        addEventListener: function (type, fn) { if (type === 'click') { this._click = fn; } }
      };
    }
    var MutationObserver = function (callback) { this._cb = callback; __observer = this; };
    MutationObserver.prototype.observe = function () {};
    var document = {
      documentElement: {},
      querySelectorAll: function () { return __els; }
    };
    // Fires the button's click with an event that records what was swallowed.
    function __click(el) {
      var calls = { prevent: 0, stop: 0, stopImmediate: 0 };
      el._click({
        preventDefault: function () { calls.prevent++; },
        stopPropagation: function () { calls.stop++; },
        stopImmediatePropagation: function () { calls.stopImmediate++; }
      });
      return calls;
    }
    """

    /// A context with the stand-in document and the script run in it, `els` being
    /// the page's candidate buttons at that moment.
    private func context(els: String) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, value in
            Issue.record("JavaScript threw: \(value?.toString() ?? "?")")
        }
        context.evaluateScript(Self.document)
        context.evaluateScript("__els = \(els);")
        context.evaluateScript(TabController.webStoreScript)
        return context
    }

    private func posts(_ context: JSContext) throws -> [[String: Any]] {
        try #require(context.objectForKeyedSubscript("__posts")?.toArray() as? [[String: Any]])
    }

    private func kinds(_ context: JSContext) throws -> [String] {
        try posts(context).compactMap { $0["kind"] as? String }
    }

    @Test func relabelsTheButtonAndSaysItHandledItOnce() throws {
        let context = try context(els: "[__el('Add to Chrome')]")
        #expect(context.evaluateScript("__els[0].textContent")?.toString() == "Add to Luna")
        #expect(try kinds(context) == ["handled"])
    }

    @Test func aClickIsSwallowedAndAsksToAdd() throws {
        let context = try context(els: "[__el('Add to Chrome')]")
        let calls = try #require(context.evaluateScript("__click(__els[0])")?.toDictionary() as? [String: Int])
        #expect(calls == ["prevent": 1, "stop": 1, "stopImmediate": 1])
        #expect(try kinds(context) == ["handled", "add"])
    }

    /// Google greys the button out for an item its own install cannot add, which
    /// in WebKit is every item. A disabled button swallows the click our listener
    /// waits on, so the script clears the disabled state before binding.
    @Test func aDisabledButtonIsEnabledAndStillAdds() throws {
        let context = try context(els: "[__el('Add to Chrome', null, true)]")
        #expect(context.evaluateScript("__els[0].hasAttribute('disabled')")?.toBool() == false)
        let calls = try #require(context.evaluateScript("__click(__els[0])")?.toDictionary() as? [String: Int])
        #expect(calls == ["prevent": 1, "stop": 1, "stopImmediate": 1])
        #expect(try kinds(context) == ["handled", "add"])
    }

    /// Native reports the install went through: the button becomes "Added", and a
    /// further click no longer asks to add it again.
    @Test func saysAddedOnceInstalled() throws {
        let context = try context(els: "[__el('Add to Chrome')]")
        context.evaluateScript("window.__lunaStoreAdded();")
        #expect(context.evaluateScript("__els[0].textContent")?.toString() == "Added")
        // Greyed out and no longer a call to action.
        #expect(context.evaluateScript("__els[0].style.filter")?.toString() == "grayscale(1)")
        #expect(context.evaluateScript("__els[0].style.cursor")?.toString() == "default")
        context.evaluateScript("__click(__els[0]);")
        #expect(try kinds(context) == ["handled"])
    }

    /// With the button already "Added", a further pass must not rewrite its text:
    /// a no-op write is still a childList change, and under `added` that looped the
    /// MutationObserver and hung installed extensions' store pages.
    @Test func reApplyingAnAddedButtonTouchesNothing() throws {
        let context = try context(els: "[__el('Add to Chrome')]")
        context.evaluateScript("window.__lunaStoreAdded();")
        let before = context.evaluateScript("__els[0]._writes")?.toInt32()
        context.evaluateScript("__observer._cb();")
        #expect(context.evaluateScript("__els[0]._writes")?.toInt32() == before)
        #expect(context.evaluateScript("__els[0].textContent")?.toString() == "Added")
    }

    /// The store's "item unavailable" notice is false for Luna's own install, so
    /// the script hides it and the guide link beside it.
    @Test func hidesTheUnavailableNotice() throws {
        let context = try context(els: """
        [__el('Add to Chrome'), \
         __el('Item currently unavailable. Please check the troubleshooting guide.'), \
         __el('View guide')]
        """)
        #expect(context.evaluateScript("__els[1].style.display")?.toString() == "none")
        #expect(context.evaluateScript("__els[2].style.display")?.toString() == "none")
        // The button it is beside is left alone.
        #expect(context.evaluateScript("__els[0].style.display")?.toString() != "none")
    }

    /// The degrade path the toast fallback exists for: no button, nothing said.
    @Test func withoutTheButtonNothingIsPosted() throws {
        #expect(try posts(context(els: "[__el('Install uBlock Origin'), __el('Remove')]")).isEmpty)
    }

    /// The SPA swaps the button for a fresh node: it is relabelled again, but
    /// native is told only the once.
    @Test func reRenderRelabelsAgainButSaysHandledOnlyOnce() throws {
        let context = try context(els: "[__el('Add to Chrome')]")
        context.evaluateScript("__els = [__el('Add to Chrome')]; __observer._cb();")
        #expect(context.evaluateScript("__els[0].textContent")?.toString() == "Add to Luna")
        #expect(try kinds(context) == ["handled"])
    }
}

/// The message body parser behind `handleWebStoreMessage`. A `WKScriptMessage`
/// cannot be built in a unit test, so the parsing is kept pure and tested here;
/// the handler is a thin adapter over it that reads `webView.url`.
@Suite("Web Store signal")
@MainActor
struct WebStoreSignalTests {

    @Test func parsesTheTwoKinds() {
        #expect(TabController.webStoreSignal(from: ["kind": "handled"]) == .handled)
        #expect(TabController.webStoreSignal(from: ["kind": "add"]) == .add)
    }

    @Test func junkIsNothing() {
        #expect(TabController.webStoreSignal(from: ["kind": "install"]) == nil)
        #expect(TabController.webStoreSignal(from: ["url": "https://evil.example"]) == nil)
        #expect(TabController.webStoreSignal(from: [:]) == nil)
    }
}
