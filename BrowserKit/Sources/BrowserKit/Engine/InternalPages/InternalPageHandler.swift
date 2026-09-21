import Foundation
import WebKit

/// Serves `luna://` (§4.4). Registered once, centrally, in
/// `WebViewFactory.makeConfiguration`.
///
/// Verified against `WKURLSchemeTask.h` (MacOSX26.5.sdk), because the
/// contract is all exceptions:
/// - `didReceiveResponse` (Swift: `didReceive(_:)`) must be called at least
///   once per task, before any
///   data and before `didFinish`. Data before a response, a second response
///   after completion, or any callback after `didFinish`/`didFailWithError`
///   each raise an Objective-C exception, which is a crash and not a throw.
/// - Failing to call `didFinish` raises nothing at all — that is what makes
///   it dangerous. The resource simply never completes: a main-frame navigation
///   spins forever, `didFinish` never reaches the navigation delegate, and the
///   tab is wedged with no error to show. Every path below therefore ends in
///   exactly one of `didFinish` or `didFailWithError`.
/// - `stop(_:)`: "After your app is told to stop loading data for a URL scheme
///   handler task it must not perform any callbacks for that task", and one
///   made anyway raises an exception.
///
/// Which is why this handler is entirely synchronous. Everything it serves is
/// either a string it builds in-process or bytes already in `FaviconService`'s
/// memory cache, so the whole response is delivered inside `start(_:)`. Both
/// protocol methods are `WK_SWIFT_UI_ACTOR`, so WebKit cannot interleave a
/// `stop(_:)` with a `start(_:)` that has not returned — there is no window in
/// which a stopped task could receive a callback. `stop(_:)` is a no-op because
/// of that, not by omission; anything asynchronous added here has to bring the
/// cancellation set with it.
@MainActor
final class InternalPageHandler: NSObject, WKURLSchemeHandler {

    /// Stateless, so one instance serves every web view.
    static let shared = InternalPageHandler()

    /// `default-src 'none'` and `frame-ancestors 'none'` are the engine-level
    /// half of §4.4's "not reachable or scriptable from ordinary web content":
    /// the navigation policy in `TabController` refuses the navigation, and this
    /// refuses the framing even if the policy is ever wrong. The two `unsafe-inline`
    /// grants are for this page's own `<style>`/`<script>`, both of which are
    /// built here — there is no external origin in the list to load anything from.
    private static let headers = [
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Content-Security-Policy": [
            "default-src 'none'",
            "style-src 'unsafe-inline'",
            "script-src 'unsafe-inline'",
            "img-src luna:",
            "form-action 'none'",
            "frame-ancestors 'none'",
            "base-uri 'none'"
        ].joined(separator: "; ")
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url
        switch url.map(InternalPages.route) ?? .notFound {
        case let .page(page):
            respond(urlSchemeTask, html: InternalPages.html(for: page), status: 200)
        case let .favicon(host):
            serveFavicon(urlSchemeTask, host: host)
        case .action, .notFound:
            // An action URL is cancelled by the navigation policy and never
            // reaches here; anything else is a typo or a probe. Both get the
            // styled page rather than WebKit's default, which is the point of §4.5.
            let error = InternalPageError(kind: .generic, url: nil)
            respond(urlSchemeTask, html: InternalPages.errorHTML(error), status: 404)
        }
    }

    /// See the type comment: `start(_:)` completes every task before it returns,
    /// so no task can be alive to stop.
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: - Delivery

    private func respond(_ task: any WKURLSchemeTask, html: String, status: Int) {
        send(task, data: Data(html.utf8), status: status, headers: Self.headers)
    }

    /// Cached bytes only — `FaviconService.favicon(forHost:)` never touches the
    /// network (§4.7). A miss fails the sub-resource, which leaves the page's
    /// monogram showing rather than a broken-image glyph.
    private func serveFavicon(_ task: any WKURLSchemeTask, host: String) {
        guard let png = FaviconService.shared.favicon(forHost: host) else {
            task.didFailWithError(URLError(.resourceUnavailable))
            return
        }
        send(task, data: png, status: 200, headers: [
            "Content-Type": "image/png",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff"
        ])
    }

    private func send(_ task: any WKURLSchemeTask, data: Data, status: Int, headers: [String: String]) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
              )
        else {
            // Unreachable — the task always carries a URL — but the alternative
            // to failing the task is leaving it hanging forever (see above).
            task.didFailWithError(URLError(.badURL))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
