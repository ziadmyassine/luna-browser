import Foundation

//  The three pages. Nothing here concatenates a raw string into markup: every
//  interpolation goes through `HTML.escape` or `HTML.href`, both of which are
//  the point of `InternalPagesTests.escapesEverythingItRenders`. An error page
//  renders an attacker-chosen URL by definition, and an archived tab's title is
//  whatever `<title>` the page it came from felt like setting.

extension InternalPages {

    @MainActor
    static func html(for page: Page) -> String {
        switch page {
        case .newTab: newTabHTML()
        case .archive: archiveHTML()
        case let .error(error): errorHTML(error)
        }
    }

    // MARK: - New Tab (§30.19)
    //
    // §30.20's voice input and §30.21's cross-device button are deliberately
    // absent: one needs a speech entitlement and the other needs sync, and
    // neither exists. An affordance that does nothing is worse than no
    // affordance (§30.4 says so in as many words).

    @MainActor
    static func newTabHTML() -> String {
        let favorites = content?().favorites ?? []
        let tiles = favorites.compactMap(tile) + [addFavoriteTile]
        let body = """
        <main class="newtab">
        <a class="pill plate" href="\(scheme)://commandbar">\
        <span class="lead" aria-hidden="true">+</span>\
        <span>Search or type a URL</span></a>
        <ul class="grid" aria-label="Favorites">\(tiles.joined())</ul>
        </main>
        """
        return document(title: Page.newTab.name, bodyClass: "", body: body)
    }

    @MainActor
    private static func tile(_ entry: InternalPageContent.Entry) -> String? {
        guard let href = HTML.href(entry.url) else { return nil }
        let label = entry.title.isEmpty ? (entry.url.host() ?? entry.url.absoluteString) : entry.title
        return """
        <li><a class="tile plate" href="\(href)">\(icon(for: entry.url))\
        <span class="label">\(HTML.escape(label))</span></a></li>
        """
    }

    private static var addFavoriteTile: String {
        """
        <li><a class="tile plate add" href="\(scheme)://addfavorite">\
        <span>+ Add Favorite</span></a></li>
        """
    }

    // MARK: - History (§6.4)
    //
    // Luna's word for the shelf is "the archive" and the user's word is
    // "history"; the page wears the user's. The route stays `luna://archive`
    // because a URL is not a label.
    //
    // It is laid out like the §3.4 tab list rather than like a web page: a
    // title and its filter on one line, then rounded rows carrying a favicon,
    // a title and a subtitle, with the Restore affordance appearing on hover
    // the way a row's trailing chip does. Before this it was a bare `<h1>`,
    // a full-width field and a stack of hairline-separated lines — correct,
    // and visibly not part of the same app as the window around it.

    @MainActor
    static func archiveHTML() -> String {
        let archived = content?().archived ?? []
        let rows = archived.map(archiveRow).joined()
        let list = rows.isEmpty
            ? "<p class=\"empty\">Nothing here yet. Closed tabs are kept for a while and show up here.</p>"
            : "<ul class=\"rows\">\(rows)</ul>"
        let body = """
        <main class="history">
        <header class="head">
        <h1>History</h1>
        <input class="search" id="q" type="search" placeholder="Search history"\
         aria-label="Search history" autofocus>
        </header>
        \(list)
        <p class="empty" id="none" hidden>No matches.</p>
        </main>
        """
        return document(title: Page.archive.name, bodyClass: "", body: body, script: archiveScript)
    }

    @MainActor
    private static func archiveRow(_ entry: InternalPageContent.Entry) -> String {
        let host = entry.url.host() ?? entry.url.absoluteString
        let title = entry.title.isEmpty ? host : entry.title
        let when = entry.archivedAt.map(Self.archivedFormatter.string(from:)) ?? ""
        let subtitle = when.isEmpty ? host : "\(host) · \(when)"
        // Restoring is Luna's job, not a navigation: the tab comes back where it
        // was, with its session blob, which only `BrowserSession` can do.
        let href = "\(scheme)://restore?tab=\(entry.id.uuidString)"
        return """
        <li data-search="\(HTML.escape((title + " " + host).lowercased()))">\
        <a class="row" href="\(href)">\(icon(for: entry.url))\
        <span class="text"><span class="title">\(HTML.escape(title))</span>\
        <span class="sub">\(HTML.escape(subtitle))</span></span>\
        <span class="go plate">Restore</span></a></li>
        """
    }

