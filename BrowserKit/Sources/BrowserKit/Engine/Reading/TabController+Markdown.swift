import Foundation
import WebKit

/// A Markdown document opened in the tab: caught at its response, rendered in
/// Swift and loaded as a page of Luna's own under the document's URL, so the
/// address stays the file or the web address it came from. Phase 4 of
/// docs/READING-PLAN.md.
///
/// The page is loaded rather than rendered in place: a web host's CSP would
/// govern a page built inside its response, and a `luna://` page would lose
/// the address and the history entry.
extension TabController {

    static let readingMessageName = "lunaReading"

    /// The copy buttons post here. Only in `.defaultClient`, so a script on a
    /// page cannot reach the pasteboard through it.
    func attachReading(to controller: WKUserContentController, relay: WKScriptMessageHandler) {
        controller.removeScriptMessageHandler(forName: Self.readingMessageName, contentWorld: .defaultClient)
        controller.add(relay, contentWorld: .defaultClient, name: Self.readingMessageName)
    }

    /// Whether `response` is a Markdown document this tab has taken over. The
    /// page Luna loads for it arrives as `text/html` under the same URL, which
    /// is what keeps this from catching its own page.
    func interceptMarkdown(_ response: URLResponse, in webView: WKWebView) -> Bool {
        guard let url = response.url, response.mimeType != "text/html",
              (response as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true,
              MarkdownDocument.isMarkdown(url: url, mimeType: response.mimeType)
        else { return false }
        if url.isFileURL {
            guard let document = try? MarkdownDocument.read(from: url) else { return false }
            show(document, in: webView)
        } else {
            fetchMarkdown(at: url, into: webView)
        }
        return true
    }

    func fetchMarkdown(at url: URL, into webView: WKWebView) {
        markdownFetch?.cancel()
        let fetch = fetchText
        markdownFetch = Task { [weak self, weak webView] in
            do {
                let data = try await fetch(url)
                guard !Task.isCancelled, let self, let webView else { return }
                self.show(MarkdownDocument(url: url, data: data, modificationDate: nil), in: webView)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.delegate?.tabController(self, didFailWith: error)
            }
        }
    }

    /// Ephemeral: the fetch carries none of the profile's cookies, as a
    /// document with no script has no use for a session.
    nonisolated static let markdownSession = URLSession(configuration: .ephemeral)

    nonisolated static func fetchMarkdownText(_ url: URL) async throws -> Data {
        let (data, response) = try await markdownSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func show(_ document: MarkdownDocument, in webView: WKWebView) {
        pendingMarkdown = document
        webView.load(
            Data(Self.markdownPage(document).utf8),
            mimeType: "text/html",
            characterEncodingName: "utf-8",
            baseURL: document.url
        )
    }

    /// At commit: the document belongs to the page only if this is the load
    /// `show` started.
    func adoptPendingMarkdown() {
        saveEdits()
        forgetEdits()
        markdownDocument = pendingMarkdown.flatMap { $0.url == webView?.url ? $0 : nil }
        pendingMarkdown = nil
        readingView = .read
    }

    /// Preferences, the outline's current heading, the copy buttons and the
    /// editor. Run at `didFinish` rather than injected into every page.
    func startMarkdownPage() {
        guard markdownDocument != nil else { return }
        webView?.callAsyncJavaScript(
            Self.readingPreferencesScript + Self.markdownScript + Self.editorScript,
            arguments: ["preferences": ReadingPreferences.stored().script],
            in: nil,
            in: .defaultClient
        )
    }

    func handleReadingMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, markdownDocument != nil,
              let body = message.body as? [String: Any]
        else { return }
        if let text = body["edit"] as? String {
            takeEdit(text)
        } else if let code = body["copy"] as? String {
            delegate?.tabController(self, didCopyCode: code)
        }
    }

    static func markdownPage(_ document: MarkdownDocument) -> String {
        let name = document.url.lastPathComponent
        let rendered = MarkdownHTML(markdown: document.text, fileName: name)
        // 230 words a minute, the usual figure for reading on screen.
        let minutes = max(1, document.text.split { $0.isWhitespace }.count / 230)
        let entries = rendered.headings.filter { (2 ... 3).contains($0.level) }.map {
            "<li class=\"h\($0.level)\"><a href=\"#\(HTML.escape($0.id))\">\(HTML.escape($0.text))</a></li>"
        }
        let outline = entries.isEmpty ? "" :
            "<nav class=\"luna-outline\" aria-label=\"On this page\"><p>On this page</p><ul>\(entries.joined())</ul></nav>"
        let csp = "default-src 'none'; img-src file: http: https: data:; style-src 'unsafe-inline'; "
            + "script-src 'none'; form-action 'none'; base-uri 'none'"
        // The Source view is rendered now and shown by `data-view`, so
        // switching to it later needs no reload.
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width">
        <title>\(HTML.escape(rendered.title))</title>
        <style>\(ReadingStyle.css(palette: InternalPages.palette))</style></head>
        <body data-view="read">\(outline)
        <article class="luna-reading"><p class="luna-site">\(HTML.escape(name)) · \(minutes) min read</p>
        \(rendered.html)</article>
        <div class="luna-source">\(MarkdownSource.html(document.text))</div>
        \(editorHTML(document, preview: rendered.html))
        </body></html>
        """
    }

    /// The outline marks the last heading scrolled past the top, or the first
    /// before any has been.
    static let markdownScript = """
    applyReadingPreferences(preferences);
    if (window.__lunaMarkdown) { return; }
    window.__lunaMarkdown = true;
    document.addEventListener('click', function (event) {
      var button = event.target.closest && event.target.closest('.luna-copy');
      if (!button) { return; }
      var code = button.parentNode.querySelector('code');
      webkit.messageHandlers.lunaReading.postMessage({ copy: code ? code.textContent : '' });
    });
    var links = Array.prototype.slice.call(document.querySelectorAll('.luna-outline a'));
    var targets = links.map(function (a) { return document.getElementById(decodeURIComponent(a.hash.slice(1))); });
    function mark() {
      var current = 0;
      targets.forEach(function (target, i) { if (target && target.getBoundingClientRect().top <= 80) { current = i; } });
      links.forEach(function (a, i) {
        if (i === current) { a.setAttribute('aria-current', 'true'); } else { a.removeAttribute('aria-current'); }
      });
    }
    addEventListener('scroll', mark, { passive: true });
    mark();
    """
}
