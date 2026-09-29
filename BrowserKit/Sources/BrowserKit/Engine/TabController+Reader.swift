import Foundation
import WebKit

/// Reader: the article, and nothing that was arranged around it.
///
/// Done in place, in the tab, rather than on a `luna://reader` page: a page of its
/// own would be a history entry, and Back from it would land on the very page the
/// user just asked to be rid of. Leaving reloads rather than putting the old markup
/// back, because markup put back has lost every listener the page had and looks
/// right while doing nothing.
public enum ReaderAnswer: Sendable {
    case on, off, nothingToRead
}

extension TabController {

    public var isReaderOn: Bool { readerIsOn }

    /// Whether Reader would find an article here, asked once per load from
    /// `didFinish` rather than on every mutation. A page that grows its article
    /// later is missed; Reader from the menu still finds it.
    func probeForArticle() {
        guard let webView, let page = webView.url, markdownDocument == nil, !readerIsOn,
              ["http", "https", "file"].contains(page.scheme ?? "")
        else { return }
        webView.callAsyncJavaScript(
            Self.articleScript + "\nreturn !!article && best >= 20;",
            arguments: [:],
            in: nil,
            in: .defaultClient
        ) { [weak self] result in
            guard let self, self.webView?.url == page else { return }
            isArticle = (try? result.get()) as? Bool ?? false
        }
    }

    public func toggleReader(_ done: @escaping @MainActor (ReaderAnswer) -> Void) {
        guard let webView else { return }
        guard !readerIsOn else {
            readerIsOn = false
            webView.reload()
            done(.off)
            return
        }
        webView.callAsyncJavaScript(
            Self.readingPreferencesScript + Self.readerScript,
            arguments: [
                "sheet": ReadingStyle.css(palette: InternalPages.palette),
                "preferences": ReadingPreferences.stored().script
            ],
            in: nil,
            in: .defaultClient
        ) { [weak self] result in
            let isOn = (try? result.get()) as? String == "on"
            if isOn { self?.readerIsOn = true }
            done(isOn ? .on : .nothingToRead)
        }
    }

    /// Finding the article is the old heuristic that still holds up: each paragraph
    /// scores its parent and, at half, its grandparent, and a container loses what
    /// share of its text is links — menus, related-story rails and comment threads
    /// are made of links, and prose is not.
    ///
    /// A declaration of `article`, `best` and `scores`, shared by Reader and by
    /// `probeForArticle`, so the glyph never offers Reader on a page Reader
    /// would then call empty.
    static let articleScript = """
    var hints = { bad: /comment|meta|footer|footnote|sidebar|share|social|related|promo|newsletter|subscribe|advert|sponsor|popup|cookie/i,
                  good: /article|body|content|entry|main|post|story|text|prose/i };

    function hint(el) {
      var words = (typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || '');
      return (hints.bad.test(words) ? -25 : 0) + (hints.good.test(words) ? 25 : 0);
    }

    function linkShare(el) {
      var text = (el.textContent || '').length;
      if (!text) { return 1; }
      var linked = 0, links = el.getElementsByTagName('a');
      for (var i = 0; i < links.length; i++) { linked += (links[i].textContent || '').length; }
      return linked / text;
    }

    var scores = new Map();
    var paragraphs = document.querySelectorAll('p, pre, td');
    for (var i = 0; i < paragraphs.length; i++) {
      var text = (paragraphs[i].textContent || '').trim();
      if (text.length < 25) { continue; }
      var points = 1 + text.split(',').length + Math.min(Math.floor(text.length / 100), 3);
      var parent = paragraphs[i].parentElement, grand = parent && parent.parentElement;
      if (parent) { scores.set(parent, (scores.get(parent) || hint(parent)) + points); }
      if (grand) { scores.set(grand, (scores.get(grand) || hint(grand)) + points / 2); }
    }
    var article = null, best = 0;
    scores.forEach(function (score, el) {
      var final = score * (1 - linkShare(el));
      if (final > best) { best = final; article = el; }
    });
    """

