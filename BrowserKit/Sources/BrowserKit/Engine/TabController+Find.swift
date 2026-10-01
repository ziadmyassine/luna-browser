import Foundation
import WebKit

/// Where a find landed: whether WebKit found the text, and which of how many
/// matches it is when the page could be counted.
public struct FindResult: Equatable, Sendable {
    public let found: Bool
    /// One-based. Nil when the count could not place WebKit's match.
    public let match: Int?
    /// Nil when the page could not be counted, or the count disagreed with
    /// what WebKit selected.
    public let total: Int?
    /// The count stopped at `TabController.findCountCap`.
    public let isCapped: Bool

    public init(found: Bool, match: Int? = nil, total: Int? = nil, isCapped: Bool = false) {
        self.found = found
        self.match = match
        self.total = total
        self.isCapped = isCapped
    }

    public static let notFound = FindResult(found: false)
}

/// §18.1's find in page.
///
/// The search is WebKit's own `find(_:configuration:)`, the only public find
/// on macOS: it searches the rendered page, frames included, selects the match
/// and scrolls to it. It returns found or not found and nothing else. The
/// match count, the highlight on every match and the yellow find indicator all
/// sit behind `_findString:options:maxCount:`, which is SPI. `NSTextFinder`,
/// which `WKWebView` is a client of, counts and highlights only through
/// AppKit's own find bar and the shared find pasteboard, so its search string
/// cannot come from a field of Luna's.
///
/// So the "3 of 12" is counted by a script, `findCountScript`, which reads the
/// page and changes nothing. It is an approximation of what WebKit searches —
/// the main frame's visible text, no frames, no shadow trees, no form fields —
/// and it is only believed when it agrees with WebKit: the selection WebKit
/// made has to be the query and has to start on one of the counted matches.
/// When it does not, the field shows no count rather than a wrong one.
extension TabController {

    /// Safari's ceiling. Past it a page is "1000+", and counting on would only
    /// cost time on every keystroke.
    public static let findCountCap = 1000

    /// Finds the next match of `query` after the selection, or the previous one.
    ///
    /// - Parameter fromMatchStart: the query has changed. WebKit looks from the
    ///   end of the selection, so a longer query would skip the match a shorter
    ///   one found; the selection is first collapsed to its start, which is the
    ///   one thing here that writes to the page.
    public func find(_ query: String, backwards: Bool = false, fromMatchStart: Bool = false) async -> FindResult {
        guard let webView, !query.isEmpty else { return .notFound }
        if fromMatchStart {
            _ = try? await webView.callAsyncJavaScript(Self.collapseSelectionScript, contentWorld: .defaultClient)
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        guard let result = try? await webView.find(query, configuration: configuration), result.matchFound else {
            return .notFound
        }
        let counted = try? await webView.callAsyncJavaScript(
            Self.findCountScript,
            arguments: ["query": query, "cap": Self.findCountCap],
            contentWorld: .defaultClient
        ) as? [Any]
        guard let counted, counted.count == 3,
              let total = (counted[0] as? NSNumber)?.intValue, let match = (counted[1] as? NSNumber)?.intValue,
              total > 0, match > 0
        else { return FindResult(found: true) }
        return FindResult(found: true, match: match, total: total, isCapped: (counted[2] as? Bool) ?? false)
    }

    /// The page's selected text, for Use Selection for Find. Empty is nil.
    public func selectedText() async -> String? {
        guard let webView else { return nil }
        let text = try? await webView.callAsyncJavaScript(
            "return window.getSelection() ? window.getSelection().toString() : '';",
            contentWorld: .defaultClient
        ) as? String
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static let collapseSelectionScript = """
    const selection = window.getSelection();
    if (selection && selection.rangeCount > 0 && !selection.isCollapsed) selection.collapseToStart();
    """

    /// Returns `[total, match, capped]`; `match` is 0 when the selection is
    /// not on a counted match.
    ///
    /// The text is rebuilt the way WebKit's find sees it: visible text nodes in
    /// document order, a line break between blocks and at a `<br>` (find does
    /// not match across one), runs of white space as one space where CSS
    /// collapses them, and case and accents folded, because a find that is not
    /// case-sensitive is not accent-sensitive either.
    static let findCountScript = """
    const fold = (s) => s.normalize('NFD').replace(/\\p{M}/gu, '').toLowerCase();
    const needle = fold(query).replace(/\\s+/g, ' ');
    if (!needle) return [0, 0, false];

    let mark = null;
    const selection = window.getSelection();
    if (selection && selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      if (!range.collapsed && fold(range.toString()).replace(/\\s+/g, ' ') === needle) {
        mark = document.createRange();
        mark.setStart(range.startContainer, range.startOffset);
      }
    }

    const looks = new Map();
    const look = (el) => {
      let seen = looks.get(el);
      if (seen) return seen;
      const style = getComputedStyle(el);
      const display = style.display;
      const space = style.whiteSpaceCollapse || style.whiteSpace || '';
      const hidden = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|SELECT|OPTION|TEXTAREA)$/.test(el.tagName)
        || (el.checkVisibility ? !el.checkVisibility({ visibilityProperty: true }) : false);
      seen = {
        block: !(display.startsWith('inline') || display === 'contents' || display === 'none'),
        pre: space.startsWith('pre') || space.startsWith('preserve') || space === 'break-spaces',
        hidden: hidden
      };
      looks.set(el, seen);
      return seen;
    };
    const blocks = new Map();
    const blockOf = (el) => {
      if (blocks.has(el)) return blocks.get(el);
      let block = el;
      while (block.parentElement && !look(block).block) block = block.parentElement;
      blocks.set(el, block);
      return block;
    };

    const parts = [];
    let length = 0, tail = '\\n', at = -1, lastBlock = null;
    const push = (s) => { if (s) { parts.push(s); length += s.length; tail = s[s.length - 1]; } };
    const lineBreak = () => { if (tail !== '\\n') push('\\n'); };
    const shape = (raw, pre, before) => {
      let s = fold(raw);
      if (!pre) {
        s = s.replace(/\\s+/g, ' ');
        if ((before === ' ' || before === '\\n') && s[0] === ' ') s = s.slice(1);
      }
      return s;
    };

    const root = document.body || document.documentElement;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        if (mark && at < 0 && mark.comparePoint(node, 0) >= 0) at = length;
        if (node.tagName === 'BR') lineBreak();
        continue;
      }
      const parent = node.parentElement;
      if (!parent || look(parent).hidden) continue;
      const block = blockOf(parent);
      if (block !== lastBlock) { lineBreak(); lastBlock = block; }
      const pre = look(parent).pre;
      if (mark && at < 0) {
        if (node === mark.startContainer) at = length + shape(node.data.slice(0, mark.startOffset), pre, tail).length;
        else if (mark.comparePoint(node, 0) >= 0) at = length;
      }
      push(shape(node.data, pre, tail));
    }

    const text = parts.join('');
    let total = 0, match = 0, from = 0, capped = false;
    for (;;) {
      const found = text.indexOf(needle, from);
      if (found < 0) break;
      total += 1;
      if (found === at) match = total;
      from = found + needle.length;
      if (total >= cap) { capped = text.indexOf(needle, from) >= 0; break; }
    }
    return [total, match, capped];
    """
}
