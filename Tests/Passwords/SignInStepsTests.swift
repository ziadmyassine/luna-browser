//
//  SignInStepsTests.swift
//  LunaTests
//
//  The sign-ins that ask for the name on one page and the password on the
//  next (Microsoft, Google, Apple), and the rule that only a sign-in that took
//  is offered for saving.
//
//  The first half runs the page script in a bare `WKWebView`, the way
//  `FormDetectionTests` does. The second half runs a real `TabController`, so
//  the script, the relay and `PasswordCoordinator` are tested as the page
//  meets them.
//

import WebKit
import XCTest
@testable import BrowserKit
@testable import Luna

@MainActor
final class SignInStepsTests: XCTestCase {

    // MARK: - The page script

    private final class Sink: NSObject, WKScriptMessageHandler {
        var events: [PasswordForms.Event] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let event = PasswordForms.event(from: message.body) { events.append(event) }
        }
    }

    private func load(_ html: String) -> (WKWebView, Sink) {
        let sink = Sink()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(sink, name: PasswordForms.messageName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: PasswordForms.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 900), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: "https://login.fixtures.example.com/"))
        return (webView, sink)
    }

    private func wait(
        _ sink: Sink,
        timeout: TimeInterval = 5,
        for predicate: @escaping (PasswordForms.Event) -> Bool
    ) async -> PasswordForms.Event? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = sink.events.first(where: predicate) { return match }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func loaded(_ sink: Sink) async -> Bool? {
        let event = await wait(sink) { if case .pageLoaded = $0 { return true } else { return false } }
        if case let .pageLoaded(has)? = event { return has }
        return nil
    }

    private func focused(_ sink: Sink, timeout: TimeInterval = 5) async -> PasswordForms.Form? {
        let event = await wait(sink, timeout: timeout) { if case .fieldFocused = $0 { return true } else { return false } }
        if case let .fieldFocused(form)? = event { return form }
        return nil
    }

    /// Microsoft's first page: a name box the page marks as a username, and
    /// no password box until the next step.
    func testANameOnlyStepIsASignInField() async throws {
        let (webView, sink) = load("""
        <form><input type="email" name="loginfmt" autocomplete="username"><button type="button">Next</button></form>
        """)
        let hasPassword = await loaded(sink)
        XCTAssertEqual(hasPassword, false, "the page has no password box yet")
        _ = try await webView.evaluateJavaScript("document.querySelector('input').focus(); 1")
        let form = await focused(sink)
        XCTAssertEqual(form?.isUsernameOnly, true, "the name box raised no offer")
        XCTAssertEqual(form?.isPasswordField, false)
    }

    /// A bare email box is every newsletter on the web; it is not a sign-in.
    func testABareEmailBoxIsNotASignIn() async throws {
        let (webView, sink) = load("""
        <form><input type="email" name="email" placeholder="Your email"><button>Subscribe</button></form>
        """)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("document.querySelector('input').focus(); 1")
        let form = await focused(sink, timeout: 1)
        XCTAssertNil(form, "a newsletter box raised the picker")
    }

    /// A page that puts the caret in its name box itself, before Luna's script
    /// ran, still gets the picker — the shape of Microsoft's and Google's.
    func testAnAutofocusedNameBoxIsOffered() async {
        let (webView, sink) = load("""
        <input type="email" id="identifierId" autocomplete="username webauthn" autofocus>
        """)
        let form = await focused(sink)
        XCTAssertEqual(form?.isUsernameOnly, true, "an autofocused name box raised nothing")
        withExtendedLifetime(webView) {}
    }

    /// Enter in the name box sends the name step, which a page handling the
    /// key itself never reports through `submit`.
    func testEnterInTheNameBoxSendsTheName() async throws {
        let (webView, sink) = load("""
        <input type="email" name="loginfmt" autocomplete="username" value="ada@example.com">
        """)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("""
        (function () {
          var box = document.querySelector('input');
          box.focus();
          box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
          return 1;
        })()
        """)
        let event = await wait(sink) { if case .identified = $0 { return true } else { return false } }
        guard case let .identified(username)? = event else { return XCTFail("the name step was not reported") }
        XCTAssertEqual(username, "ada@example.com")
    }

    /// Microsoft's shape: the page fades its form in, so the name box is
    /// still transparent when it takes focus, and handles Return itself. The
    /// name has to be caught from the typing and the key, not the focus.
    func testANameTypedIntoAFadingBoxIsStillSent() async throws {
        let (webView, sink) = load("""
        <form><input type="email" name="loginfmt" autocomplete="username webauthn" style="opacity:0"></form>
        """)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("""
        (function () {
          var box = document.querySelector('input');
          box.focus();
          box.style.opacity = '1';
          box.value = 'ada@example.com';
          box.dispatchEvent(new Event('input', { bubbles: true }));
          box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
          return 1;
        })()
        """)
        let event = await wait(sink) { if case .identified = $0 { return true } else { return false } }
        guard case let .identified(username)? = event else { return XCTFail("the name step was not reported") }
        XCTAssertEqual(username, "ada@example.com")
    }

    /// Microsoft's password step shows the name as text and keeps it in a box
    /// moved off screen, marked as the username for password managers.
    func testThePasswordStepReadsTheNameKeptOffScreen() async throws {
        let (webView, sink) = load("""
        <form onsubmit="return false">
        <input type="email" name="loginfmt" autocomplete="username" value="grace@example.com"
          style="position:absolute; left:-10000px; opacity:0">
        <div>grace@example.com</div>
        <input type="password" name="passwd"><button type="button">Sign in</button></form>
        """)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("""
        (function () {
          document.querySelector('input[type=password]').value = 'hunter2';
          document.querySelector('button').click();
          return 1;
        })()
        """)
        let event = await wait(sink) { if case .submitted = $0 { return true } else { return false } }
        guard case let .submitted(username, _)? = event else { return XCTFail("no submit reported") }
        XCTAssertEqual(username, "grace@example.com")
    }

    /// A sign-in done in place takes its form away; that is reported apart
    /// from the caret merely leaving it.
    func testAFormTakenAwayIsReportedAsGone() async throws {
        let (webView, sink) = load("""
        <form id="f"><input type="text" name="username"><input type="password" name="password"></form>
        """)
        let hasPassword = await loaded(sink)
        XCTAssertEqual(hasPassword, true)
        _ = try await webView.evaluateJavaScript("document.getElementById('f').remove(); 1")
        let event = await wait(sink) { if case .formGone = $0 { return true } else { return false } }
        XCTAssertNotNil(event, "the form left without a word")
    }

    // MARK: - Saving only what worked

    private final class Recorder: NSObject, TabControllerDelegate {
        var saves: [PasswordSaveRequest] = []
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController, wantsNewTabFor url: URL?, configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) {}
        func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest) {
            saves.append(request)
        }
    }

    /// A host no saved credential can be filed under, so the Keychain is
    /// asked and has nothing to compare.
    private let base = URL(string: "https://signin.luna-\(UUID().uuidString.prefix(8).lowercased()).example.com/")!

    private func tab() throws -> (TabController, Recorder, WKWebView) {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let recorder = Recorder()
        controller.delegate = recorder
        controller.activate()
        return (controller, recorder, try XCTUnwrap(controller.webView))
    }

    private func show(_ html: String, in webView: WKWebView) async throws {
        webView.loadHTMLString(html, baseURL: base)
        let deadline = Date().addingTimeInterval(5)
        while webView.isLoading || webView.url == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    private func signIn(_ webView: WKWebView, name: String?, password: String) async throws {
        _ = try await webView.evaluateJavaScript("""
        (function () {
          var name = document.querySelector('input[type=text], input[type=email]');
          if (name) { name.value = \(name.map { "'\($0)'" } ?? "''"); }
          document.querySelector('input[type=password]').value = '\(password)';
          document.querySelector('button').click();
          return 1;
        })()
        """)
        try await Task.sleep(for: .milliseconds(300))
    }

    private static let signInPage = """
    <form onsubmit="return false"><input type="text" name="username"><input type="password" name="password">
    <button type="button">Sign in</button></form>
    """

    private func settled(_ recorder: Recorder, within seconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while recorder.saves.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
    }

    /// The page moved on and has no password box: the sign-in took, and only
    /// now is the user asked.
    func testSavingIsOfferedOnceTheSignInTook() async throws {
        let (controller, recorder, webView) = try tab()
        try await show(Self.signInPage, in: webView)
        try await signIn(webView, name: "luna-test-ada", password: "correct horse")
        XCTAssertTrue(recorder.saves.isEmpty, "the chip came up before anyone knew the password worked")

        try await show("<p>Welcome back</p>", in: webView)
        try await settled(recorder, within: 4)
        XCTAssertEqual(recorder.saves.map(\.username), ["luna-test-ada"])
        withExtendedLifetime(controller) {}
    }

    /// The page came back with its password box: a refused password, which
    /// is not one to keep.
    func testARefusedSignInIsNotOffered() async throws {
        let (controller, recorder, webView) = try tab()
        try await show(Self.signInPage, in: webView)
        try await signIn(webView, name: "luna-test-ada", password: "wrong")
        try await show(Self.signInPage, in: webView)
        try await settled(recorder, within: 2.5)
        XCTAssertTrue(recorder.saves.isEmpty, "a refused password was offered for saving")
        withExtendedLifetime(controller) {}
    }

    /// The password step has no name box; the name sent on the step before is
    /// the one the password is saved under.
    func testTheNameStepNamesThePasswordStep() async throws {
        let (controller, recorder, webView) = try tab()
        try await show("""
        <input type="email" name="loginfmt" autocomplete="username"><button type="button">Next</button>
        """, in: webView)
        _ = try await webView.evaluateJavaScript("""
        (function () {
          var box = document.querySelector('input');
          box.focus();
          box.value = 'luna-test-grace@example.com';
          document.querySelector('button').click();
          return 1;
        })()
        """)
        try await Task.sleep(for: .milliseconds(300))

        try await show("""
        <p>luna-test-grace@example.com</p><input type="password" name="passwd"><button type="button">Sign in</button>
        """, in: webView)
        try await signIn(webView, name: nil, password: "battery staple")
        try await show("<p>Stay signed in?</p>", in: webView)
        try await settled(recorder, within: 4)
        XCTAssertEqual(recorder.saves.map(\.username), ["luna-test-grace@example.com"])
        withExtendedLifetime(controller) {}
    }
}

