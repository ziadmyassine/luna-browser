import Foundation
import Testing
import WebKit
@testable import BrowserKit

@Suite("Internal pages (§4.4, §4.5)")
@MainActor
struct InternalPagesTests {

    // MARK: - Routing

    @Test func routesEveryPage() {
        #expect(InternalPages.route(URL(string: "luna://history")!) == .page(.history))
        #expect(InternalPages.route(URL(string: "luna://favicon/apple.com")!) == .favicon(host: "apple.com"))
        // Case in the host must not change the route — WebKit lower-cases it,
        // but a URL Luna builds itself may not have been through WebKit yet.
        #expect(InternalPages.route(URL(string: "luna://History")!) == .page(.history))
    }

    /// The address the History page had before it took the name the user reads.
    /// A bookmark or a closed tab still holding it must not stop resolving.
    @Test func theAddressTheHistoryPageUsedToHaveStillLandsOnIt() {
        #expect(InternalPages.route(URL(string: "luna://archive")!) == .page(.history))
        #expect(InternalPages.name(for: URL(string: "luna://archive")!) == "History")
    }

    /// §30.19's page is gone and its URL is not quietly still serving it.
    @Test func theNewTabPageIsNotAPageAnyMore() {
        #expect(InternalPages.route(URL(string: "luna://newtab")!) == .notFound)
        #expect(InternalPages.name(for: URL(string: "luna://newtab")!) == nil)
    }

    @Test func routesActions() {
        let id = UUID()
        #expect(InternalPages.route(URL(string: "luna://commandbar")!) == .action(.commandBar))
        #expect(InternalPages.route(URL(string: "luna://restore?tab=\(id.uuidString)")!) == .action(.restore(id)))
        // A URL carrying another URL, ampersand and all — the case
        // `URLComponents.queryItems` quietly splits in two.
        let target = URL(string: "https://example.com/a?q=1&r=2")!
        let retry = URL(string: "luna://retry?" + InternalPages.query([("url", target.absoluteString)]))!
        #expect(InternalPages.route(retry) == .action(.retry(target)))
    }

    @Test func refusesAnythingThatIsNotOurs() {
        #expect(InternalPages.route(URL(string: "https://example.com")!) == .notFound)
        #expect(InternalPages.route(URL(string: "luna://nonsense")!) == .notFound)
        #expect(InternalPages.route(URL(string: "luna://restore?tab=not-a-uuid")!) == .notFound)
        #expect(InternalPages.route(URL(string: "luna://favicon")!) == .notFound)
    }

    /// The gadget this whole indirection exists to close: an error page hands
    /// its buttons a URL an attacker chose, and those buttons are loaded.
    @Test func retryAndProceedRefuseNonWebSchemes() {
        for hostile in ["javascript:alert(1)", "file:///etc/passwd", "luna://archive", "data:text/html,<b>"] {
            let query = InternalPages.query([("url", hostile)])
            #expect(InternalPages.route(URL(string: "luna://retry?" + query)!) == .notFound, "\(hostile)")
            #expect(InternalPages.route(URL(string: "luna://proceed?" + query)!) == .notFound, "\(hostile)")
        }
    }

    // MARK: - Reachability (§4.4 security)

    /// Internal pages must not be reachable from ordinary web content. The only
    /// signal web content cannot forge is the scheme of the document the
    /// navigation came from.
    @Test func webContentCannotReachInternalPages() {
        for hostile in ["https", "http", "file", "data", "blob", "HTTPS"] {
            #expect(!InternalPages.allowsNavigation(fromDocumentScheme: hostile), "\(hostile) got in")
        }
        // Luna's own: no document yet (a tab's first load, a session restore),
        // and one internal page linking to another.
        #expect(InternalPages.allowsNavigation(fromDocumentScheme: nil))
        #expect(InternalPages.allowsNavigation(fromDocumentScheme: "luna"))
        #expect(InternalPages.allowsNavigation(fromDocumentScheme: "about"))
    }

