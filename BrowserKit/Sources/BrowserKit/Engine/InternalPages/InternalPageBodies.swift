import Foundation

//  The two pages. Nothing here concatenates a raw string into markup: every
//  interpolation goes through `HTML.escape` or `HTML.href`, both of which are
//  the point of `InternalPagesTests.escapesEverythingItRenders`. An error page
//  renders an attacker-chosen URL by definition, and an archived tab's title is
//  whatever `<title>` the page it came from felt like setting.

extension InternalPages {

    @MainActor
    static func html(for page: Page) -> String {
        switch page {
        case .history: historyHTML()
        case let .error(error): errorHTML(error)
        }
    }

    // MARK: - History (§6.4)
    //
    // History is the name everywhere the user meets it, the address included:
    // an address bar is something people read, and a page whose title says
    // History over a URL that says archive is two names for one thing. The
    // stored state keeps the older word — a tab has an `archivedAt`, and
    // `AutoArchive` is what puts it there — because that is a thing that
    // happened to a tab, not a place the user goes. `luna://archive` still
    // routes here (§4.4).
    //
    // It is laid out like the §3.4 tab list rather than like a web page: a
    // title and its filter on one line, then rounded rows carrying a favicon,
    // a title and a subtitle, with the Restore affordance appearing on hover
    // the way a row's trailing chip does. Before this it was a bare `<h1>`,
    // a full-width field and a stack of hairline-separated lines — correct,
    // and visibly not part of the same app as the window around it.

    @MainActor
    static func historyHTML() -> String {
        let archived = content?().archived ?? []
        let rows = archived.map(historyRow).joined()
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
        return document(title: Page.history.name, bodyClass: "", body: body, script: historyScript)
    }

    @MainActor
    private static func historyRow(_ entry: InternalPageContent.Entry) -> String {
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
    private static let historyScript = """
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
    // One card and one mark per kind. The kind is a class on `.error` and a
    // glyph in the well; everything else about the page is the same page,
    // because all of them are the same event — Luna could not give you what
    // you asked for, and here is the one thing you can do about it.

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
        if let url = error.url, error.offersBypass || error.offersRetry {
            let host = error.offersBypass ? "proceed" : "retry"
            let label = error.offersBypass ? "Continue Anyway" : "Try Again"
            // Continuing is never the recommendation. The two kinds that
            // offer it are the two Luna stopped on purpose, so the emphasis
            // goes to the way out rather than to the way through; every other
            // kind is a failure nobody chose and trying again is the answer.
            let role = error.offersBypass ? "button plate" : "button key plate"
            buttons.append("<a class=\"\(role)\" href=\"\(HTML.action(host, url: url))\">\(label)</a>")
        }
        // The recommendation, when there is no other button to carry it: an
        // address with no page behind it has nothing to retry and nothing to
        // continue past, so saying where you meant to go is the only move.
        let home = buttons.isEmpty || error.offersBypass ? "button key plate" : "button plate"
        // §9.1, not a page. There is nowhere to send somebody who is stuck on
        // an error except somewhere they can say where they want to go.
        buttons.append("<a class=\"\(home)\" href=\"\(scheme)://commandbar\">New Tab</a>")
        return buttons.joined()
    }

    /// One mark per kind, drawn in `currentColor` so the stylesheet decides
    /// whether it is ink or §8.1's danger — there is no colour in this file
    /// either.
    ///
    /// A glyph per kind, not one for all of them. Every kind used to wear the
    /// same exclamation in a circle, which says nothing over and over. These
    /// are the distinctions the sentence under them already makes: a network
    /// that is not there, a name that did not resolve, a certificate that did
    /// not check out, a request Luna stopped, a site with no encryption to
    /// offer, and an address of Luna's own with nothing written at it. The
    /// generic kind keeps the circle, because "something went wrong" is all
    /// that page knows.
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
        // A sheet with its corner turned and one rule across it. Every other
        // mark here says something went wrong; this one says there is nothing
        // written at this address.
        case .notFound:
            """
            <path d="M6.5 3.2h6.8l4.2 4.2v13.4H6.5z"/><path d="M13.3 3.2v4.2h4.2"/>\
            <path d="M9.6 14.4h4.8"/>
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
        case .notFound:
            ("No such page", "Luna has no page at this address.")
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
