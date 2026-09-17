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
        return document(title: "New Tab", bodyClass: "", body: body)
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

    // MARK: - Archive (§6.4)

    @MainActor
    static func archiveHTML() -> String {
        let archived = content?().archived ?? []
        let rows = archived.map(archiveRow).joined()
        let list = rows.isEmpty
            ? "<p class=\"empty\">Nothing archived yet.</p>"
            : "<ul class=\"rows\">\(rows)</ul>"
        let body = """
        <main class="archive">
        <h1>Archive</h1>
        <input class="search" id="q" type="search" placeholder="Search archive"\
         aria-label="Search archive" autofocus>
        \(list)
        <p class="empty" id="none" hidden>No matches.</p>
        </main>
        """
        return document(title: "Archive", bodyClass: "", body: body, script: archiveScript)
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
        <span class="go">Restore</span></a></li>
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

    @MainActor
    static func errorHTML(_ error: InternalPageError) -> String {
        let copy = Self.copy(for: error.kind)
        let target = error.url.map { "<p class=\"target\">\(HTML.escape($0.absoluteString))</p>" } ?? ""
        let detail = error.detail.map { "<p class=\"target\">\(HTML.escape($0))</p>" } ?? ""
        let body = """
        <main class="error \(error.kind.rawValue)">
        <div class="card plate">
        \(mark)
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
            buttons.append("<a class=\"button plate\" href=\"\(HTML.action(host, url: url))\">\(label)</a>")
        }
        buttons.append("<a class=\"button plate\" href=\"\(scheme)://newtab\">New Tab</a>")
        return buttons.joined()
    }

    /// One mark for every kind, tinted by `--luna-danger` for the two that
    /// warn and by `--luna-text-tertiary` for the rest (the stylesheet decides).
    /// `currentColor` rather than a fill value: there is no colour in this file.
    private static let mark = """
    <svg class="mark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"\
     stroke-linecap="round" aria-hidden="true">\
    <circle cx="12" cy="12" r="9"/><path d="M12 7v6"/><path d="M12 16.5v.01"/></svg>
    """

    private static func copy(for kind: InternalPageError.Kind) -> (title: String, message: String) {
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
