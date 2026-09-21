import Foundation
import WebKit

// MARK: - WKNavigationDelegate (§4.2)

extension TabController: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // §15.2 — an <a download> link, decided before a response ever arrives.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // §4.4 comes first, because `NavigationPolicy.disposition` would hand a
        // `luna://` URL straight to `.display` — which is right for Luna's own
        // navigation and wrong for a page that links to one.
        if url.scheme?.lowercased() == InternalPages.scheme {
            decisionHandler(decideInternalPage(url, navigationAction))
            return
        }
        // §17, main frame only — a sub-frame does not change the site the user is
        // on, and re-scoping the rule lists for one would disable blocking for the
        // whole page.
        if navigationAction.targetFrame?.isMainFrame ?? false {
            ContentBlocker.shared.apply(to: webView.configuration.userContentController, host: url.host())
            // §17.2. The rule lists above are swapped per navigation; the YouTube
            // script has to be too, and for the same reason — "disable blocking here"
            // has to mean here.
            refreshUserScriptsIfNeeded(host: url.host())
            // §17.6. `preferredHTTPSNavigationPolicy` cannot do this: measured, both of
            // its values end an http-only navigation at `about:blank` with `didFinish`
            // and no delegate error, so there is no hook to put an interstitial on.
            // Luna upgrades and cancels itself instead. `bypassedURL` is the user having
            // already said "continue anyway" on the downgrade page.
            if case let .upgrade(upgraded) = ContentBlocker.shared.httpsDecision(for: url),
               url != bypassedURL {
                decisionHandler(.cancel)
                load(upgraded)
                return
            }
        }
        switch NavigationPolicy.disposition(for: url) {
        case .display:
            decisionHandler(.allow)
        case .block:
            decisionHandler(.cancel)
        case .external:
            // Answer WebKit first: policy decisions run in a modal-ish runloop mode and
            // the delegate is about to put UI on screen.
            decisionHandler(.cancel)
            delegate?.tabController(self, wantsToOpenExternally: url)
        }
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // `value(forHTTPHeaderField:)`, not `allHeaderFields[…]` — the latter is a
        // case-sensitive dictionary lookup and servers send `content-disposition`.
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")
        let download = NavigationPolicy.shouldDownload(
            canShowMIMEType: navigationResponse.canShowMIMEType,
            contentDisposition: disposition,
            isForMainFrame: navigationResponse.isForMainFrame
        )
        decisionHandler(download ? .download : .allow)
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        delegate?.tabController(self, didStartDownload: download)
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        delegate?.tabController(self, didStartDownload: download)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        resetPerDocumentState()
        // A new document starts unmuted however the tab is set: `muted` is a property of
        // the media elements, and these are new ones. Re-asserted here rather than at
        // `didFinish` because the audio of an autoplaying page starts long before the
        // load settles (§3.4a).
        reapplyMute()
        publishState()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishState()
        // Cheap, and it is the only copy §19.3 can recover from once the process dies.
        savedInteractionState = webView.interactionState as? Data
        fallbackURL = webView.url ?? fallbackURL
        refreshFavicon()
    }

    /// §14.8's redirect flag starts clean here, and only here.
    ///
    /// The two obvious alternatives are both wrong:
    ///
    ///  · `didCommit` runs after the redirect callback, so clearing there
    ///    would erase the very thing the flag recorded.
    ///  · `decidePolicyFor` runs again for every redirect target — that is
    ///    how a redirect chain is observable at all — so clearing there would
    ///    erase the flag on the hop that set it.
    ///
    /// `didStartProvisionalNavigation` fires once per navigation, before any
    /// redirect in that navigation, which is exactly the boundary wanted.
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        passwords.sawServerRedirect = false
        publishState()
    }

    public func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        // §14.8: "treat a fill into a page reached via a redirect chain as
        // suspicious". Noted, not blocked — a great many real logins redirect
        // through an identity provider, so refusing here would break more
        // sign-ins than it protected. The flag rides along on the offer and the
        // popover says where the password is about to go, which is the one
        // judgement the user can make and Luna cannot.
        passwords.sawServerRedirect = true
        publishState()
    }

    /// §4.5: nothing committed, so WebKit is about to show its own grey default
    /// page. Ours goes there instead.
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard reportNavigationFailure(error) else { return }
        presentErrorPage(for: error, in: webView)
    }

    /// A failure after `didCommit` leaves a partly-rendered page on screen.
    /// Replacing it with an error page would throw away content the user can
    /// already read, so this one only reports.
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        _ = reportNavigationFailure(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverFromDeadProcess()
    }

    /// §4.4's two rules in one place: only Luna may navigate to a `luna://` URL,
    /// and an action URL is performed rather than loaded.
    ///
    /// The trust signal is the source document's scheme, because that is the
    /// one thing web content cannot forge — a link, a form, an iframe and a
    /// `location.href` on `https://evil.example` all report `https` here, while
    /// Luna's own loads either carry the one-shot token or come from another
    /// internal page.
    private func decideInternalPage(
        _ url: URL,
        _ navigationAction: WKNavigationAction
    ) -> WKNavigationActionPolicy {
        let sourceScheme = navigationAction.sourceFrame.request.url?.scheme
        guard allowsInternalNavigation(to: url, fromDocumentScheme: sourceScheme) else { return .cancel }
        guard case let .action(action) = InternalPages.route(url) else { return .allow }
        // Not a document: cancel the navigation and do the thing it stands for.
        perform(action)
        return .cancel
    }

    /// Replaces WebKit's default failure page with §4.5's (§4.4 for the route).
    ///
    /// The failing URL comes from the error rather than from `webView.url`:
    /// nothing committed, so the web view still reports the previous page — or
    /// nothing at all for a tab's first load.
    private func presentErrorPage(for error: Error, in webView: WKWebView) {
        let nsError = error as NSError
        let failing = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? fallbackURL
        // An internal page cannot fail — the handler answers every task — so a
        // `luna://` failure here is something else, and routing to another
        // internal page would be a loop with no exit.
        guard failing?.scheme?.lowercased() != InternalPages.scheme else { return }
        // §17.6: an https failure Luna is itself the reason for. The interstitial
        // offers the http original rather than a retry that would fail identically.
        if let failing, let origin = ContentBlocker.shared.downgradeOrigin(for: failing) {
            showErrorPage(.httpsDowngrade, for: origin)
            return
        }
        let kind = InternalPageError.kind(for: error)
        // Only where our own copy is vague: repeating "you're offline" in
        // smaller type underneath "You're offline" is noise.
        let detail = (kind == .generic || kind == .tls) ? nsError.localizedDescription : nil
        showErrorPage(kind, for: failing, detail: detail)
    }

    /// - Returns: whether this was a real failure, rather than one of the two
    ///   that mean "WebKit handed the navigation somewhere else".
    @discardableResult
    private func reportNavigationFailure(_ error: Error) -> Bool {
        publishState()
        // `.cancelled` is what a policy decision of `.cancel` and every download handoff
        // look like from here. Surfacing it would put an error page over a working
        // download.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return false }
        // "Frame load interrupted": what a `.download` policy decision looks like from
        // here. Modern `WKError` has no case for it — the constant only exists as the
        // deprecated `WebKitErrorFrameLoadInterruptedByPolicyChange = 102` in legacy
        // `WebKitErrors.h`, so it is matched by domain and code rather than by importing
        // a symbol that warns.
        guard !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else { return false }
        delegate?.tabController(self, didFailWith: error)
        return true
    }
}

// MARK: - WKUIDelegate (§4.2)

extension TabController: WKUIDelegate {

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // The URL is nil for `window.open()` with no argument — the page writes into the
        // blank document afterwards. Returning nil there is exactly the case that makes
        // `window.open` look broken, so the tab is created regardless.
        delegate?.tabController(self, wantsNewTabFor: navigationAction.request.url, configuration: configuration)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let delegate else { completionHandler(); return }
        Task { await delegate.tabController(self, runJavaScriptAlert: message); completionHandler() }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard let delegate else { completionHandler(false); return }
        Task { completionHandler(await delegate.tabController(self, runJavaScriptConfirm: message)) }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let delegate else { completionHandler(nil); return }
        Task {
            completionHandler(
                await delegate.tabController(self, runJavaScriptPrompt: prompt, defaultText: defaultText)
            )
        }
    }

    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let delegate else { decisionHandler(.deny); return }
        // §18.8: this path is why the private `mediaDevicesEnabled` preference is never
        // set — it works without it, and setting it crashes the WebContent process.
        let url = URL(string: "\(origin.protocol)://\(origin.host)")
        Task { decisionHandler(await delegate.tabController(self, requestMediaCapture: type, origin: url)) }
    }
}
