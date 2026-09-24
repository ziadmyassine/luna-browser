import Foundation

//  A tab's half of §4.4 and §4.5: showing one of Luna's own pages, deciding
//  whether a `luna://` navigation is Luna's or a web page's, and performing the
//  links on an internal page that are not navigations.
//
//  Split out of `TabController.swift` rather than added to it: the two stored
//  properties have to live there (Swift extensions cannot add storage) and
//  nothing else does.

extension TabController {

    /// Shows one of Luna's own pages in this tab (§4.4). Navigates to it as a
    /// `luna://` URL — never injects it — so the page's sub-resources load and
    /// the address, the back list and `TabState.url` all stay honest.
    public func load(_ page: InternalPages.Page) {
        load(page.url)
    }

    /// §4.5's styled failure page, in place of WebKit's default.
    ///
    /// This is the seam for both of §17's interstitials, and the only
    /// supported way to put one up:
    ///
    ///     controller.showErrorPage(.blocked, for: url, detail: "EasyPrivacy")
    ///     controller.showErrorPage(.httpsDowngrade, for: url)
    ///
    /// Both render a "Continue Anyway" button; taking it sets `bypassedURL` and
    /// re-navigates, so a blocker has to let that one URL through. `detail` is
    /// escaped on the way into the DOM, so a rule name or a certificate message
    /// can be passed through verbatim.
    public func showErrorPage(_ kind: InternalPageError.Kind, for url: URL?, detail: String? = nil) {
        load(.error(InternalPageError(kind: kind, url: url, detail: detail)))
    }

    /// Whether a `luna://` navigation may proceed. Web content must not be able
    /// to reach an internal page (§4.4): the archive's restore rows would
    /// otherwise be a clickjacking target inside an iframe, and every internal
    /// page would be a navigation any site could force.
    func allowsInternalNavigation(to url: URL, fromDocumentScheme sourceScheme: String?) -> Bool {
        if expectedInternalLoad == url {
            expectedInternalLoad = nil
            return true
        }
        return InternalPages.allowsNavigation(fromDocumentScheme: sourceScheme)
    }

    /// Performs a link on an internal page that is not a navigation. Called only
    /// after `allowsInternalNavigation` has agreed the click came from Luna.
    func perform(_ action: InternalPages.Action) {
        switch action {
        case let .retry(url):
            bypassedURL = nil
            load(url)
        case let .proceed(url):
            bypassedURL = url
            // §17.6's "Continue Anyway" is a standing answer, not a one-shot: a user
            // who accepted http for this host once should not be asked on every link.
            // The blocked-page bypass stays one-shot — that is what `bypassedURL` is.
            if url.scheme?.lowercased() == "http", let host = url.host() {
                ContentBlocker.shared.allowInsecure(host: host, in: sitePermissions)
            }
            load(url)
        case .commandBar, .restore:
            // Needs the Command Bar or the tab list, neither of which exists
            // here. Silently nothing if the app never installed a handler,
            // which is the honest failure for a link rather than a crash.
            InternalPages.onAction?(action, id)
        }
    }
}
