import Foundation
import LunaControl
import Testing
import WebKit

/// The library operations behind trusted input and its DOM fallback, in a
/// real windowless web view: where a target is and what it must be routed to,
/// hover, drag and the popups the stage keeps off the user's screen.
@Suite("Luna Control input scripts", .serialized)
@MainActor
struct ControlInputScriptsTests {

    private static let page = """
    <html><body style="margin:0">
    <select id="plan" aria-label="Plan" style="position:absolute;left:0;top:0;width:100px;height:20px">
      <option>Basic</option><option>Pro</option></select>
    <input id="when" type="date" aria-label="When" style="position:absolute;left:0;top:30px">
    <input id="doc" type="file" aria-label="Document" style="position:absolute;left:0;top:60px">
    <button id="go" style="position:absolute;left:200px;top:0;width:100px;height:40px">Go</button>
    <div id="card" draggable="true" style="position:absolute;left:0;top:100px;width:50px;height:50px">Card</div>
    <div id="bin" style="position:absolute;left:200px;top:100px;width:80px;height:80px">Bin</div>
    <div id="ed" contenteditable="true" aria-label="Notes" style="position:absolute;left:300px;top:200px">ab</div>
    <div id="menu" style="position:absolute;left:0;top:200px;width:80px;height:30px">Menu</div>
    <script>
      window.seen = [];
      const note = e => seen.push(e.type + ':' + (e.button ?? '') + (e.metaKey ? ':meta' : ''));
      for (const t of ['contextmenu', 'auxclick', 'click']) go.addEventListener(t, note);
      for (const t of ['mouseover', 'mouseenter', 'pointermove']) menu.addEventListener(t, note);
      card.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', 'card-1'); note(e); });
      bin.addEventListener('dragover', e => e.preventDefault());
      bin.addEventListener('drop', e => { e.preventDefault(); seen.push('drop:' + e.dataTransfer.getData('text/plain')); });
      card.addEventListener('dragend', note);
    </script>
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

    private func ref(_ webView: WKWebView, _ query: String) async throws -> String {
        let found = try await run(webView, "find", ["query": query])
        let match = try #require(found.firstMatch(of: /\[(e\d+)\]/))
        return String(match.1)
    }

    private func seen(_ webView: WKWebView) async throws -> [String] {
        let joined = try await webView.evaluateJavaScript("seen.join(',')") as? String ?? ""
        return joined.split(separator: ",").map(String.init)
    }

    private func located(_ webView: WKWebView, _ args: [String: Any]) async throws -> [String: Any] {
        let json = try await run(webView, "locate", args)
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func locateGivesTheCentreAndRoutesNativePopups() async throws {
        let webView = try await loaded()
        let go = try await located(webView, ["ref": try await ref(webView, "go")])
        #expect(go["x"] as? Double == 250 && go["y"] as? Double == 20)
        #expect(go["route"] is NSNull || go["route"] == nil)
        #expect(go["draggable"] as? Bool == false)
        #expect(try await located(webView, ["ref": try await ref(webView, "plan")])["route"] as? String == "form_input")
        #expect(try await located(webView, ["x": 10, "y": 10])["route"] as? String == "form_input")
        #expect(try await located(webView, ["ref": try await ref(webView, "when")])["route"] as? String == "form_input")
        #expect(try await located(webView, ["ref": try await ref(webView, "document")])["route"] as? String == "file_upload")
        #expect(try await located(webView, ["x": 20, "y": 120])["draggable"] as? Bool == true)
    }

    /// Trusted typing goes to whatever has focus, and keys on a page with no
    /// field focused are its shortcuts: so it needs a field first.
    @Test func focusEndNeedsAFieldAndPutsTheCaretLast() async throws {
        let webView = try await loaded()
        await #expect(throws: (any Error).self) { try await run(webView, "focusEnd", [:]) }
        let notes = try await ref(webView, "notes")
        #expect(try await run(webView, "focusEnd", ["ref": notes]).contains("Notes"))
        #expect(try await run(webView, "focusEnd", [:]).contains("Notes"))
        let caret = try await webView.evaluateJavaScript("getSelection().focusOffset === ed.childNodes.length")
        #expect(caret as? Bool == true)
        await #expect(throws: (any Error).self) { try await run(webView, "focusEnd", ["ref": try await ref(webView, "go")]) }
    }

    @Test func domClickPressesTheButtonItIsGiven() async throws {
        let webView = try await loaded()
        let go = try await ref(webView, "go")
        _ = try await run(webView, "click", ["ref": go, "clickCount": 1, "button": 2])
        _ = try await run(webView, "click", ["ref": go, "clickCount": 1, "button": 1])
        _ = try await run(webView, "click", ["ref": go, "clickCount": 1, "button": 0, "modifiers": ["meta"]])
        #expect(try await seen(webView) == ["contextmenu:2", "auxclick:1", "click:0:meta"])
    }

    @Test func domHoverEntersTheElement() async throws {
        let webView = try await loaded()
        _ = try await run(webView, "hover", ["x": 10, "y": 210])
        #expect(try await seen(webView) == ["mouseover:0", "mouseenter:0", "pointermove:0"])
    }

    @Test func html5DragIsSynthesisedWithItsData() async throws {
        let webView = try await loaded()
        let said = try await run(webView, "drag", ["from": ["x": 20, "y": 120], "to": ["x": 240, "y": 140]])
        #expect(said.contains("Dragged"))
        #expect(try await seen(webView) == ["dragstart:0", "drop:card-1", "dragend:0"])
    }

    /// While the stage drives a page, a context menu or a native popup would
    /// open on the user's screen: their default actions are prevented, and
    /// the page's own listeners still run.
    @Test func stageModePreventsNativePopupsAndLiftsAfter() async throws {
        let webView = try await loaded()
        let fire = """
        [new MouseEvent('contextmenu', {bubbles: true, cancelable: true}),
         new MouseEvent('mousedown', {bubbles: true, cancelable: true}),
         new DragEvent('dragstart', {bubbles: true, cancelable: true})]
          .map((e, i) => [go, plan, card][i].dispatchEvent(e)).join(',')
        """
        #expect(try await webView.evaluateJavaScript(fire) as? String == "true,true,true")
        _ = try await run(webView, "stage", ["on": true])
        #expect(try await webView.evaluateJavaScript(fire) as? String == "false,false,false")
        #expect(try await seen(webView).contains("contextmenu:0"))
        _ = try await run(webView, "stage", ["on": false])
        #expect(try await webView.evaluateJavaScript(fire) as? String == "true,true,true")
    }
}