    /// The one-shot token is what lets an error page be routed after a failure
    /// on an `https://` document — and it must not survive being used.
    @Test func theTrustTokenIsSpentOnFirstUse() {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let page = InternalPages.Page.error(InternalPageError(kind: .offline, url: URL(string: "https://a.test")))
        controller.load(page)

        #expect(controller.allowsInternalNavigation(to: page.url, fromDocumentScheme: "https"))
        #expect(!controller.allowsInternalNavigation(to: page.url, fromDocumentScheme: "https"))
    }

    // MARK: - Escaping

    @Test func escapesEverythingItRenders() {
        let payload = "<script>alert(\"x\" & 'y')</script>"
        let escaped = HTML.escape(payload)
        #expect(escaped == "&lt;script&gt;alert(&quot;x&quot; &amp; &#39;y&#39;)&lt;/script&gt;")
        // `&` first, or the replacements escape each other's ampersands.
        #expect(!escaped.contains("&amp;lt;"))
    }

    /// An error page renders an attacker-chosen URL by definition, and a
    /// blocker's `detail` is whatever string Agent A hands over.
    @Test func errorPagesNeverEchoRawURLText() {
        let hostile = URL(string: "https://evil.test/?x=1&y=<2")!
        let html = InternalPages.errorHTML(InternalPageError(kind: .dns, url: hostile, detail: "<b>owned</b>"))

        // The URL text, escaped — never the raw ampersand or angle bracket.
        #expect(html.contains("x=1&amp;y="))
        #expect(!html.contains("x=1&y="))
        #expect(!html.contains("y=<2"))
        #expect(!html.contains("<b>owned"))
        #expect(html.contains("&lt;b&gt;owned"))
        // Still shown, just not as markup.
        #expect(html.contains("evil.test"))
    }

    @Test func historyRowsEscapePageSuppliedTitles() {
        InternalPages.content = {
            InternalPageContent(archived: [
                .init(
                    id: UUID(),
                    title: "</a><img src=x onerror=alert(1)>",
                    url: URL(string: "https://evil.test/\"onmouseover=\"alert(1)")!,
                    archivedAt: Date()
                )
            ])
        }
        defer { InternalPages.content = nil }

        let html = InternalPages.historyHTML()
        // Rendered as text, never as markup — in the row and in the
        // `data-search` attribute the filter script reads.
        #expect(html.contains("&lt;/a&gt;&lt;img src=x onerror=alert(1)&gt;"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("</a><img"))
        #expect(!html.contains("onmouseover="))
    }

    /// A stored `javascript:` URL with a click target is the archive's worst
    /// case, and the only defence is refusing to emit the `href` at all.
    @Test func hrefRefusesNonWebSchemes() {
        #expect(HTML.href(URL(string: "https://example.com/a")!) == "https://example.com/a")
        #expect(HTML.href(URL(string: "javascript:alert(1)")!) == nil)
        #expect(HTML.href(URL(string: "file:///etc/passwd")!) == nil)
    }

    // MARK: - The token→CSS bridge

    /// Half of the bridge's contract, checked from the side that consumes the
    /// variables: nothing in the stylesheet may read a custom property the app's
    /// generator does not promise to define. `InternalPageThemeTests` checks the
    /// other half — that the generator defines all of them.
    @Test func stylesheetOnlyReadsPromisedVariables() {
        let declared = Set(InternalPages.paletteVariables)
        let used = Set(
            InternalPages.stylesheet
                .components(separatedBy: "var(")
                .dropFirst()
                .map { String($0.prefix { $0 != "," && $0 != ")" && $0 != " " }) }
                // `--fav` is set inline per element by the favicon markup, not
                // by the palette; only the palette's own names are the contract.
                .filter { $0.hasPrefix("--luna-") }
        )
        #expect(used.subtracting(declared).isEmpty, "stylesheet reads undeclared: \(used.subtracting(declared))")
        #expect(declared.subtracting(used).isEmpty, "declared but never read: \(declared.subtracting(used))")
    }