// MARK: - Where the picker lands, and the finger's go-ahead

extension SignInStepsTests {

    /// Microsoft's password step slides in from the side. The field is
    /// measured where it stops, not where it was when it took the focus.
    func testAFieldSlidingInIsMeasuredWhereItStops() async throws {
        let (webView, sink) = load("""
        <div id="step" style="position: relative; left: 300px">
          <form><input type="password" name="passwd" id="pw"><input type="submit" value="Sign in"></form>
        </div>
        """)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("""
        var step = document.getElementById('step'), left = 300;
        var slide = setInterval(function () {
          left = Math.max(0, left - 30);
          step.style.left = left + 'px';
          if (left === 0) { clearInterval(slide); }
        }, 20);
        document.getElementById('pw').focus(); 1
        """)
        let reported = await focused(sink)
        let form = try XCTUnwrap(reported)
        let stop = try await webView.evaluateJavaScript("document.getElementById('pw').getBoundingClientRect().left") as? Double
        XCTAssertEqual(form.fieldRect.minX, try XCTUnwrap(stop), accuracy: 0.5, "the picker was hung from the field mid-slide")
    }

    private func signedIn(_ html: String) async throws -> String? {
        let (webView, sink) = load(html)
        _ = await loaded(sink)
        _ = try await webView.evaluateJavaScript("document.querySelector('input').focus(); 1")
        let reported = await focused(sink)
        let form = try XCTUnwrap(reported)
        await PasswordForms.fill(form, username: "", password: "hunter2", in: webView, frame: nil, submit: true)
        try await Task.sleep(for: .milliseconds(300))
        return try await webView.evaluateJavaScript("document.title") as? String
    }

    /// A fill chosen with a finger presses the form's own button.
    func testAFingerFillPressesTheFormsButton() async throws {
        let title = try await signedIn("""
        <form onsubmit="event.preventDefault(); document.title = 'sent ' + this.passwd.value">
          <input type="password" name="passwd"><input type="submit" value="Sign in">
        </form>
        """)
        XCTAssertEqual(title, "sent hunter2")
    }

    /// Google's sign-in has no form, only a button that says Next.
    func testAFingerFillPressesNextWhereThereIsNoForm() async throws {
        let title = try await signedIn("""
        <div><input type="password" name="Passwd">
        <div role="button" onclick="document.title = 'next ' + document.querySelector('input').value">Next</div></div>
        """)
        XCTAssertEqual(title, "next hunter2")
    }
}
