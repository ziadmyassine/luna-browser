import Foundation
import WebKit

// Adapted from Search's ExtensionOffscreen.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// `chrome.offscreen`: a page with a DOM for a worker that has none — to read
/// the clipboard, parse HTML, play a sound. Owned by the extension, never a
/// tab: WebKit is told of it as a tab so its frames' content scripts can name
/// it, but it stands in no window and extensions never hear of it coming or
/// going. One per extension per Space, as Chrome allows one per extension.
@MainActor
final class ExtensionOffscreen: NSObject, WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab {

    struct Refused: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    /// A first page that has not loaded after this long is given up on.
    static let loadTimeout: Duration = .seconds(30)
    /// Replies kept for relays that several pages hear at once.
    static let repliesKept = 128

    let extensionID: String
    private let extensionContext: WKWebExtensionContext
    let url: URL
    private let contextID = UUID().uuidString
    private let documentID = UUID().uuidString
    private let web: WKWebView
    private let onClose: (ExtensionOffscreen) -> Void
    private var loading: CheckedContinuation<Void, any Error>?
    private var deadline: Task<Void, Never>?
    private var closed = false
    private(set) var isReady = false
    private var readiness: [CheckedContinuation<Void, any Error>] = []
    /// WebKit's number for the page as a tab, which its frames' messages carry.
    private var tabID: Int?

    private struct Delivery {
        var reply: Result<Reply, any Error>?
        var waiters: [CheckedContinuation<Reply, any Error>]
    }

    /// A page's reply, which is JSON and so safe to hand across threads.
    struct Reply: @unchecked Sendable { let value: Any }

    private var deliveries: [String: Delivery] = [:]
    private var deliveryOrder: [String] = []

    /// Loads `path`, one of the extension's own pages, and returns once it has.
    static func create(
        _ path: String,
        for context: WKWebExtensionContext,
        onClose: @escaping (ExtensionOffscreen) -> Void
    ) throws -> ExtensionOffscreen {
        let base = context.baseURL
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host() == base.host(), url.user() == nil, url.password() == nil,
              let configuration = context.webViewConfiguration,
              let preferences = configuration.preferences.copy() as? WKPreferences
        else { throw Refused(why: "The offscreen document must belong to this extension.") }
        // This page has no window by design. Its DOM and message replies keep
        // working, with WebKit's background throttling still in place.
        preferences.inactiveSchedulingPolicy = .throttle
        configuration.preferences = preferences
        let document = ExtensionOffscreen(context: context, url: url, configuration: configuration, onClose: onClose)
        context.didOpenTab(document)
        return document
    }

