//
//  FormDetectionTests.swift
//  LunaTests
//
//  §14.3's detection script, run in a **real `WKWebView`** against real form
//  markup — not asserted against as a string.
//
//  The script is the part of §14 with the most heuristics and the least type
//  checking, and both bugs found during its bring-up were invisible to every
//  other kind of test:
//
//  · a page holding a login form *and* any second password field anywhere
//    reported the login form as a signup, so Luna offered to generate a new
//    password instead of filling the saved one;
//  · a form submitted without having been scanned — the ordinary SPA shape,
//    where the button is a `<button type="button">` with a handler — reported
//    an empty username, which saves a credential the user cannot identify and
//    that will not match next time.
//
//  Neither is reachable from a unit test of the Swift side, and neither would
//  have been caught by reading the script. They are both pinned below.
//

import WebKit
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class FormDetectionTests: XCTestCase {

    // MARK: - Harness

    /// Collects what the page posts, exactly as `ScriptMessageRelay` would.
    private final class Sink: NSObject, WKScriptMessageHandler {
        var events: [PasswordForms.Event] = []
        var onEvent: (() -> Void)?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let event = PasswordForms.event(from: message.body) {
                events.append(event)
                onEvent?()
            }
        }
    }

    /// Loads `html` with the production script installed the way
    /// `TabController.attach` installs it, and returns the web view and sink.
    ///
    /// The web view is returned so the caller can keep it alive: a `WKWebView`
    /// that goes out of scope takes its WebContent process with it, and the
    /// test then waits forever for a message from a dead process.
    private func load(_ html: String) async -> (WKWebView, Sink) {
        let sink = Sink()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(sink, name: PasswordForms.messageName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: PasswordForms.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1200), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: "https://fixtures.example.com/login"))
        return (webView, sink)
    }

    /// Waits for the first event satisfying `predicate`, or fails.
    private func wait(
        _ sink: Sink,
        for predicate: @escaping (PasswordForms.Event) -> Bool,
        timeout: TimeInterval = 5
    ) async -> PasswordForms.Event? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = sink.events.first(where: predicate) { return match }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func firstForm(_ sink: Sink) async -> PasswordForms.Form? {
        let event = await wait(sink) { if case .formDetected = $0 { return true } else { return false } }
        if case let .formDetected(form)? = event { return form }
        return nil
    }

    // MARK: - Detection

    func testFindsAPlainLoginFormAndItsFields() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="username"><input type="password" name="password">
        <button type="submit">Sign in</button></form>
        """)
        let form = await firstForm(sink)
        XCTAssertNotNil(form, "a plain login form must be detected")
        XCTAssertFalse(form?.isSignup ?? true)
        XCTAssertFalse(form?.fieldRect.isEmpty ?? true, "the popover has nothing to anchor to")

        let tagged = try await webView.evaluateJavaScript("""
        (function () {
          var f = document.querySelector('[data-luna-form]');
          var u = f.querySelector('[data-luna-field="username"]');
          var p = f.querySelector('[data-luna-field="password"]');
          return (u ? u.name : 'none') + '/' + (p ? p.name : 'none');
        })()
        """) as? String
        XCTAssertEqual(tagged, "username/password")
    }

    /// The username field is found by **position** as well as by keyword: a
    /// great many sites call it something no keyword list would catch.
    func testFindsAnOpaquelyNamedUsernameField() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="login[identity]"><input type="password" name="login[secret]"></form>
        """)
        let detected = await firstForm(sink)
        XCTAssertNotNil(detected)
        let tagged = try await webView.evaluateJavaScript(
            "document.querySelector('[data-luna-field=\"username\"]').name"
        ) as? String
        XCTAssertEqual(tagged, "login[identity]")
    }

    func testTwoPasswordFieldsInOneFormIsASignup() async throws {
        let (webView, sink) = await load("""
        <form><input type="email" name="email">
        <input type="password" autocomplete="new-password" passwordrules="minlength: 12; required: upper;">
        <input type="password" name="confirm"></form>
        """)
        let form = await firstForm(sink)
        XCTAssertEqual(form?.isSignup, true)
        XCTAssertEqual(form?.passwordRules, "minlength: 12; required: upper;")
        withExtendedLifetime(webView) {}
    }

    /// **Regression.** `isSignup` was computed from every password field in the
    /// *document* rather than in the form, so a page carrying a login form and
    /// any second password field — a change-password widget, a hidden modal —
    /// made the login form look like a signup. Luna then offered to generate a
    /// password on a page the user was trying to sign in to.
    func testASecondFormElsewhereDoesNotMakeALoginLookLikeASignup() async throws {
        let (webView, sink) = await load("""
        <form id="login"><input type="text" name="u"><input type="password" name="p"></form>
        <form id="change"><input type="password" name="old"><input type="password" name="new"></form>
        """)
        let form = await firstForm(sink)
        XCTAssertNotNil(form)
        XCTAssertEqual(form?.isSignup, false, "the login form is not a signup just because the page has another")
        withExtendedLifetime(webView) {}
    }

    func testAnInvisiblePasswordFieldIsNotAForm() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="u"><input type="password" name="p" style="display:none"></form>
        """)
        let detected = await wait(sink, for: { if case .formDetected = $0 { return true } else { return false } },
                                  timeout: 1.5)
        XCTAssertNil(detected, "a hidden password field must not raise an offer")
        withExtendedLifetime(webView) {}
    }

    func testAFormWithNoPasswordIsNotAForm() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="q"><button type="submit">Search</button></form>
        """)
        let detected = await wait(sink, for: { if case .formDetected = $0 { return true } else { return false } },
                                  timeout: 1.5)
        XCTAssertNil(detected, "a search box must not raise an offer")
        withExtendedLifetime(webView) {}
    }

    func testReportsAOneTimeCodeField() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="u"><input type="password" name="p">
        <input type="text" autocomplete="one-time-code" name="code"></form>
        """)
        let form = await firstForm(sink)
        XCTAssertEqual(form?.hasOneTimeCode, true)
        withExtendedLifetime(webView) {}
    }

    // MARK: - §14.4's submit triggers

    func testReportsAFormSubmit() async throws {
        let (webView, sink) = await load("""
        <form onsubmit="return false"><input type="text" name="u" value="ada">
        <input type="password" name="p" value="hunter2"><button type="submit" id="go">In</button></form>
        """)
        _ = await firstForm(sink)
        _ = try? await webView.evaluateJavaScript("document.getElementById('go').click()")

        let event = await wait(sink) { if case .submitted = $0 { return true } else { return false } }
        guard case let .submitted(username, password)? = event else {
            return XCTFail("no submit reported")
        }
        XCTAssertEqual(username, "ada")
        XCTAssertEqual(password, "hunter2")
    }

    /// **Regression.** Most real logins never fire `submit` — the button is a
    /// `<button type="button">` whose handler calls `fetch`. The password had a
    /// fallback lookup for the unscanned case and the username did not, so this
    /// shape reported an empty username and saved an unidentifiable credential.
    func testReportsASPAButtonLoginWithItsUsername() async throws {
        let (webView, sink) = await load("""
        <form id="first"><input type="text" name="a"><input type="password" name="b"></form>
        <form id="spa"><input type="text" name="user" value="grace">
        <input type="password" name="pw" value="battery-staple">
        <button type="button" id="go">Log in</button></form>
        """)
        _ = await firstForm(sink)
        // The second form is deliberately never focused, so it is never
        // scanned and carries no `data-luna-field` tags.
        _ = try? await webView.evaluateJavaScript("document.getElementById('go').click()")

        let event = await wait(sink) { if case .submitted = $0 { return true } else { return false } }
        guard case let .submitted(username, password)? = event else {
            return XCTFail("no submit reported for the button-with-a-handler shape")
        }
        XCTAssertEqual(password, "battery-staple")
        XCTAssertEqual(username, "grace", "an unscanned form must still find its username")
    }

    // MARK: - §14.3's fill

    /// The fill has to survive a framework that has replaced the element's own
    /// `value` setter — React does exactly this, and a plain assignment is
    /// swallowed — and it has to leave the page's listeners believing a human
    /// typed. The password here carries a quote, an apostrophe, a backtick and
    /// a backslash: the characters that would break any interpolated script.
    func testFillDrivesAControlledInputAndFiresEvents() async throws {
        let (webView, sink) = await load("""
        <form><input type="text" name="u"><input type="password" name="p"></form>
        <script>
          window.seen = [];
          document.querySelectorAll('input').forEach(function (el) {
            ['input', 'change'].forEach(function (n) {
              el.addEventListener(n, function () { window.seen.push(el.name + ':' + n); });
            });
            var native = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
            Object.defineProperty(el, 'value', {
              get: native.get, configurable: true,
              set: function () { window.seen.push(el.name + ':swallowed'); }
            });
          });
        </script>
        """)
        guard let form = await firstForm(sink) else { return XCTFail("no form to fill") }

        let secret = #"p@ss"w'or`d\ness"#
        await PasswordForms.fill(form, username: "ada@example.com", password: secret, in: webView, frame: nil)

        let values = try await webView.evaluateJavaScript("""
        JSON.stringify({
          u: document.querySelector('[data-luna-field="username"]').value,
          p: document.querySelector('[data-luna-field="password"]').value,
          seen: window.seen
        })
        """) as? String
        let decoded = try XCTUnwrap(values)
        XCTAssertTrue(decoded.contains("ada@example.com"))
        XCTAssertTrue(decoded.contains(#"p@ss\"w'or`d\\ness"#), "the password did not survive the round trip: \(decoded)")
        XCTAssertTrue(decoded.contains("u:input"), "frameworks need an input event: \(decoded)")
        XCTAssertTrue(decoded.contains("p:change"), "frameworks need a change event: \(decoded)")
        XCTAssertFalse(decoded.contains("swallowed"), "the fill went through the patched setter: \(decoded)")
    }

    // MARK: - §14.10

    /// What a *website's* script sees, which is the page world — not the
    /// client world Luna's own `callAsyncJavaScript` runs in.
    func testPasskeyInterfaceIsHiddenFromThePage() async throws {
        guard !PasskeySupport.isAvailable else {
            throw XCTSkip("this build carries the entitlement, so nothing is suppressed")
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            try XCTUnwrap(PasskeySupport.userScript())
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<!doctype html><title>t</title>", baseURL: URL(string: "https://fixtures.example.com/"))
        try? await Task.sleep(for: .milliseconds(600))

        let probe = """
        var out = { present: typeof window.PublicKeyCredential !== 'undefined' };
        try {
          await navigator.credentials.get({ publicKey: { challenge: new Uint8Array(1) } });
          out.get = 'resolved';
        } catch (e) { out.get = e.name; }
        return JSON.stringify(out);
        """
        let result = try await webView.callAsyncJavaScript(
            probe, arguments: [:], in: nil, contentWorld: .page
        ) as? String
        let decoded = try XCTUnwrap(result)
        XCTAssertTrue(decoded.contains("\"present\":false"), "feature detection still succeeds: \(decoded)")
        XCTAssertTrue(decoded.contains("NotSupportedError"), "a direct call must fail definitely, not hang: \(decoded)")
    }
}
