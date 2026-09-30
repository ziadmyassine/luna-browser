import Foundation
import WebKit

/// Edit: the page's `<textarea>` posts its text, Swift renders the preview and
/// the highlighted backdrop from it, and saving writes it back to the file.
///
/// The textarea's value is never assigned after the page is built. WebKit's
/// undo steps for the typing live against that value, and replacing it drops
/// every one of them, so only the preview and the backdrop are ever replaced.
extension TabController {

    /// Above this many lines the backdrop is plain rows: highlighting the
    /// whole file again on every pause would cost more than the colour is worth.
    static let highlightedLineLimit = 5_000
    static let autosaveDelay = Duration.seconds(1)

    /// Edit's own undo list while Edit is showing, which the web view hands
    /// WebKit and answers ⌘Z from. The window's list also holds closed tabs
    /// and hidden elements, and ⌘Z in the editor must never reach those.
    public var editorUndoManager: UndoManager? { readingView == .edit ? editUndo : nil }

    /// A message from the editor: its whole text.
    func takeEdit(_ text: String) {
        guard let document = markdownDocument, document.isEditable else { return }
        let edited = text == document.editorText ? nil : text
        if edited != editedText { editedText = edited }
        renderEdit(text)
        if edited == nil { autosave?.cancel() } else { scheduleAutosave() }
    }

    /// Writes the editor's text if it differs from the file. True when the
    /// file now holds it. `explicit` is ⌘S, which asks again after saving
    /// stopped over a change on disk; autosave stays quiet until it is answered.
    @discardableResult
    public func saveEdits(explicit: Bool = false) -> Bool {
        autosave?.cancel()
        autosave = nil
        guard let document = markdownDocument, let text = editedText else { return !saveHalted }
        if saveHalted {
            if explicit { delegate?.tabController(self, markdownChangedOnDisk: document.url) }
            return false
        }
        return write(text, over: document, overwritingChanges: false)
    }

    /// Saves now, then again with what the editor holds but has not posted:
    /// it posts 120 ms after the last keystroke, and a tab closed inside that
    /// lost it. The closure keeps the view and the tab alive until the page
    /// answers.
    /// ponytail: a quit can still end the process first; waiting on the page
    /// from `applicationShouldTerminate` would close that.
    func saveEditsBeforeClosing() {
        saveEdits()
        guard readingView == .edit, let view = webView else { return }
        view.evaluateJavaScript(
            "document.querySelector('.luna-input').value", in: nil, in: .defaultClient
        ) { [self] result in
            _ = view
            guard case let .success(value) = result, let text = value as? String else { return }
            takeEdit(text)
            saveEdits()
        }
    }

    /// The answer to `markdownChangedOnDisk`: write the editor's text over the
    /// change, or drop it and read the file again.
    public func resolveDiskConflict(keepMine: Bool) {
        guard let document = markdownDocument else { return }
        saveHalted = false
        if keepMine {
            if let text = editedText { write(text, over: document, overwritingChanges: true) }
        } else {
            editedText = nil
            reload()
        }
    }

    @discardableResult
    private func write(_ text: String, over document: MarkdownDocument, overwritingChanges: Bool) -> Bool {
        do {
            let saved = try document.save(text, overwritingChanges: overwritingChanges)
            // Only if nothing newer was typed while the file was written.
            if editedText == text { editedText = nil }
            markdownDocument = saved
            return true
        } catch MarkdownDocument.SaveError.changedOnDisk {
            saveHalted = true
            delegate?.tabController(self, markdownChangedOnDisk: document.url)
            return false
        } catch {
            delegate?.tabController(self, didFailWith: error)
            return false
        }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveEdits()
        }
    }

    /// A new document, or none: what was edited belonged to the last one.
    func forgetEdits() {
        autosave?.cancel()
        autosave = nil
        editedText = nil
        saveHalted = false
        editUndo.removeAllActions()
    }

    private func renderEdit(_ text: String) {
        let name = markdownDocument?.url.lastPathComponent ?? ""
        webView?.callAsyncJavaScript(
            "if (window.__lunaEditRender) { window.__lunaEditRender(preview, rows); }",
            arguments: ["preview": MarkdownHTML(markdown: text, fileName: name).html, "rows": Self.editorRows(text)],
            in: nil,
            in: .defaultClient
        )
    }

    /// One `.src-line` per line of the textarea, including the empty last one
    /// a trailing newline makes, which the Source view drops.
    static func editorRows(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.count <= highlightedLineLimit else {
            return lines.map { "<div class=\"src-line\">\(HTML.escape(String($0)))</div>" }.joined()
        }
        let rows = MarkdownSource.html(text)
        return lines.count > 1 && lines.last?.isEmpty == true ? rows + "<div class=\"src-line\"></div>" : rows
    }

    /// The editor's half of the page. The leading newline is the one the HTML
    /// parser drops from a textarea, so a document starting with a blank line
    /// keeps it.
    static func editorHTML(_ document: MarkdownDocument, preview: String) -> String {
        guard document.isEditable else { return "" }
        return """
        <div class="luna-edit"><div class="luna-editor"><div class="luna-stack"><div class="luna-band"></div>\
        <pre class="luna-backdrop" aria-hidden="true"><div class="luna-rows">\(editorRows(document.editorText))</div></pre>\
        <textarea class="luna-input" spellcheck="false" autocapitalize="off" aria-label="Markdown">
        \(HTML.escape(document.text))</textarea></div></div>\
        <div class="luna-preview"><article class="luna-reading">\(preview)</article></div></div>
        """
    }

    /// Typing redraws the backdrop's changed rows as plain text at once, so
    /// the words never lag the caret; the highlighted rows follow ~120 ms
    /// after the last keystroke, with the preview.
    static let editorScript = """
    var input = document.querySelector('.luna-input');
    if (input) {
      var rows = document.querySelector('.luna-rows');
      var band = document.querySelector('.luna-band');
      var preview = document.querySelector('.luna-preview .luna-reading');
      var timer = 0;
      var lineIndex = function () { return input.value.slice(0, input.selectionStart).split('\\n').length - 1; };
      var placeBand = function () {
        var row = rows.children[lineIndex()];
        band.style.display = row ? '' : 'none';
        if (row) { band.style.top = row.offsetTop + 'px'; band.style.height = row.offsetHeight + 'px'; }
      };
      var plainRows = function () {
        var lines = input.value.split('\\n');
        if (lines.length !== rows.children.length) {
          rows.replaceChildren.apply(rows, lines.map(function (line) {
            var row = document.createElement('div');
            row.className = 'src-line';
            row.textContent = line;
            return row;
          }));
          return;
        }
        lines.forEach(function (line, i) {
          if (rows.children[i].textContent !== line) { rows.children[i].textContent = line; }
        });
      };
      var post = function () {
        clearTimeout(timer);
        timer = 0;
        webkit.messageHandlers.lunaReading.postMessage({ edit: input.value });
      };
      input.addEventListener('input', function () {
        plainRows();
        placeBand();
        clearTimeout(timer);
        timer = setTimeout(post, 120);
      });
      input.addEventListener('blur', function () { if (timer) { post(); } });
      document.addEventListener('selectionchange', placeBand);
      window.__lunaEditRender = function (html, rowsHTML) {
        preview.innerHTML = html;
        rows.innerHTML = rowsHTML;
        plainRows();
        placeBand();
      };
      placeBand();
    }
    """
}
