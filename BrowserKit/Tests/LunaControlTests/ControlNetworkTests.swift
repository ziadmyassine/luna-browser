import Foundation
import LunaControl
import Testing
import WebKit

/// `network_read`'s capture script in a real, windowless web view, installed at
/// document start the way the app installs it, against pages served from a
/// scheme handler so no test touches the network.
@Suite("Luna Control network log", .serialized)
@MainActor
struct ControlNetworkTests {

    private static let origin = "lunatest://site"

    private func loaded(_ script: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(Fixture(page: script), forURLScheme: "lunatest")
        configuration.userContentController.addUserScript(
            WKUserScript(source: ControlScripts.networkInstall, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.load(URLRequest(url: URL(string: Self.origin + "/")!))
        for _ in 0 ..< 200 where webView.title != "done" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(webView.title == "done")
        // A response body is read from a clone, a moment after the page has its own.
        try await Task.sleep(for: .milliseconds(200))
        return webView
    }

    private func read(
        _ webView: WKWebView, bodies: Bool = false, pattern: String? = nil, documents: [[String: Any]] = []
    ) async throws -> String {
        var args: [String: Any] = ["includeBodies": bodies, "clear": false, "documents": documents]
        if let pattern { args["pattern"] = pattern }
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.networkRead, arguments: ["args": args], in: nil, contentWorld: .page
        )
        return value as? String ?? ""
    }

    @Test func testFetchAndXHRCaptured() async throws {
        let webView = try await loaded("""
        await fetch('/api/items?x=1', { headers: { 'X-Asked': 'yes' } }).then(r => r.text());
        await new Promise(done => {
          const xhr = new XMLHttpRequest();
          xhr.open('POST', '/api/save');
          xhr.setRequestHeader('Content-Type', 'text/plain');
          xhr.onloadend = done;
          xhr.send('name=Ann');
        });
        """)
        let log = try await read(webView)
        #expect(log.contains("fetch GET \(Self.origin)/api/items?x=1 → 200"))
        #expect(log.contains("> x-asked: yes"))
        #expect(log.contains("< x-served-by: fixture"))
        #expect(log.contains("xhr POST \(Self.origin)/api/save → 201"))
        #expect(!log.contains("{\"items\""), "bodies only when asked for")

        let bodies = try await read(webView, bodies: true)
        #expect(bodies.contains("response body: {\"items\":[1,2]}"))
        #expect(bodies.contains("request body: name=Ann"))
        #expect(bodies.contains("response body: saved"))

        let only = try await read(webView, pattern: "SAVE")
        #expect(only.contains("/api/save") && !only.contains("/api/items"))

        // The document itself comes from the app's navigation response, not the page.
        let withDocument = try await read(webView, documents: [[
            "kind": "document", "method": "", "url": Self.origin + "/", "status": 200, "frame": "main frame",
            "time": 0, "responseHeaders": ["content-type": "text/html"]
        ]])
        #expect(withDocument.hasPrefix("document \(Self.origin)/ → 200 (main frame)\n  < content-type: text/html"))
    }

    @Test func testAuthorizationHeaderRedacted() async throws {
        let webView = try await loaded("""
        await fetch('/api/items', {
          method: 'POST',
          headers: { Authorization: 'Bearer abc.def-123456789' },
          body: JSON.stringify({ access_token: 's3cr3tvalue', name: 'Ann' })
        });
        """)
        let raw = try await read(webView, bodies: true)
        #expect(raw.contains("abc.def-123456789"), "the page's log holds it; the redactor is what takes it out")
        let clean = ControlRedactor.scrub(raw)
        #expect(!clean.contains("abc.def-123456789"))
        #expect(!clean.contains("s3cr3tvalue"))
        #expect(clean.contains("> authorization: \(ControlRedactor.hidden)"))
        #expect(clean.contains("\"name\":\"Ann\""))
    }

    @Test func testBodyCapped() async throws {
        let webView = try await loaded("""
        await fetch('/big').then(r => r.text());
        """)
        let log = try await read(webView, bodies: true, pattern: "/big")
        let body = try #require(log.components(separatedBy: "response body: ").last)
        #expect(body.count <= ControlScripts.networkBodyLimit + 40)
        #expect(body.contains("[cut at 10 KB]"))
    }

    @Test func logKeepsTheNewest500() async throws {
        let webView = try await loaded("""
        await fetch('/big');
        await Promise.all(Array.from({ length: 520 }, (_, i) => fetch('/api/save?n=' + i)));
        """)
        let all = try await read(webView)
        let entries = all.split(separator: "\n").filter { !$0.hasPrefix(" ") }
        #expect(entries.count == ControlScripts.networkEntryLimit)
        #expect(all.contains("fetch GET \(Self.origin)/api/save?n=519"))
        #expect(!all.contains("/big"), "the oldest entry went first")
    }

    @Test func networkReadIsAReadThatNeverAsks() throws {
        let call = try #require(try? ControlCall.parse(
            tool: "network_read", arguments: ["pattern": "api", "include_bodies": true, "clear": "yes"]
        )?.get())
        #expect(call.command == .network(pattern: "api", includeBodies: true, clear: false))
        #expect(!call.command.acts)
        #expect(ControlAudit.tool(of: call.command) == "network_read")
    }
}

/// Serves the fixture site: the page, which runs `page` and then titles itself
/// "done", and the endpoints it calls.
private final class Fixture: NSObject, WKURLSchemeHandler {
    let page: String

    init(page: String) { self.page = page }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let (status, type, body): (Int, String, String) = switch url.path {
        case "/api/items": (200, "application/json", "{\"items\":[1,2]}")
        case "/api/save": (201, "text/plain", "saved")
        case "/big": (200, "text/plain", String(repeating: "a", count: 50_000))
        default:
            (200, "text/html", "<html><body><script>(async () => {\n\(page)\ndocument.title = 'done';\n})()</script></body></html>")
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type, "X-Served-By": "fixture", "Access-Control-Allow-Origin": "*",
            "Access-Control-Expose-Headers": "X-Served-By"
        ])!
        task.didReceive(response)
        task.didReceive(Data(body.utf8))
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
