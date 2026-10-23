import Foundation
import WebKit

/// Hiding a part of a page for good: the picker that chooses it, and the stylesheet
/// that keeps it hidden on every later visit.
///
/// The stylesheet goes in at `documentStart`, so a hidden banner is never seen
/// arriving and then leaving. The picker is not injected into every page — it costs
/// nothing until someone asks for it — and both run in `.defaultClient`, where the
/// page can neither see the picker nor post to it.

/// What comment mode's picker reports about the element pressed. Every string
/// was written by the page, so it is untrusted: one line each, whitespace
/// collapsed and clipped in the picker, and never a form's value.
public struct PageElement: Codable, Equatable, Sendable {
    /// CSS pixels, relative to the viewport.
    public struct Box: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// A hint computed on the live page, not an address. When nothing unique
    /// was found it is the plain nth-of-type path, and `matches` says so.
    public var selector: String
    /// How many elements `selector` matched at the press: 1 unless the hint is ambiguous or resolves to nothing.
    public var matches: Int
    public var tag: String
    /// The role attribute, nil without one: the tag stands for an implicit role.
    public var role: String?
    /// The element's visible words, at most 120 characters.
    public var text: String
    /// Its outerHTML with `value` attributes cut, at most 300 characters.
    public var html: String
    /// The nearest h1–h6 before it, at most 60 characters.
    public var heading: String?
    /// The nearest header, nav, main, aside, footer or role around it.
    public var landmark: String?
    /// What its neighbours are called, at most six.
    public var siblings: [String]
    public var box: Box

    public init(
        selector: String, matches: Int, tag: String, role: String?, text: String, html: String,
        heading: String?, landmark: String?, siblings: [String], box: Box
    ) {
        self.selector = selector
        self.matches = matches
        self.tag = tag
        self.role = role
        self.text = text
        self.html = html
        self.heading = heading
        self.landmark = landmark
        self.siblings = siblings
        self.box = box
    }
}

/// A picker that is on, and who to tell what it picks.
struct ElementPicking {
    enum Mode {
        /// Hide Something…: a selector to file against the site.
        case hiding(@MainActor (HiddenElements.Element) -> Void)
        /// Comment mode: a description of the element, kept even when no selector finds it again.
        case describing(@MainActor (PageElement) -> Void)
    }

    let mode: Mode
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
        startPicker(ElementPicking(mode: .hiding(onPick), onEnd: onEnd))
    }

    /// Comment mode's picker: as `startPickingElements`, but every press is
    /// described, and kept even when its selector is not unique.
    public func startDescribingElements(
        onPick: @escaping @MainActor (PageElement) -> Void,
        onEnd: @escaping @MainActor () -> Void
    ) {
        startPicker(ElementPicking(mode: .describing(onPick), onEnd: onEnd))
    }

    private func startPicker(_ requested: ElementPicking) {
        guard let webView, picking == nil else { return }
        picking = requested
        let detail: Bool
        if case .describing = requested.mode { detail = true } else { detail = false }
        webView.callAsyncJavaScript(
            Self.pickerScript + "\nwindow.__lunaPicker.on(palette, options);",
            arguments: ["palette": InternalPages.palette, "options": ["detail": detail]],
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
        if body["off"] as? Bool == true { return endPicking() }
        switch picking?.mode {
        case let .hiding(onPick):
            guard let selector = body["selector"] as? String, !selector.isEmpty else { return }
            onPick(HiddenElements.Element(selector: selector, label: body["label"] as? String ?? selector))
        case let .describing(onPick):
            // The body's keys are `PageElement`'s own, so it decodes as it stands.
            guard let data = try? JSONSerialization.data(withJSONObject: body),
                  let element = try? JSONDecoder().decode(PageElement.self, from: data) else { return }
            onPick(element)
        case nil:
            break
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
