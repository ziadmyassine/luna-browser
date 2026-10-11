import WebKit

extension WKWebsiteDataStore {

    /// Every cookie in this jar, its cookie file read in first.
    ///
    /// A store WebKit has not yet used answers `httpCookieStore.allCookies()`
    /// with `[]` although its cookies are on disk: the file is loaded by the
    /// first page in the store or by a `dataRecords(ofTypes:)` call, and not by
    /// `allCookies()` itself (measured 2026-10-11, macOS 26). A Space no tab has
    /// loaded in since launch has such a jar, so read cookies through this.
    public func loadedCookies() async -> [HTTPCookie] {
        _ = await dataRecords(ofTypes: [WKWebsiteDataTypeCookies])
        return await httpCookieStore.allCookies()
    }

    /// The cookies of this jar a request to `url` carries, for a fetch made
    /// outside a web view. Foundation's own jar does the matching — domain,
    /// host-only, path, `Secure` and expiry (RFC 6265 §5.4) — because a
    /// hand-written `host.hasSuffix(domain)` sent `example.com`'s logins to
    /// `badexample.com`. An ephemeral configuration's jar is a fresh one in
    /// memory, so nothing is shared or written.
    public func cookies(for url: URL) async -> [HTTPCookie] {
        guard let matcher = URLSessionConfiguration.ephemeral.httpCookieStorage else { return [] }
        for cookie in await loadedCookies() { matcher.setCookie(cookie) }
        return matcher.cookies(for: url) ?? []
    }
}