    private init(
        context: WKWebExtensionContext,
        url: URL,
        configuration: WKWebViewConfiguration,
        onClose: @escaping (ExtensionOffscreen) -> Void
    ) {
        extensionContext = context
        extensionID = context.uniqueIdentifier
        self.url = url
        self.onClose = onClose
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: Self.loadTimeout) } catch { return }
                self?.close(because: Refused(why: "The offscreen document did not finish loading."))
            }
            web.load(URLRequest(url: url))
        }
    }

    func close(because error: any Error) {
        guard !closed else { return }
        closed = true
        extensionContext.didCloseTab(self, windowIsClosing: false)
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.stopLoading()
        let waiters = deliveries.values.flatMap(\.waiters)
        deliveries.removeAll()
        deliveryOrder.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
        finish(.failure(error))
        onClose(self)
    }

    private func whenReady() async throws {
        if isReady { return }
        guard !closed else { throw Refused(why: "The offscreen document was closed.") }
        try await withCheckedThrowingContinuation { readiness.append($0) }
    }

    private func finish(_ result: Result<Void, any Error>) {
        deadline?.cancel()
        deadline = nil
        let waiting = readiness
        readiness = []
        for waiter in waiting { waiter.resume(with: result) }
        let continuation = loading
        loading = nil
        continuation?.resume(with: result)
    }

    // MARK: - Messages from its own frames

    /// WebKit brings none of a frame's messages to the page around it, so the
    /// shim relays them through another of the extension's contexts to here.
    /// Only a frame of this document, while it is where it was made, is heard.
    func send(_ message: Any, sender: [String: Any], token: String) async throws -> Any {
        guard !token.isEmpty, token.count <= 128 else { return ["handled": false] }
        // Its own frames load with it and speak before it has finished: they
        // wait for it, as in Chrome, rather than go unheard.
        guard (try? await whenReady()) != nil, !closed,
              let frame = sender["frameId"] as? Int, frame > 0,
              let tab = sender["tab"] as? [String: Any], let tabID, tab["id"] as? Int == tabID,
              let at = web.url, at.scheme == url.scheme, at.host() == url.host(),
              tab["url"] as? String == at.absoluteString
        else { return ["handled": false] }
        nonisolated(unsafe) let message = message
        let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, any Error>) in
            // A worker and several pages may hear the same relay; they share
            // one delivery and one reply, and its side effects happen once.
            if var existing = deliveries[token] {
                if let reply = existing.reply { return continuation.resume(with: reply) }
                existing.waiters.append(continuation)
                deliveries[token] = existing
                return
            }
            deliveries[token] = Delivery(waiters: [continuation])
            web.callAsyncJavaScript(
                "return await globalThis.__lunaOffscreenDispatch(message, sender);",
                arguments: ["message": message, "sender": sender], in: nil, in: .page
            ) { [weak self] result in
                nonisolated(unsafe) let result = result
                MainActor.assumeIsolated { self?.replied(to: token, with: result.map { Reply(value: $0) }) }
            }
        }
        return reply.value
    }

    private func replied(to token: String, with result: Result<Reply, any Error>) {
        guard let pending = deliveries[token], pending.reply == nil else { return }
        deliveries[token] = Delivery(reply: result, waiters: [])
        deliveryOrder.append(token)
        if deliveryOrder.count > Self.repliesKept { deliveries[deliveryOrder.removeFirst()] = nil }
        for waiter in pending.waiters { waiter.resume(with: result) }
    }

    /// It, as `runtime.getContexts` lists it, if it matches `filter`.
    func context(matching filter: [String: Any]) -> [String: Any]? {
        guard isReady else { return nil }
        let origin = "\(url.scheme ?? "")://\(url.host() ?? "")"
        let value: [String: Any] = [
            "contextId": contextID, "contextType": "OFFSCREEN_DOCUMENT", "documentId": documentID,
            "documentUrl": url.absoluteString, "documentOrigin": origin, "frameId": 0, "tabId": -1, "windowId": -1,
            "incognito": false
        ]
        let fields = ["contextIds": "contextId", "contextTypes": "contextType", "documentIds": "documentId",
                      "documentOrigins": "documentOrigin", "documentUrls": "documentUrl", "frameIds": "frameId",
                      "tabIds": "tabId", "windowIds": "windowId"]
        for (plural, singular) in fields {
            guard let asked = filter[plural] else { continue }
            guard let choices = asked as? NSArray, let actual = value[singular], choices.contains(actual) else { return nil }
        }
        if filter["incognito"] as? Bool == true { return nil }
        return value
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, !isReady else { return }
        // WebKit's own getCurrent, not the shim's, which hides a tab with no
        // place in a window: the id tells this page from a visible tab at the
        // same address, and from an earlier document.
        web.callAsyncJavaScript(
            "return (await Object.getPrototypeOf(chrome.tabs).getCurrent.call(chrome.tabs)).id;",
            in: nil, in: .page
        ) { [weak self] result in
            nonisolated(unsafe) let result = result
            MainActor.assumeIsolated { self?.identified(by: result) }
        }
    }

    private func identified(by result: Result<Any, any Error>) {
        guard !closed else { return }
        switch result {
        case .success(let value):
            guard let id = value as? Int else { return close(because: Refused(why: "The offscreen document has no page identifier.")) }
            tabID = id
            isReady = true
            finish(.success(()))
        case .failure(let error):
            close(because: error)
        }
    }

    /// The document itself stays on the extension's own pages, as Chrome keeps
    /// it: a site loaded in its place would run hidden, for as long as it
    /// liked, with the extension's configuration. Its frames may go anywhere —
    /// reading sites in them is what it is for. Nothing is downloaded from it.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload { return decisionHandler(.cancel) }
        guard navigationAction.targetFrame?.isMainFrame != false else { return decisionHandler(.allow) }
        let target = navigationAction.request.url
        decisionHandler(target?.scheme == url.scheme && target?.host() == url.host() ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    // Only its first page failing ends it: once it is there, a later
    // navigation that fails leaves it where it was.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if !isReady { close(because: error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if !isReady { close(because: error) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        close(because: Refused(why: "The offscreen document's web process exited."))
    }

    // MARK: - WKUIDelegate

    /// No camera or microphone for a page nobody can see: WebKit would
    /// otherwise put up its own question for a page with no window.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    // MARK: - WKWebExtensionTab

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { nil }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { web }
    func title(for context: WKWebExtensionContext) -> String? { web.title }
    func url(for context: WKWebExtensionContext) -> URL? { web.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !web.isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { false }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        close(because: Refused(why: "The offscreen document was closed."))
        completionHandler(nil)
    }
}
