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
        publishState()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishState()
        // Cheap, and it is the only copy §19.3 can recover from once the process dies.
        savedInteractionState = webView.interactionState as? Data
        fallbackURL = webView.url ?? fallbackURL
        refreshFavicon()
    }

    public func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        publishState()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        reportNavigationFailure(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverFromDeadProcess()
    }

    private func reportNavigationFailure(_ error: Error) {
        publishState()
        // `.cancelled` is what a policy decision of `.cancel` and every download handoff
        // look like from here. Surfacing it would put an error page over a working
        // download.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        // "Frame load interrupted": what a `.download` policy decision looks like from
        // here. Modern `WKError` has no case for it — the constant only exists as the
        // deprecated `WebKitErrorFrameLoadInterruptedByPolicyChange = 102` in legacy
        // `WebKitErrors.h`, so it is matched by domain and code rather than by importing
        // a symbol that warns.
        guard !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else { return }
        delegate?.tabController(self, didFailWith: error)
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
