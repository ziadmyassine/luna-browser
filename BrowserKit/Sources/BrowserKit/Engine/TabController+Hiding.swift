import Foundation
import WebKit

/// Hiding a part of a page for good: the picker that chooses it, and the stylesheet
/// that keeps it hidden on every later visit.
///
/// The stylesheet goes in at `documentStart`, so a hidden banner is never seen
/// arriving and then leaving. The picker is not injected into every page — it costs
/// nothing until someone asks for it — and both run in `.defaultClient`, where the
/// page can neither see the picker nor post to it.

/// A picker that is on, and who to tell what it picks.
struct ElementPicking {
    let onPick: @MainActor (HiddenElements.Element) -> Void
    let onEnd: @MainActor () -> Void
}

extension TabController {

    static let pickMessageName = "lunaPick"

    /// Whose hidden elements this tab wears — a private window's own, like `sitePermissions`.
    public var hiddenElements: HiddenElements { .scope(for: dataStore) }

    /// The picker runs where the page can neither see it nor post as it.
    func attachPicker(to controller: WKUserContentController, relay: WKScriptMessageHandler) {
        controller.removeScriptMessageHandler(forName: Self.pickMessageName, contentWorld: .defaultClient)
        controller.add(relay, contentWorld: .defaultClient, name: Self.pickMessageName)
    }

    func detachPicker(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: Self.pickMessageName, contentWorld: .defaultClient)
        endPicking()
    }

    /// The reader, the picker and the Markdown document were all things done to a document that has gone.
    func forgetPageTools() {
        isArticle = false
        readerIsOn = false
        endPicking()
        adoptPendingMarkdown()
    }

    func installHiddenStyle(into controller: WKUserContentController, host: String?) {
        hiddenStyleInstalled = hiddenElements.css(forHost: host)
        if let script = Self.hiddenStyleScript(hiddenStyleInstalled) { controller.addUserScript(script) }
    }

    func hiddenStyleIsStale(for host: String?) -> Bool {
        hiddenElements.css(forHost: host) != hiddenStyleInstalled
    }

    public var isPickingElements: Bool { picking != nil }

    /// Turns the picker on. Every element clicked is handed to `onPick` until the
    /// user presses Escape, the page goes away, or `stopPickingElements()`; then
    /// `onEnd` runs once.
    public func startPickingElements(
        onPick: @escaping @MainActor (HiddenElements.Element) -> Void,
        onEnd: @escaping @MainActor () -> Void
    ) {
        guard let webView, picking == nil else { return }
        picking = ElementPicking(onPick: onPick, onEnd: onEnd)
        webView.callAsyncJavaScript(
            Self.pickerScript + "\nwindow.__lunaPicker.on(palette);",
            arguments: ["palette": InternalPages.palette],
            in: nil,
            in: .defaultClient
        )
    }

    public func stopPickingElements() {
        guard picking != nil else { return }
        webView?.evaluateJavaScript("window.__lunaPicker && window.__lunaPicker.off();", in: nil, in: .defaultClient)
        endPicking()
    }

    func endPicking() {
        guard let ended = picking else { return }
        picking = nil
        ended.onEnd()
    }

    /// Main frame only: the picker is only ever put there, and a frame posting a
    /// selector of its own must not get one hidden on the page around it.
    func handlePickMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        if body["off"] as? Bool == true {
            endPicking()
        } else if let selector = body["selector"] as? String, !selector.isEmpty {
            let label = body["label"] as? String ?? selector
            picking?.onPick(HiddenElements.Element(selector: selector, label: label))
        }
    }

    /// Re-dresses the page on screen after its site's list changed, and swaps the
    /// script set so the next page on the site starts with the same list.
    public func applyHiddenElements() {
        guard let webView else { return }
        let css = hiddenElements.css(forHost: webView.url?.host())
        webView.callAsyncJavaScript(Self.setStyleFunction, arguments: ["css": css], in: nil, in: .defaultClient)
        guard css != hiddenStyleInstalled else { return }
        installUserScripts(
            into: webView.configuration.userContentController,
            host: webView.url?.host(),
            isFile: webView.url?.isFileURL ?? false
        )
    }

    /// Nil when the site has nothing hidden, so a page with no list pays nothing.
    static func hiddenStyleScript(_ css: String) -> WKUserScript? {
        guard !css.isEmpty else { return nil }
        let literal = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return WKUserScript(
            source: "(function (css) {\n\(setStyleFunction)\n})(\(literal));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        )
    }

    /// Before the document has a head, the root element is the only place to put it.
    private static let setStyleFunction = """
    var sheet = document.getElementById('luna-hidden');
    if (!sheet) {
      if (!css) { return; }
      sheet = document.createElement('style');
      sheet.id = 'luna-hidden';
      (document.head || document.documentElement).appendChild(sheet);
    }
    sheet.textContent = css;
    """
}