    /// Pictures are resolved before the page is taken down. `currentSrc` is the image
    /// the page actually chose after `srcset` and `<picture>`; the markup alone is a
    /// lazy placeholder as often as not.
    ///
    /// The page's scripts keep running, so an observer takes away anything they add
    /// afterwards — a cookie bar that arrives late, a paywall overlay.
    static let readerScript = """
    if (document.getElementById('luna-reader')) { return 'on'; }

    """ + articleScript + """

    if (!article || best < 20) { return 'none'; }

    var late = ['data-src', 'data-original', 'data-lazy-src', 'data-lazy', 'data-full-src', 'data-hi-res-src'];
    Array.prototype.forEach.call(document.querySelectorAll('img'), function (img) {
      var real = img.currentSrc || img.getAttribute('src') || '';
      if (!real || real.indexOf('data:') === 0 || img.naturalWidth <= 2) {
        for (var k = 0; k < late.length; k++) {
          if (img.getAttribute(late[k])) { real = img.getAttribute(late[k]); break; }
        }
      }
      if (real && real.indexOf('data:') !== 0) { img.setAttribute('src', real); } else { img.setAttribute('data-luna-drop', ''); }
      img.removeAttribute('srcset');
      img.removeAttribute('loading');
    });

    // The article's own headline, then the page's only one: `og:title` and the
    // document title usually carry the site's name on the end.
    var headings = document.querySelectorAll('h1');
    var headline = article.querySelector('h1') || (headings.length === 1 ? headings[0] : null);
    var meta = document.querySelector('meta[property="og:title"]');
    var title = ((headline && headline.innerText) || (meta && meta.content) || document.title || '').trim();

    // A story split across sibling blocks — a site that wraps every few
    // paragraphs in a box of their own — comes along whole: the siblings that
    // score as prose, and bare paragraphs that are not mostly links.
    var parts = [article];
    if (article.parentElement) {
      parts = Array.prototype.filter.call(article.parentElement.children, function (el) {
        if (el === article) { return true; }
        var score = scores.get(el);
        if (score !== undefined && score * (1 - linkShare(el)) >= Math.max(10, best * 0.2)) { return true; }
        return el.tagName === 'P' && (el.textContent || '').trim().length > 80 && linkShare(el) < 0.25;
      });
    }
    var copy = document.createElement('div');
    parts.forEach(function (part) { copy.appendChild(part.cloneNode(true)); });
    var clutter = 'script,style,noscript,link,form,nav,aside,footer,button,input,select,textarea,svg,canvas,' +
      'object,embed,[aria-hidden="true"],[hidden],[role="navigation"],[role="complementary"],[role="banner"],' +
      '[role="dialog"],img[data-luna-drop]';
    // Never one of the blocks just chosen: `form` or `[aria-hidden]` on the
    // article's own box is a site's markup habit, not a sign it is not the article.
    function chosen(el) { return el.parentElement === copy; }
    Array.prototype.forEach.call(copy.querySelectorAll(clutter), function (el) { if (!chosen(el)) { el.remove(); } });
    Array.prototype.forEach.call(document.querySelectorAll('img[data-luna-drop]'), function (el) {
      el.removeAttribute('data-luna-drop');
    });
    Array.prototype.forEach.call(copy.querySelectorAll('*'), function (el) {
      if (!chosen(el) && hint(el) < 0 && el.getElementsByTagName('p').length < 3) { el.remove(); }
    });
    // Video from the players people embed in articles; every other frame is an ad or a widget.
    var players = /youtube(-nocookie)?\\.com|youtu\\.be|vimeo\\.com|dailymotion\\.com|loom\\.com|wistia/i;
    Array.prototype.forEach.call(copy.querySelectorAll('iframe'), function (frame) {
      if (!players.test(frame.getAttribute('src') || '')) { frame.remove(); }
    });
    var keep = { href: 1, src: 1, alt: 1, title: 1, colspan: 1, rowspan: 1, controls: 1, poster: 1, allowfullscreen: 1 };
    [copy].concat(Array.prototype.slice.call(copy.querySelectorAll('*'))).forEach(function (el) {
      Array.prototype.slice.call(el.attributes).forEach(function (attribute) {
        if (!keep[attribute.name]) { el.removeAttribute(attribute.name); }
      });
    });
    var first = copy.querySelector('h1');
    if (first && first.textContent.trim() === title) { first.remove(); }

    var page = document.createElement('article');
    page.id = 'luna-reader';
    page.className = 'luna-reading';
    var site = document.createElement('p');
    site.className = 'luna-site';
    site.textContent = location.hostname.replace(/^www\\./, '');
    page.appendChild(site);
    if (title) {
      var top = document.createElement('h1');
      top.className = 'luna-title';
      top.textContent = title;
      page.appendChild(top);
    }
    while (copy.firstChild) { page.appendChild(copy.firstChild); }

    Array.prototype.forEach.call(document.querySelectorAll('link[rel~="stylesheet" i], style'), function (el) { el.remove(); });
    document.adoptedStyleSheets = [];
    var root = document.documentElement;
    Array.prototype.slice.call(root.attributes).forEach(function (a) {
      if (a.name !== 'lang' && a.name !== 'dir') { root.removeAttribute(a.name); }
    });
    var head = document.head || root.insertBefore(document.createElement('head'), root.firstChild);
    var style = document.createElement('style');
    style.id = 'luna-reader-style';
    style.textContent = sheet;
    head.appendChild(style);
    var body = document.createElement('body');
    body.appendChild(page);
    if (document.body) { document.body.replaceWith(body); } else { root.appendChild(body); }
    Array.prototype.slice.call(root.children).forEach(function (el) { if (el !== head && el !== body) { el.remove(); } });

    function guard(target, allowed) {
      new MutationObserver(function (changes) {
        changes.forEach(function (change) {
          Array.prototype.forEach.call(change.addedNodes, function (node) {
            if (node.nodeType === 1 && !allowed(node)) { node.remove(); }
          });
        });
      }).observe(target, { childList: true });
    }
    guard(root, function (node) { return node === head || node === body; });
    guard(body, function () { return false; });
    guard(head, function (node) { return !/^(STYLE|LINK)$/.test(node.tagName); });
    // After the root's attributes are cleared above, or they would take these too.
    applyReadingPreferences(preferences);

    window.scrollTo(0, 0);
    // The chrome reads the colour at the top of the page on a resize, and the page it read is gone.
    window.dispatchEvent(new Event('resize'));
    return 'on';
    """
}
