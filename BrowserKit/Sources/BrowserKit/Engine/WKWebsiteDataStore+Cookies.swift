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
}
