import Foundation
import LunaControl
import Testing
import WebKit

/// The page scripts run in a real, windowless web view: the tree's shape, refs
/// that hold across reads, and the actions landing on the elements they name.
@Suite("Luna Control page scripts", .serialized)
@MainActor
struct ControlScriptsTests {

    private static let page = """
    <html><head><title>Form</title></head><body>
    <h1>Sign in</h1>
    <p>Welcome back to the example.</p>
    <form id="f" onsubmit="event.preventDefault(); document.title = 'sent ' + this.email.value">
      <label for="email">Email</label><input id="email" name="email" type="email">
      <input type="password" value="hunter2" aria-label="Password">
      <select id="plan" aria-label="Plan"><option value="a">Basic</option><option value="b">Pro</option></select>
      <input type="checkbox" id="keep" aria-label="Keep me signed in">
      <button type="submit">Continue</button>
    </form>
    <a href="/help">Help</a>
    <div style="display:none"><button>Hidden</button></div>
    </body></html>
    """

    private let world = WKContentWorld.world(name: "luna-control-tests")

    private func loaded(_ page: String = page) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(page, baseURL: URL(string: "https://example.com/"))
        for _ in 0 ..< 100 where webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        return webView
    }

    private func run(_ webView: WKWebView, _ operation: String, _ args: [String: Any]) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.call(operation), arguments: ["args": args], in: nil, contentWorld: world
        )
        return value as? String ?? ""
    }

    @Test func readPageIsAnIndentedTreeWithRefsOnControls() async throws {
        let webView = try await loaded()
        let tree = try await run(webView, "readPage", ["interactiveOnly": false, "maxDepth": 30])
        #expect(tree.hasPrefix("URL: https://example.com/\nTitle: Form\nViewport: 800x600"))
        #expect(tree.contains("heading \"Sign in\" level=1"))
        #expect(tree.contains("paragraph \"Welcome back to the example.\""))
        #expect(tree.contains("  textbox \"Email\" [e"))
        #expect(tree.contains("combobox \"Plan\" [e"))
        #expect(tree.contains("option \"Pro\""))
        #expect(tree.contains("link \"Help\" [e") && tree.contains("href=\"/help\""))
        // A password's value never leaves the page, and hidden things are not listed.
        #expect(!tree.contains("hunter2"))
        #expect(!tree.contains("Hidden"))

        // The same element keeps its ref on the next read.
        let again = try await run(webView, "readPage", ["interactiveOnly": true, "maxDepth": 30])
        let emailRef = Self.ref(in: tree, for: "textbox \"Email\"")
        #expect(emailRef != nil && again.contains("textbox \"Email\" [\(emailRef ?? "")]"))
        #expect(!again.contains("paragraph"))
    }

    @Test func actionsLandOnTheElementsTheyName() async throws {
        let webView = try await loaded()
        let found = try await run(webView, "find", ["query": "email"])
        let email = try #require(Self.ref(in: found, for: "textbox \"Email\""))
        _ = try await run(webView, "type", ["text": "a@b.co", "ref": email])
        let plan = try #require(Self.ref(in: try await run(webView, "find", ["query": "plan"]), for: "combobox"))
        _ = try await run(webView, "fill", ["ref": plan, "value": "Pro"])
        let keep = try #require(Self.ref(in: try await run(webView, "find", ["query": "keep"]), for: "checkbox"))
        _ = try await run(webView, "fill", ["ref": keep, "value": true])

        let state = try await webView.evaluateJavaScript(
            "[email.value, plan.value, keep.checked].join(',')"
        ) as? String
        #expect(state == "a@b.co,b,true")

        let button = try #require(Self.ref(in: try await run(webView, "find", ["query": "continue"]), for: "button"))
        let clicked = try await run(webView, "click", ["ref": button, "clickCount": 1])
        #expect(clicked.hasPrefix("Clicked button \"Continue\""))
        #expect(try await webView.evaluateJavaScript("document.title") as? String == "sent a@b.co")

        let stale = await #expect(throws: (any Error).self) {
            _ = try await self.run(webView, "click", ["ref": "e999", "clickCount": 1])
        }
        #expect(stale != nil)
    }

    @Test func enterSubmitsTheFormItIsIn() async throws {
        let webView = try await loaded()
        let email = try #require(Self.ref(in: try await run(webView, "find", ["query": "email"]), for: "textbox"))
        _ = try await run(webView, "type", ["text": "x@y.z", "ref": email])
        _ = try await run(webView, "key", ["keys": "Enter"])
        #expect(try await webView.evaluateJavaScript("document.title") as? String == "sent x@y.z")
    }

    @Test func javascriptReturnsTheLastExpressionAsJSON() async throws {
        let webView = try await loaded()
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.javascript, arguments: ["args": ["code": "const n = 2; ({ n, title: document.title })"]],
            in: nil, contentWorld: .page
        )
        #expect((value as? String)?.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            == "{\"n\":2,\"title\":\"Form\"}")
    }

    @Test func consoleIsRecordedFromTheFirstTouch() async throws {
        let webView = try await loaded()
        _ = try await webView.callAsyncJavaScript(ControlScripts.consoleInstall, arguments: [:], in: nil, contentWorld: .page)
        _ = try await webView.evaluateJavaScript("console.log('hello', {a: 1}); console.error('boom'); 0")
        let all = try await webView.callAsyncJavaScript(
            ControlScripts.consoleRead, arguments: ["args": ["onlyErrors": false, "clear": false]],
            in: nil, contentWorld: .page
        ) as? String
        #expect(all == "[log] hello {\"a\":1}\n[error] boom")
        let errors = try await webView.callAsyncJavaScript(
            ControlScripts.consoleRead, arguments: ["args": ["onlyErrors": true, "clear": true]],
            in: nil, contentWorld: .page
        ) as? String
        #expect(errors == "[error] boom")
    }

    private static let checkout = """
    <html><head><title>Pay</title></head><body><form>
    <input autocomplete="cc-number" value="4111111111111111" aria-label="Card number">
    <input autocomplete="billing cc-csc" value="321" aria-label="Security code">
    <input autocomplete="one-time-code" value="424242" aria-label="Verification">
    <input name="otp_code" value="551177" aria-label="Code from your app">
    <input name="cvv" value="987" aria-label="CVV">
    <input name="iban" value="DK5000400440116243" aria-label="Account">
    <input id="ssn" value="078-05-1120" aria-label="Social security">
    <select autocomplete="cc-exp-month" aria-label="Month"><option>01</option><option selected>07</option></select>
    <input name="nickname" value="Ann" aria-label="Name on the account">
    </form></body></html>
    """

    @Test func testCardAndOTPValuesHiddenInReadPageFindAndFill() async throws {
        let webView = try await loaded(Self.checkout)
        let secrets = ["4111111111111111", "321", "424242", "551177", "987", "DK5000400440116243", "078-05-1120"]
        let tree = try await run(webView, "readPage", ["interactiveOnly": false, "maxDepth": 30])
        let found = try await run(webView, "find", ["query": "textbox"])
        for text in [tree, found] {
            for secret in secrets { #expect(!text.contains(secret), "\(secret) in \(text)") }
            // The field is still there to be found by its label; only its value is withheld.
            #expect(text.contains("textbox \"Card number\" [e"))
            #expect(text.contains("value=[hidden]"))
            #expect(text.contains("value=\"Ann\""))
        }
        #expect(!tree.contains("value=\"07\""))

        let card = try #require(Self.ref(in: found, for: "\"Card number\""))
        let filled = try await run(webView, "fill", ["ref": card, "value": "5555555555554444"])
        let typed = try await run(webView, "type", ["ref": card, "text": "9999"])
        for text in [filled, typed] { #expect(!text.contains("5555") && !text.contains("9999"), "\(text)") }
    }

    @Test func screenshotMaskHidesSecretFieldsAndComesOff() async throws {
        let webView = try await loaded(Self.checkout)
        let security = "getComputedStyle(document.querySelector('[name=cvv]')).webkitTextSecurity"
        let none: [String: Any] = ["args": [String: Any]()]
        _ = try await webView.callAsyncJavaScript(ControlScripts.maskSecrets, arguments: none, in: nil, contentWorld: world)
        #expect(try await webView.evaluateJavaScript(security) as? String == "disc")
        #expect(try await webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('[name=nickname]')).webkitTextSecurity"
        ) as? String == "none")
        _ = try await webView.callAsyncJavaScript(ControlScripts.unmaskSecrets, arguments: none, in: nil, contentWorld: world)
        #expect(try await webView.evaluateJavaScript(security) as? String == "none")
    }

    private static let sensitive = """
    <html><head><title>Checkout</title></head><body>
    <form id="pay" onsubmit="event.preventDefault()">
      <input autocomplete="cc-number" aria-label="Card number">
      <input name="note" aria-label="Note">
      <button type="submit">Place order</button>
      <button type="button">Add a note</button>
    </form>
    <form id="login" onsubmit="event.preventDefault()">
      <input name="user" aria-label="Username"><input type="password" aria-label="Password">
      <button>Continue</button>
    </form>
    <a href="https://accounts.example.com/o/oauth2/auth?client_id=a&response_type=code">Sign in with Example</a>
    <a href="/report.csv" download>Export</a>
    <a href="/help">Help</a>
    <div class="g-recaptcha"><iframe title="reCAPTCHA" src="about:blank#recaptcha" width="300" height="80"></iframe></div>
    </body></html>
    """

    /// What `inspect` says about acting on the element `label` names.
    private func inspect(_ webView: WKWebView, _ op: String, _ label: String, _ extra: [String: Any] = [:]) async throws
        -> [String: Any] {
        let found = try await run(webView, "find", ["query": label])
        let ref = try #require(Self.ref(in: found, for: "\"\(label)\""), "\(label) in \(found)")
        let json = try await run(webView, "inspect", extra.merging(["op": op, "ref": ref]) { $1 })
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func risks(_ facts: [String: Any]) -> Set<String> { Set(facts["risks"] as? [String] ?? []) }

    @Test func testInspectFlagsCardFormAndOAuthLink() async throws {
        let webView = try await loaded(Self.sensitive)
        // Submitting the card form is a payment twice over: its field and its button's word.
        #expect(risks(try await inspect(webView, "click", "Place order")) == ["payment"])
        #expect(risks(try await inspect(webView, "click", "Add a note")).isEmpty)
        #expect(risks(try await inspect(webView, "type", "Note")).isEmpty)
        // Card and password fields are the user's to type into; submitting a sign-in is asked.
        #expect(risks(try await inspect(webView, "type", "Card number")) == ["secretField"])
        #expect(risks(try await inspect(webView, "fill", "Password")) == ["secretField"])
        #expect(risks(try await inspect(webView, "click", "Continue")) == ["credentials"])
        #expect(risks(try await inspect(webView, "key", "Username", ["keys": "Enter"])) == ["credentials"])
        // The consent link hands its address back for the app to judge.
        let oauth = try await inspect(webView, "click", "Sign in with Example")
        #expect((oauth["href"] as? String)?.contains("client_id=a") == true)
        #expect(risks(try await inspect(webView, "click", "Export")) == ["download"])
        #expect(risks(try await inspect(webView, "click", "Help")).isEmpty)
        // A CAPTCHA's frame, reached by a point as a model would reach it.
        let box = try await webView.evaluateJavaScript(
            "(() => { const b = document.querySelector('iframe').getBoundingClientRect(); "
                + "return [b.left + 10, b.top + 10].join(','); })()"
        ) as? String
        let point = try #require(box?.split(separator: ",").compactMap { Double($0) })
        let json = try await run(webView, "inspect", ["op": "click", "x": point[0], "y": point[1]])
        #expect(json.contains("captcha"), "\(json)")
    }

    /// The ref on the first line containing `prefix`.
    private static func ref(in text: String, for prefix: String) -> String? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(prefix) }),
              let match = line.firstMatch(of: /\[(e\d+)\]/) else { return nil }
        return String(match.1)
    }
}
