import Foundation
import JavaScriptCore
import Testing
import WebKit
@testable import BrowserKit

/// What Luna injects into every frame of every page, and what it costs to.
///
/// `mediaScript`, `ContentBlocker.blockedCountScript` and §14's form detection
/// are all `forMainFrameOnly: false`, because the things they watch live in
/// subframes. WebKit compiles and evaluates each `WKUserScript` separately in
/// each frame, so three of them on a news page with thirty ad frames is ninety
/// injections — measured at 0.37 ms per extra frame for the three together
/// (`docs/PERF.md`). They go in as one now, and these are the assertions that
/// keep the merge honest: the count, the contents, and the isolation that
/// WebKit used to provide by holding them apart.
@Suite("Per-frame user scripts")
@MainActor
struct UserScriptsTests {

    // MARK: - One script, with everything still in it

    @Test func theDocumentEndScriptsGoInAsOne() {
        let script = TabController.documentEndScript()
        #expect(script.injectionTime == .atDocumentEnd)
        // The whole point: a subframe is where the sound, the blocked request
        // and very often the sign-in form are.
        #expect(script.isForMainFrameOnly == false)
    }

    @Test func mergingLosesNoneOfTheThree() {
        PasswordSettings.isEnabled = true
        defer { PasswordSettings.isEnabled = true }
        let source = TabController.documentEndScript().source
        #expect(source.contains(TabController.mediaScript))
        #expect(source.contains(ContentBlocker.blockedCountScript))
        #expect(source.contains(PasswordForms.script))
    }

    /// §14 off still means not injected, not injected-and-ignored — a user who
    /// declines autofill does not pay a MutationObserver on every frame for it.
    @Test func formDetectionStaysOutWhenItIsTurnedOff() {
        PasswordSettings.isEnabled = false
        defer { PasswordSettings.isEnabled = true }
        let source = TabController.documentEndScript().source
        #expect(!source.contains(PasswordForms.script))
        #expect(source.contains(TabController.mediaScript))
    }

    // MARK: - The isolation the merge had to put back

    /// This is the risk the merge introduces and the reason for the
    /// `try`/`catch`. Three separate `WKUserScript`s fail separately: one
    /// throwing leaves the other two installed. One script does not — without
    /// this, a throw in the first would silently cost the page its blocked
    /// count and its autofill.
    @Test func oneScriptThrowingDoesNotTakeTheOthersWithIt() throws {
        let context = try #require(JSContext())
        var escaped: String?
        context.exceptionHandler = { _, value in escaped = value?.toString() }
        context.evaluateScript("var __ran = [];")
        context.evaluateScript(TabController.isolated([
            "__ran.push('first');",
            "throw new Error('boom');",
            "__ran.push('third');"
        ]))
        #expect(context.objectForKeyedSubscript("__ran")?.toArray() as? [String] == ["first", "third"])
        // Caught, not merely survived: an exception reaching the handler would
        // mean WebKit had seen it too.
        #expect(escaped == nil)
    }

    /// Each source keeps its own scope, as it had when WebKit held them apart.
    /// Every one of Luna's is an IIFE; joining them must not make that a
    /// promise rather than a fact.
    @Test func theJoinedSourcesShareNoScope() throws {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, value in
            Issue.record("JavaScript threw: \(value?.toString() ?? "?")")
        }
        context.evaluateScript("var __seen = null;")
        context.evaluateScript(TabController.isolated([
            "(function () { var mine = 'first'; })();",
            "(function () { __seen = (typeof mine); })();"
        ]))
        #expect(context.objectForKeyedSubscript("__seen")?.toString() == "undefined")
    }
}