    /// §8.1: no colour or absolute length value outside `Design/`. A second
    /// palette in the page templates is worse than no palette — it looks right
    /// on the day it is written and drifts silently ever after.
    @Test func stylesheetCarriesNoLiterals() {
        let css = InternalPages.stylesheet
        #expect(!css.contains("#"), "hex colour in the stylesheet")
        for function in ["rgb(", "rgba(", "hsl(", "color("] {
            #expect(!css.contains(function), "\(function) in the stylesheet")
        }
        let lengths = try? NSRegularExpression(pattern: "[0-9]\\s*(px|pt|rem|em)\\b")
        let range = NSRange(css.startIndex..., in: css)
        #expect(lengths?.firstMatch(in: css, range: range) == nil, "absolute length in the stylesheet")
    }

    // MARK: - Pages

    @Test func everyErrorKindRendersAnAction() {
        let target = URL(string: "https://example.com")!
        for kind in InternalPageError.Kind.allCases {
            let error = InternalPageError(kind: kind, url: target)
            let html = InternalPages.errorHTML(error)
            let expected: String
            if error.offersBypass {
                expected = "luna://proceed"
            } else if error.offersRetry {
                expected = "luna://retry"
            } else {
                expected = "luna://commandbar"
            }
            #expect(html.contains(expected), "\(kind) offers no way forward")
        }
    }

    /// A `luna://` address with no page behind it gets §4.5's "can't find that"
    /// page rather than "this page didn't load" — nothing failed on the way to
    /// it — and Try Again is left off, because `luna://` never went near the
    /// network and the address will be just as empty next time.
    @Test func anAddressWithNoPageBehindItDoesNotOfferToTryAgain() {
        let error = InternalPageError(kind: .dns, url: URL(string: "luna://nosuchthing")!)
        #expect(!error.offersRetry)
        let html = InternalPages.errorHTML(error)
        // Escaped on the way into the DOM, so match the half without the apostrophe.
        #expect(html.contains("find that site"))
        #expect(!html.contains("luna://retry"))
        #expect(html.contains("luna://commandbar"))
        // A real lookup failure still offers it.
        #expect(InternalPageError(kind: .dns, url: URL(string: "https://a.test/")!).offersRetry)
    }

    /// The other button on an error page. §30.19's New Tab page used to be
    /// where it went; with that gone it asks for the Command Bar, because a
    /// page that cannot load is not somewhere to leave somebody standing.
    @Test func anErrorPageOffersTheCommandBarAndNotAPageThatIsGone() {
        let html = InternalPages.errorHTML(InternalPageError(kind: .generic, url: nil))
        #expect(html.contains("luna://commandbar"))
        #expect(!html.contains("luna://newtab"))
    }

    @Test func mapsWebKitFailuresToTheFourPages() {
        let cases: [(Int, InternalPageError.Kind)] = [
            (NSURLErrorNotConnectedToInternet, .offline),
            (NSURLErrorCannotFindHost, .dns),
            (NSURLErrorServerCertificateUntrusted, .tls),
            // Resolved and answered, just refused — telling the user their
            // internet is down would be a lie.
            (NSURLErrorCannotConnectToHost, .generic)
        ]
        for (code, expected) in cases {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            #expect(InternalPageError.kind(for: error) == expected, "code \(code)")
        }
    }

    /// The round trip the Retry button depends on.
    @Test func errorURLsSurviveTheRoundTrip() {
        let error = InternalPageError(kind: .tls, url: URL(string: "https://a.test/x?y=1&z=2"), detail: "bad date")
        guard case let .page(.error(decoded)) = InternalPages.route(error.pageURL) else {
            Issue.record("error URL did not round-trip")
            return
        }
        #expect(decoded == error)
    }

    // MARK: - Registration

    @Test func theSchemeIsRegisteredCentrally() {
        let configuration = WebViewFactory.makeConfiguration(dataStore: .nonPersistent())
        #expect(configuration.urlSchemeHandler(forURLScheme: InternalPages.scheme) != nil)
        // The popup path must not re-register: `setURLSchemeHandler` raises for a
        // scheme that already has one, and a popup carries the opener's config.
        let popup = WebViewFactory.makeWebView(configuration: configuration)
        #expect(popup.configuration.urlSchemeHandler(forURLScheme: InternalPages.scheme) != nil)
    }
}
