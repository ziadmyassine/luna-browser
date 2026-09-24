//
//  ControlService+Network.swift
//  Luna
//
//  `network_read`: the page-world recorder in `ControlScripts+Network.swift`
//  for what the page's script sends, and the tab's navigation responses for
//  the documents it loads, which no page script sees the headers of.
//
//  Only a tab an agent has touched gets either. What comes back goes through
//  the gate's redactor and untrusted fence like every page tool's answer.
//

import BrowserKit
import LunaControl
import WebKit

extension ControlService {

    /// Documents kept per tab. The page's own log keeps 500; documents are a
    /// few per navigation, and a tab that has loaded fifty is long past the
    /// ones an agent is asking about.
    private static let documentLimit = 50

    /// Installs the recorder on a tab the first time an agent touches it, and
    /// runs it now for the document already open, which the user script,
    /// taking effect from the next document, does not reach.
    func watchNetwork(of controller: TabController, in webView: WKWebView) async {
        if controller.onNavigationResponse == nil {
            let id = controller.id
            controller.addUserScript(WKUserScript(
                source: ControlScripts.networkInstall, injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
            controller.onNavigationResponse = { [weak self] response in self?.record(response, tab: id) }
        }
        _ = try? await webView.callAsyncJavaScript(ControlScripts.networkInstall, arguments: [:], in: nil, contentWorld: .page)
    }

    func readNetwork(
        of controller: TabController, in webView: WKWebView, pattern: String?, includeBodies: Bool, clear: Bool
    ) async throws -> ControlResult {
        let args: [String: Any] = [
            "pattern": pattern as Any, "includeBodies": includeBodies, "clear": clear,
            "documents": networkDocuments[controller.id] ?? []
        ]
        let value = try await webView.callAsyncJavaScript(
            ControlScripts.networkRead, arguments: ["args": args], in: nil, contentWorld: .page
        )
        if clear { networkDocuments[controller.id] = nil }
        let text = value as? String ?? ""
        return .text(text.isEmpty ? "No requests since Luna Control first touched this tab." : text)
    }

    private func record(_ response: WKNavigationResponse, tab id: UUID) {
        guard let http = response.response as? HTTPURLResponse, let url = http.url else { return }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            let name = String(describing: name).lowercased()
            // The tool says Set-Cookie is not shown; WebKit may or may not
            // have taken it out already.
            if name != "set-cookie" { headers[name] = String(describing: value) }
        }
        var documents = networkDocuments[id] ?? []
        documents.append([
            "kind": "document", "url": url.absoluteString, "status": http.statusCode,
            "frame": response.isForMainFrame ? "main frame" : "frame",
            "time": Date().timeIntervalSince1970 * 1000, "responseHeaders": headers
        ])
        networkDocuments[id] = Array(documents.suffix(Self.documentLimit))
    }
}
