import Foundation

/// §4.5's styled failure page, as a value: what went wrong, where, and the one
/// thing the user can do about it.
///
/// A value rather than a rendered string so the mapping from `NSError` is a
/// pure function with a test, and so Agent A's blocked / HTTPS-downgrade
/// interstitials are the *same* page with a different `kind` rather than a
/// second implementation.
public struct InternalPageError: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// No route to the network at all.
        case offline
        /// The host does not resolve.
        case dns
        /// The certificate chain failed.
        case tls
        /// Luna's own content blocking stopped it (§17). Agent A's seam.
        case blocked
        /// Luna refused to fall back to `http://` (§17). Agent A's seam.
        case httpsDowngrade
        /// Everything WebKit failed at that has no page of its own.
        case generic
    }

    public var kind: Kind
    /// The URL that failed. Rendered, so it is escaped on the way into the DOM
    /// and re-validated on the way back out of a button.
    public var url: URL?
    /// One line of specifics — a certificate message, the blocklist that
    /// matched. Optional: most kinds read better without one.
    public var detail: String?

    public init(kind: Kind, url: URL? = nil, detail: String? = nil) {
        self.kind = kind
        self.url = url
        self.detail = detail
    }

    init(query: (String) -> String?) {
        kind = Kind(rawValue: query("kind") ?? "") ?? .generic
        url = InternalPages.webURL(query("url"))
        let detail = query("detail")
        self.detail = (detail?.isEmpty ?? true) ? nil : detail
    }

    /// The `luna://error?…` URL this page is navigated to (§4.4).
    public var pageURL: URL {
        var items = [(name: "kind", value: kind.rawValue)]
        if let url { items.append((name: "url", value: url.absoluteString)) }
        if let detail { items.append((name: "detail", value: detail)) }
        let query = InternalPages.query(items)
        return URL(string: "\(InternalPages.scheme)://error?\(query)")
            ?? URL(string: "\(InternalPages.scheme)://error")!
    }

    /// Whether the primary button re-navigates (`Try Again`) or asks to be let
    /// past (`Continue Anyway`). A blocked page's retry would only be blocked
    /// again, and a TLS failure has nothing to bypass without the §17
    /// authentication-challenge work that does not exist yet.
    public var offersBypass: Bool {
        kind == .blocked || kind == .httpsDowngrade
    }

    /// §4.5's four cases, from what WebKit actually reports.
    ///
    /// `NSURLErrorCannotConnectToHost` is deliberately **not** `offline`: the
    /// name resolved and the machine answered, it just refused the port, and
    /// telling the user their internet is down would be a lie.
    public static func kind(for error: Error) -> Kind {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .generic }
        switch error.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return .offline
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dns
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired,
             NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return .tls
        default:
            return .generic
        }
    }
}
