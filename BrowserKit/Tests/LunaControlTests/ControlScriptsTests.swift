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

    private func loaded() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.com/"))
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

    /// The ref on the first line containing `prefix`.
    private static func ref(in text: String, for prefix: String) -> String? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(prefix) }),
              let match = line.firstMatch(of: /\[(e\d+)\]/) else { return nil }
        return String(match.1)
    }
}