    /// Filters rows that are already in the DOM. No network, no `eval`, no
    /// generated markup — the one thing the page cannot do without script is
    /// narrow a list as you type, and §6.4 asks for exactly that.
    private static let archiveScript = """
    (function(){
      var q=document.getElementById('q'),rows=document.querySelectorAll('.rows li'),none=document.getElementById('none');
      q.addEventListener('input',function(){
        var text=q.value.trim().toLowerCase(),shown=0;
        for(var i=0;i<rows.length;i++){
          var hit=!text||rows[i].dataset.search.indexOf(text)>=0;
          rows[i].hidden=!hit;
          if(hit){shown++;}
        }
        none.hidden=shown>0||!rows.length;
      });
    })();
    """

    private static let archivedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Errors (§4.5)
    //
    // One card and six marks. The kind is a class on `.error` and a glyph in
    // the well; everything else about the page is the same page, because these
    // six are the same event — Luna could not give you what you asked for, and
    // here is the one thing you can do about it.

    @MainActor
    static func errorHTML(_ error: InternalPageError) -> String {
        let copy = Self.copy(for: error.kind)
        let target = error.url.map {
            "<p class=\"target well\">\(HTML.escape($0.absoluteString))</p>"
        } ?? ""
        // The detail is a second voice — a certificate's own words, a
        // blocklist's name — so it is not dressed as the address.
        let detail = error.detail.map { "<p class=\"note\">\(HTML.escape($0))</p>" } ?? ""
        let body = """
        <main class="error \(error.kind.rawValue)">
        <div class="card pane lifted">
        <span class="mark well" aria-hidden="true">\(mark(for: error.kind))</span>
        <h1>\(HTML.escape(copy.title))</h1>
        <p>\(HTML.escape(copy.message))</p>
        \(target)\(detail)
        <div class="actions">\(actions(for: error))</div>
        </div>
        </main>
        """
        return document(title: copy.title, bodyClass: "", body: body)
    }

    private static func actions(for error: InternalPageError) -> String {
        var buttons: [String] = []
        if let url = error.url {
            let host = error.offersBypass ? "proceed" : "retry"
            let label = error.offersBypass ? "Continue Anyway" : "Try Again"
            // Continuing is never the recommendation. The two kinds that
            // offer it are the two Luna stopped on purpose, so the emphasis
            // goes to the way out rather than to the way through; every other
            // kind is a failure nobody chose and trying again is the answer.
            let role = error.offersBypass ? "button plate" : "button key plate"
            buttons.append("<a class=\"\(role)\" href=\"\(HTML.action(host, url: url))\">\(label)</a>")
        }
        let home = error.offersBypass ? "button key plate" : "button plate"
        buttons.append("<a class=\"\(home)\" href=\"\(scheme)://newtab\">New Tab</a>")
        return buttons.joined()
    }

    /// One mark per kind, drawn in `currentColor` so the stylesheet decides
    /// whether it is ink or §8.1's danger — there is no colour in this file
    /// either.
    ///
    /// Six glyphs, not one. Every kind used to wear the same exclamation
    /// in a circle, which is the mark for "something went wrong" and therefore
    /// says nothing at all six times. These are the distinctions the sentence
    /// under them is already making: a network that is not there, a name that
    /// did not resolve, a certificate that did not check out, a request Luna
    /// itself stopped, and a site with no encryption to offer. The last one
    /// keeps the circle, because "something went wrong" is honestly all that
    /// page knows.
    ///
    /// Stroked rather than filled, at the weight SF Symbols draw at this size,
    /// so a mark on one of Luna's pages and a mark in Luna's chrome are the
    /// same hand.
    private static func mark(for kind: InternalPageError.Kind) -> String {
        svg(paths(for: kind))
    }

    private static func svg(_ paths: String) -> String {
        """
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"\
         stroke-linecap="round" stroke-linejoin="round">\(paths)</svg>
        """
    }

