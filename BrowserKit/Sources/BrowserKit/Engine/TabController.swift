import Foundation
import WebKit

/// One tab's engine: owns at most one `WKWebView` and is every delegate WebKit asks for
/// (§4.2). A hibernated tab owns **nothing** — no view, no WebContent process — which is
/// the whole of §19.2's memory strategy, not a tuning knob.
@MainActor
public final class TabController: NSObject {

    public let id: UUID
    public private(set) var state: TabState
    public weak var delegate: TabControllerDelegate?

    /// nil while hibernated.
    public private(set) var webView: WKWebView?

    private let dataStore: WKWebsiteDataStore

    /// The last session we managed to capture. Kept **outside** the web view on purpose:
    /// once the WebContent process is gone `webView.interactionState` reads back nil, so
    /// crash recovery (§19.3) has nothing else to restore from.
    var savedInteractionState: Data?

    /// URL to fall back to when `savedInteractionState` is missing or unusable.
    var fallbackURL: URL?

    private var observations: [NSKeyValueObservation] = []

    // Not `private`: the delegate conformances live in TabController+Delegates.swift.
    /// Frames currently making sound, keyed by frame URL. A tab is audible if any of
    /// them is — an embedded player lives in a subframe.
    var audibleFrames: Set<String> = []

    /// §19.3 guard: a page that kills its own WebContent process on load would otherwise
    /// make us rebuild it forever.
    private var recoveries: [Date] = []
    private static let recoveryLimit = 3
    private static let recoveryWindow: TimeInterval = 60

    static let mediaMessageName = "lunaMedia"

    private let messageRelay = ScriptMessageRelay()

    public init(id: UUID, dataStore: WKWebsiteDataStore) {
        self.id = id
        self.dataStore = dataStore
        state = TabState()
        super.init()
        messageRelay.owner = self
    }

    // MARK: - Lifecycle

    /// Builds the web view if this tab is cold, restoring the saved session into it.
    public func activate() {
        ensureWebView(restoringSession: true)
    }

    /// Builds this tab's web view from a configuration handed over by
    /// `createWebViewWith` (§4.2). WebKit requires the popup to use **that exact**
    /// configuration, or `window.opener` and the whole `target="_blank"` relationship
    /// break — and the caller must not load anything into it: WebKit performs the
    /// pending navigation itself once the view is returned.
    @discardableResult
    public func activate(with configuration: WKWebViewConfiguration) -> WKWebView {
        if let webView { return webView }
        let webView = WebViewFactory.makeWebView(configuration: configuration)
        attach(webView)
        publishState()
        return webView
    }

    /// Captures the session, tears the view down and releases the WebContent process.
    /// After this the tab holds a `TabState` and a `Data` blob and nothing else.
    public func hibernate() {
        guard webView != nil else { return }
        savedInteractionState = captureInteractionState()
        detach()
        publishState()
    }

    /// - Parameter fallbackURL: loaded when `interactionState` is nil or WebKit refuses
    ///   it. A restored tab whose blob is stale would otherwise wake up blank.
    public func restore(interactionState: Data?, fallbackURL: URL? = nil) {
        savedInteractionState = interactionState
        if let fallbackURL {
            self.fallbackURL = fallbackURL
            if state.url == nil { state.url = fallbackURL }
        }
        if let webView, let interactionState {
            webView.interactionState = interactionState
            publishState()
        }
    }

    public func captureInteractionState() -> Data? {
        (webView?.interactionState as? Data) ?? savedInteractionState
    }

    // MARK: - Navigation

    public func load(_ url: URL) {
        fallbackURL = url
        // An explicit navigation replaces the stored session; restoring it first would
        // pay for a full page load we are about to throw away.
        savedInteractionState = nil
        // Only Luna's own code reaches this method, so a `luna://` URL arriving here
        // is trusted by construction (§4.4). Web content's route in is
        // `decidePolicyFor`, which has no such token and is refused there.
        if url.scheme?.lowercased() == InternalPages.scheme { expectedInternalLoad = url }
        let webView = ensureWebView(restoringSession: false)
        Self.load(url, into: webView)
    }