    private static func paths(for kind: InternalPageError.Kind) -> String {
        switch kind {
        // The Wi-Fi fan, struck through: the arcs are what the menu bar draws,
        // and the stroke across them is the whole message.
        case .offline:
            """
            <path d="M2.5 8.6a15 15 0 0 1 19 0"/><path d="M5.8 12.5a10 10 0 0 1 12.4 0"/>\
            <path d="M9.1 16.4a5 5 0 0 1 5.8 0"/><path d="M12 19.9v.01"/><path d="M3 3l18 18"/>
            """
        // A search that came back with nothing in it — the name was looked up
        // and there was no answer, which is not the same as a network failing.
        // The cross is inside the lens rather than across the whole mark: a
        // magnifier with a bar through it is the zoom-out control.
        case .dns:
            """
            <circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.2 15.2L20.5 20.5"/>\
            <path d="M8.4 8.4l4.2 4.2"/><path d="M12.6 8.4l-4.2 4.2"/>
            """
        // A lock that is shut, with something wrong inside it. The site
        // offered encryption and the proof behind it did not check out, which
        // is not the open lock below — and it is not a lock with a line
        // through it either: rendered at 28 pt the slash crossed the shackle
        // and the whole mark read as a scribble.
        case .tls:
            """
            <rect x="4.5" y="10" width="15" height="9.5" rx="2.5"/>\
            <path d="M8.2 10V6.8a3.8 3.8 0 0 1 7.6 0V10"/>\
            <path d="M12 12.9v2.3"/><path d="M12 17.1v.01"/>
            """
        // A shield with a bar across it. Luna stopped this, and a shield is
        // the only mark on the page that means "on purpose".
        case .blocked:
            """
            <path d="M12 2.8l8 3v6.1c0 4.9-3.4 8.1-8 9.3-4.6-1.2-8-4.4-8-9.3V5.8z"/>\
            <path d="M8.8 12h6.4"/>
            """
        // The same lock, whole but hanging open: nothing is broken here, there
        // was simply never a lock on it.
        case .httpsDowngrade:
            """
            <rect x="4.5" y="10" width="15" height="9.5" rx="2.5"/>\
            <path d="M8.2 10V6.8a3.8 3.8 0 0 1 7.3-1.4"/><path d="M12 13.4v2.6"/>
            """
        case .generic:
            """
            <circle cx="12" cy="12" r="9"/><path d="M12 7v6"/><path d="M12 16.5v.01"/>
            """
        }
    }

    /// Shared with `Page.name`: an error page's title is what a tab showing it
    /// is called, and the two must not be able to disagree.
    static func copy(for kind: InternalPageError.Kind) -> (title: String, message: String) {
        switch kind {
        case .offline:
            ("You're offline", "Luna can't reach the network. Check your Wi-Fi or Ethernet connection.")
        case .dns:
            ("Can't find that site", "The address didn't resolve. Check the spelling, or the site may be gone.")
        case .tls:
            ("This connection isn't private", "The site's certificate couldn't be verified, so Luna stopped.")
        case .blocked:
            ("Blocked by Luna", "Luna's content blocker stopped this request.")
        case .httpsDowngrade:
            ("This site isn't secure", "Luna asked for an encrypted connection and the site only offers HTTP.")
        case .generic:
            ("This page didn't load", "Something went wrong on the way to this page.")
        }
    }

    // MARK: - Favicons

    /// A favicon `<span>`, backed by a `luna://favicon/<host>` sub-resource when
    /// one is actually cached, and by a monogram when it is not. Asking
    /// `FaviconService` here rather than emitting a speculative URL is what
    /// keeps §4.7's "no icon ever flashes a broken-image glyph" true.
    @MainActor
    private static func icon(for url: URL) -> String {
        guard let host = url.host() else { return "<span class=\"icon\"></span>" }
        let monogram = host.trimmingPrefix("www.").first.map(String.init)?.uppercased() ?? ""
        guard FaviconService.shared.favicon(forHost: host) != nil,
              let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return "<span class=\"icon\">\(HTML.escape(monogram))</span>" }
        return """
        <span class="icon has-fav" style="--fav:url(&quot;\(scheme)://favicon/\(HTML.escape(encoded))&quot;)">\
        \(HTML.escape(monogram))</span>
        """
    }
}