    /// `load(URLRequest)` on a `file:` URL fails silently — WebKit needs the explicit
    /// read-access grant for the enclosing directory or every subresource 404s.
    static func load(_ url: URL, into webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - Internal pages (§4.4, §4.5)
    //
    // Only the stored state is here — a Swift extension cannot add any. The
    // behaviour is in `InternalPages/TabController+InternalPages.swift`.

    /// The one `luna://` URL this tab may navigate to next, because Luna asked
    /// for it. Consumed on the matching decision.
    var expectedInternalLoad: URL?

    /// The URL the user chose from an interstitial's "Continue Anyway", live for
    /// that one navigation and cleared when it commits. **§17's blocking must
    /// let this URL through**, or the button does nothing. `internal(set)`
    /// because `private` is file-scoped and the setter is next door; nothing
    /// outside `BrowserKit` can write it.
    public internal(set) var bypassedURL: URL?

    public func reload() { webView?.reload() }
    public func stop() { webView?.stopLoading() }
    public func goBack() { webView?.goBack() }
    public func goForward() { webView?.goForward() }

    /// §19.3 heartbeat — call on window/app activation. A WebContent process suspended
    /// in the background can fail to resume and leaves a dead white view with no
    /// termination callback; the only honest probe is asking it to run something.
    public func checkProcessHealth() async {
        guard let webView else { return }
        do {
            _ = try await webView.evaluateJavaScript("0")
        } catch let error as NSError
            where error.domain == WKErrorDomain
            && error.code == WKError.Code.webContentProcessTerminated.rawValue {
            recoverFromDeadProcess()
        } catch {
            // Any other failure (JS disabled, a PDF view) is not a dead process.
        }
    }

    // MARK: - Web view plumbing

    @discardableResult
    private func ensureWebView(restoringSession: Bool) -> WKWebView {
        if let webView { return webView }
        let webView = WebViewFactory.makeWebView(dataStore: dataStore)
        attach(webView)
        if restoringSession, let savedInteractionState {
            webView.interactionState = savedInteractionState
        }
        // Covers a fresh tab and a blob WebKit silently refused. Setting
        // `interactionState` drives the navigation itself, so loading as well would
        // fetch the same page twice.
        if webView.url == nil, let url = fallbackURL ?? state.url {
            Self.load(url, into: webView)
        }
        publishState()
        return webView
    }

    private func attach(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let controller = webView.configuration.userContentController
        // Adding a name that is already registered raises `NSInvalidArgumentException`;
        // removing one that is not is a no-op. Always pay the cheap call.
        for name in [Self.mediaMessageName, ContentBlocker.blockedMessageName] {
            controller.removeScriptMessageHandler(forName: name)
            controller.add(messageRelay, name: name)
        }
        for source in [Self.mediaScript, ContentBlocker.blockedCountScript] {
            controller.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )
        }

        // WebKit posts these on the main thread; `assumeIsolated` states that instead of
        // hiding it behind an unchecked conformance.
        let republish: @Sendable (WKWebView, Any) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.publishState() }
        }
        observations = [
            webView.observe(\.url, options: [.new]) { republish($0, $1) },
            webView.observe(\.title, options: [.new]) { republish($0, $1) },
            webView.observe(\.isLoading, options: [.new]) { republish($0, $1) },
            webView.observe(\.estimatedProgress, options: [.new]) { republish($0, $1) },
            webView.observe(\.canGoBack, options: [.new]) { republish($0, $1) },
            webView.observe(\.canGoForward, options: [.new]) { republish($0, $1) },
            webView.observe(\.themeColor, options: [.new]) { republish($0, $1) },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { republish($0, $1) }
        ]
        self.webView = webView
    }

    /// Everything that has to happen before the last reference to the web view goes
    /// away. The user content controller holds its handlers and scripts strongly, so
    /// leaving them registered pins the web view — and with it a WebContent process —
    /// for as long as the configuration lives, which is the opposite of §19.2.
    private func detach() {
        guard let view = webView else { return }
        webView = nil

        for observation in observations { observation.invalidate() }
        observations.removeAll()
        audibleFrames.removeAll()

        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil

        let controller = view.configuration.userContentController
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Self.mediaMessageName)
        controller.removeScriptMessageHandler(forName: ContentBlocker.blockedMessageName)

        // Picture-in-Picture and element fullscreen outlive their web view: without this
        // a hibernated tab leaves a floating video playing with nothing behind it. The
        // closure holds `view` until WebKit is finished with it.
        view.closeAllMediaPresentations { _ = view }
        view.removeFromSuperview()
    }

    func recoverFromDeadProcess() {
        let now = Date()
        recoveries = recoveries.filter { now.timeIntervalSince($0) < Self.recoveryWindow }
        guard recoveries.count < Self.recoveryLimit else {
            // Rebuilding again would just spin. Leave the tab cold and say so.
            detach()
            publishState()
            delegate?.tabController(self, didFailWith: WKError(.webContentProcessTerminated))
            return
        }
        let attempt = recoveries.count
        recoveries.append(now)
        detach()
        publishState()

        // Respawning immediately puts a new WebContent process into the same broken XPC
        // state — after a sleep/wake, launchservicesd needs seconds to come back and an
        // instant rebuild becomes a tight crash loop. Back off a little more each time.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            guard let self else { return }
            self.ensureWebView(restoringSession: true)
            self.delegate?.tabControllerDidRecoverFromProcessTermination(self)
        }
    }

    /// The crash budget is per burst: a tab that works again for a minute starts clean.
    /// Call on `NSWorkspace.didWakeNotification` too — the post-wake XPC window produces
    /// a burst of terminations that says nothing about the page.
    public func resetProcessCrashBudget() {
        recoveries.removeAll()
    }

    // MARK: - State

    /// A new document owns neither the old title nor the old tint, and none of the old
    /// frames are still making noise.
    func resetPerDocumentState() {
        state.title = ""
        state.themeColor = nil
        audibleFrames.removeAll()
        // The interstitial bypass is good for the one navigation it was granted
        // for. Leaving it set would quietly allowlist the site for as long as the
        // tab lives (§4.5).
        bypassedURL = nil
        // §17.4's count is per document, and the page's own counter restarts too.
        ContentBlocker.shared.resetBlockedCount(tab: id)
    }

    func publishState() {
        var next = state
        if let webView {
            next.url = webView.url ?? next.url
            // Keep the last non-empty title: a page's title arrives after its first
            // paint, and `didCommit` clears it so it can never survive a navigation.
            if let title = webView.title, !title.isEmpty { next.title = title }
            next.isLoading = webView.isLoading
            next.progress = webView.estimatedProgress
            next.canGoBack = webView.canGoBack
            next.canGoForward = webView.canGoForward
            next.hasOnlySecureContent = webView.hasOnlySecureContent
            if let themeColor = webView.themeColor {
                next.themeColor = ColorBridge.rgba(from: themeColor.cgColor)
            }
            // The page's own colour behind the page, so over-scroll and the gap before
            // first paint are not a white flash. Assigning the web view's own colour
            // keeps this AppKit-free; nil restores WebKit's default.
            webView.underPageBackgroundColor = webView.themeColor
            next.isPlayingAudio = !audibleFrames.isEmpty
        } else {
            // A cold tab keeps its identity (url, title, tint) and loses everything that
            // only a live process can answer.
            next.isLoading = false
            next.progress = 0
            next.canGoBack = false
            next.canGoForward = false
            next.isPlayingAudio = false
        }
        guard next != state else { return }
        state = next
        delegate?.tabController(self, didChange: next)
    }

    func refreshFavicon() {
        guard let webView, let host = webView.url?.host() else { return }
        Task { [weak self] in
            let png = await FaviconService.shared.fetchFavicon(for: webView, host: host)
            guard let self else { return }
            self.delegate?.tabController(self, didUpdateFavicon: png)
        }
    }

    /// §17.4's count, from `ContentBlocker`'s page script. A heuristic by
    /// necessity: WebKit exposes no blocked-load callback.
    func handleBlockedMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let count = body["count"] as? Int else { return }
        ContentBlocker.shared.setBlockedCount(count, tab: id)
    }

    func handleMediaMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let audible = body["audible"] as? Bool
        else { return }
        let frame = message.frameInfo.isMainFrame
            ? "" : (message.frameInfo.request.url?.absoluteString ?? "subframe")
        if audible { audibleFrames.insert(frame) } else { audibleFrames.remove(frame) }
        publishState()
    }

    /// Reports whether any media element in the frame is *audible* — playing, unmuted
    /// and above zero volume. `requestMediaPlaybackState()` would call a muted autoplay
    /// video "playing" and put a speaker badge on half the sidebar.
    ///
    /// Media events do not bubble, so the listeners are registered in the capture phase;
    /// that is the only way one document-level listener sees every `<video>`.
    private static let mediaScript = """
    (function () {
      var post = function () {
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaMedia;
        if (!h) { return; }
        var audible = false;
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
          var m = media[i];
          if (!m.paused && !m.muted && m.volume > 0) { audible = true; break; }
        }
        h.postMessage({ audible: audible });
      };
      ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied'].forEach(function (name) {
        document.addEventListener(name, post, true);
      });
      post();
    })();
    """
}
