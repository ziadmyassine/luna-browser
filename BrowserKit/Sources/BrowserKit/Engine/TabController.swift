import Foundation
import WebKit

/// One tab's engine: owns at most one `WKWebView` and is every delegate WebKit asks for
/// (§4.2). A hibernated tab owns nothing — no view, no WebContent process — which is
/// the whole of §19.2's memory strategy, not a tuning knob.
@MainActor
public final class TabController: NSObject {

    public let id: UUID
    public private(set) var state: TabState
    public weak var delegate: TabControllerDelegate?

    /// nil while hibernated.
    public private(set) var webView: WKWebView?

    private let dataStore: WKWebsiteDataStore
    /// A private window's own (§5.6), so its icons never reach the shared cache.
    public let favicons: FaviconService

    /// The Space's extension controller, put on every web view this tab builds
    /// (§16.1). Nil in a private window, where extensions do not run.
    private let webExtensionController: WKWebExtensionController?

    /// The last session we managed to capture. Kept outside the web view on purpose:
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

    /// §3.4a's mute. The answer; the page script that enforces it is in
    /// `TabController+Mute.swift`, which is also the only thing that writes this.
    /// Not `private`, for the same reason `audibleFrames` is not: a Swift extension
    /// cannot carry storage, so the flag lives here and the behaviour lives next door.
    var mutedStorage = false

    /// §19.3 guard: a page that kills its own WebContent process on load would otherwise
    /// make us rebuild it forever.
    private var recoveries: [Date] = []

    /// Whether §17.2's YouTube script is in the current script set — see
    /// `refreshUserScriptsIfNeeded(host:)`, which is the only thing that reads it.
    private var youTubeScriptInstalled = false
    private static let recoveryLimit = 3
    private static let recoveryWindow: TimeInterval = 60

    static let mediaMessageName = "lunaMedia"

    /// The main frame's scroll offset, whenever it changes — see
    /// `TabController+Scroll.swift`. Nil unless something is drawing chrome that
    /// depends on it. The page script is injected either way: one listener
    /// posting a number nobody reads costs less than re-injecting scripts when a
    /// setting changes.
    public var onScroll: ((Double) -> Void)?

    /// The colour under the top edge of the visible page, as the page itself
    /// reports it — see `TabController+Scroll.swift`. Nil means "no single
    /// colour up there", and the document's own background is then the answer.
    ///
    /// Stored as well as published because it belongs to the tab: a tab
    /// selected again is still scrolled where it was, and the chrome matching it
    /// should not wait for the next drag to find out. The setter lives next
    /// door, with the script that feeds it.
    public internal(set) var topColour: RGBA?

    /// `topColour` whenever it changes — and only then. The page posts a sample
    /// on every frame of a drag; nearly all of them say what the last one did.
    public var onTopColour: ((RGBA?) -> Void)?

    /// How far through the page the reader is, 0...1, or nil for a page with
    /// nothing below the fold — see `TabController+Scroll.swift`.
    public internal(set) var scrollProgress: Double?

    /// `scrollProgress` whenever it changes.
    public var onScrollProgress: ((Double?) -> Void)?

    private let messageRelay = ScriptMessageRelay()

    /// §14's password state for this tab: the form the page is showing, the
    /// frame it lives in, and the §14.8 gate every fill passes through.
    ///
    /// One stored property rather than five, because a Swift extension cannot
    /// carry storage. The behaviour is next door in `Passwords/`.
    public let passwords = PasswordCoordinator()

    /// Whose per-site answers this tab reads and writes — a private window's own (§5.6).
    public var sitePermissions: SitePermissions { .scope(for: dataStore) }

    public init(
        id: UUID,
        dataStore: WKWebsiteDataStore,
        favicons: FaviconService = .shared,
        webExtensionController: WKWebExtensionController? = nil
    ) {
        self.id = id
        self.dataStore = dataStore
        self.favicons = favicons
        self.webExtensionController = webExtensionController
        state = TabState()
        super.init()
        messageRelay.owner = self
        passwords.tab = self
    }

    // MARK: - Lifecycle

    /// Builds the web view if this tab is cold, restoring the saved session into it.
    public func activate() {
        ensureWebView(restoringSession: true)
    }

    /// Builds this tab's web view from a configuration handed over by
    /// `createWebViewWith` (§4.2). WebKit requires the popup to use that exact
    /// configuration, or `window.opener` and `target="_blank"` break. The caller
    /// must not load anything into it: WebKit performs the pending navigation
    /// itself once the view is returned.
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
    /// that one navigation and cleared when it commits. §17's blocking must
    /// let this URL through, or the button does nothing. `internal(set)`
    /// because `private` is file-scoped and the setter is next door; nothing
    /// outside `BrowserKit` can write it.
    public internal(set) var bypassedURL: URL?

    public func reload() { webView?.reload() }
    public func stop() { webView?.stopLoading() }
    public func goBack() { webView?.goBack() }
    public func goForward() { webView?.goForward() }

    /// §19.3 heartbeat — call on window/app activation. A WebContent process
    /// suspended in the background can fail to resume and leave a dead white
    /// view with no termination callback; the only probe is asking it to run
    /// something.
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
        let webView = WebViewFactory.makeWebView(dataStore: dataStore, webExtensionController: webExtensionController)
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
        for name in [Self.mediaMessageName, ContentBlocker.blockedMessageName,
                     Self.scrollMessageName, PasswordForms.messageName,
                     ContentBlocker.youTubeMessageName] {
            controller.removeScriptMessageHandler(forName: name)
            controller.add(messageRelay, name: name)
        }
        installUserScripts(into: controller, host: state.url?.host())

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
            webView.observe(\.hasOnlySecureContent, options: [.new]) { republish($0, $1) },
            // The site offering a `theme-color` is what decides the colour behind
            // the page, so this one hands it over before it publishes.
            webView.observe(\.themeColor, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.matchBackgroundToTheme()
                    self?.publishState()
                }
            },
            // WebKit answers this off a paint, so it lands after the navigation
            // callbacks rather than in them — see `publishState`.
            webView.observe(\.underPageBackgroundColor, options: [.new]) { republish($0, $1) }
        ]
        self.webView = webView
    }

    /// Every user script this tab runs, installed from scratch.
    ///
    /// `removeAllUserScripts()` first, because `WKUserContentController` cannot
    /// remove a single script. That is why this is a function rather than four
    /// lines in `attach`: §17.2's YouTube script is the first whose presence
    /// depends on a setting and on the site, so the first that has to come off.
    private func installUserScripts(into controller: WKUserContentController, host: String?) {
        controller.removeAllUserScripts()
        youTubeScriptInstalled = ContentBlocker.shared.blocksYouTubeAds(forHost: host, in: sitePermissions)

        controller.addUserScript(Self.documentEndScript())
        // §14.10: hides `PublicKeyCredential` until Apple grants the
        // entitlement, so sites offer a password instead of a passkey button
        // that cannot work. Returns nil — and injects nothing — once it is
        // granted. `documentStart`, because feature detection runs early.
        if let passkeyGuard = PasskeySupport.userScript() {
            controller.addUserScript(passkeyGuard)
        }
        // Main frame only: an ad iframe scrolling itself is not the page moving,
        // and §3.2b's bar collapses on the page moving.
        controller.addUserScript(
            WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // §17.2. `documentStart` is load-bearing, not a preference: YouTube's
        // bundle caches its own `JSON.parse` and `Response.prototype.text` on
        // the way up, and a hook installed after it has run is measurably never
        // called. Every frame, because a `youtube-nocookie` embed is a frame and
        // plays the same pre-roll; the script's first act is to check its own
        // hostname and leave.
        if youTubeScriptInstalled {
            controller.addUserScript(
                WKUserScript(
                    source: ContentBlocker.youTubeScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
            )
        }
    }

    /// Re-installs the scripts when — and only when — §17.2's answer for the site the
    /// tab is headed to differs from the answer it was built with.
    ///
    /// Called from `decidePolicyFor`, which is early enough: WebKit takes the
    /// script set when it creates the document, and the document does not exist
    /// yet. Guarded rather than unconditional because `removeAllUserScripts()`
    /// throws away WebKit's compiled copy of four sources.
    func refreshUserScriptsIfNeeded(host: String?) {
        guard let controller = webView?.configuration.userContentController else { return }
        let blocks = ContentBlocker.shared.blocksYouTubeAds(forHost: host, in: sitePermissions)
        guard blocks != youTubeScriptInstalled else { return }
        installUserScripts(into: controller, host: host)
    }

    /// The document-end scripts every frame on the page gets, as one
    /// `WKUserScript` rather than three.
    ///
    /// They are `forMainFrameOnly: false` because the things they watch live in
    /// subframes — an embedded player makes sound, an ad frame is where a
    /// blocked request happens, a sign-in form is very often in an iframe — so
    /// a news page with thirty ad frames is thirty injections of each.
    ///
    /// This is one seam, not a saving. It was measured and it is a dead
    /// heat: 31-frame page, two harness binaries interleaved, ten rounds
    /// each, `+14.53 ms` merged against `+14.35 ms` split (`docs/PERF.md`).
    /// Three `WKUserScript`s are not three compiles per frame — WebKit compiles
    /// a source once and evaluates it per frame — and what the frame pays for is
    /// the evaluating, which is the same code either way. What it buys is one
    /// place that decides what every frame gets; do not read a speed claim into
    /// it, and do not merge anything else hoping for one.
    ///
    /// The `try`/`catch` is not new error-hiding. WebKit ran the three
    /// independently, so one of them throwing left the other two installed;
    /// joining them into one script is exactly what would have taken that away.
    /// ``isolated(_:)`` puts it back and nothing else. They share no scope
    /// either: each source is its own IIFE, as it was when WebKit held them
    /// apart.
    static func documentEndScript() -> WKUserScript {
        var sources = [mediaScript, ContentBlocker.blockedCountScript]
        // §14: not injected at all when the feature is off, rather than
        // injected and ignored. A user who declines autofill should not pay a
        // MutationObserver on every frame of every page for it.
        if PasswordSettings.isEnabled { sources.append(PasswordForms.script) }
        return WKUserScript(
            source: isolated(sources),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    /// `sources` joined so that one of them throwing does not take the rest
    /// with it. Pure, and separate from the script that uses it, so the
    /// isolation can be asserted with sources that actually throw.
    static func isolated(_ sources: [String]) -> String {
        sources.map { "try {\n\($0)\n} catch (error) {}" }.joined(separator: "\n")
    }

    /// Everything that has to happen before the last reference to the web view
    /// goes away. The user content controller holds its handlers and scripts
    /// strongly, so leaving them registered pins the web view — and a WebContent
    /// process with it — for as long as the configuration lives (§19.2).
    ///
    /// Silence is something this does, not something it waits for. Unhooking the
    /// view and letting go of it relies on a deallocated `WKWebView` closing its
    /// page, which is true of the last reference and says nothing about the one
    /// before it: WebKit's own async completions, a floating Picture-in-Picture
    /// window, element fullscreen, a snapshot in flight can each outlive this
    /// call by an unbounded amount, and the page plays for as long as one does.
    /// Closing a pinned tab with a video running left the sound going in the
    /// background with nothing on screen to stop it. Audio is the one leak a
    /// user can hear, so it is turned off explicitly and first.
    ///
    /// Suspended rather than paused: suspending also refuses the page's own
    /// attempts to start again, and there is no resume to pair it with because
    /// this view never comes back — `ensureWebView` builds a new one.
    private func detach() {
        guard let view = webView else { return }
        webView = nil

        // The closure holds `view` until WebKit has finished, exactly as the
        // media-presentation teardown below does.
        view.setAllMediaPlaybackSuspended(true) { _ = view }

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
        controller.removeScriptMessageHandler(forName: Self.scrollMessageName)
        controller.removeScriptMessageHandler(forName: PasswordForms.messageName)
        controller.removeScriptMessageHandler(forName: ContentBlocker.youTubeMessageName)

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

        // Respawning immediately puts a new WebContent process into the same
        // broken XPC state: after a sleep/wake, launchservicesd needs seconds to
        // come back and an instant rebuild becomes a tight crash loop.
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
}

// MARK: - State

/// An extension rather than more of the class above: `TabController` is the
/// engine class §33's 4,000-line warning is aimed at, and a type body has a
/// length limit. Everything here is about what the tab currently *is* — its
/// published state, the colour behind the page, and the scripts every document
/// gets — rather than about building or tearing down a web view.
extension TabController {

    // MARK: - State

    /// A new document owns neither the old title nor the old tint, and none of the old
    /// frames are still making noise.
    func resetPerDocumentState() {
        state.title = ""
        state.themeColor = nil
        state.pageBackground = nil
        // And un-pinned in the web view, not only in the state: a colour handed
        // to WebKit by `matchBackgroundToTheme` stays until it is taken back, so
        // a site with a `theme-color` would paint the next document's
        // over-scroll in its own. nil gives the question back to WebKit, which
        // answers it off this document's first paint.
        webView?.underPageBackgroundColor = nil
        // Published, not just cleared: the chrome is painted in this and the
        // new document has not reported its own yet.
        setTopColour(nil)
        setScrollProgress(nil)
        audibleFrames.removeAll()
        // The interstitial bypass is good for the one navigation it was granted
        // for. Leaving it set would quietly allowlist the site for as long as the
        // tab lives (§4.5).
        bypassedURL = nil
        // §17.4's count is per document, and the page's own counter restarts too.
        ContentBlocker.shared.resetBlockedCount(tab: id)
        // §14: the form belonged to the document that just went away, and so
        // did any popover pointing at it.
        delegate?.tabControllerDidDismissPasswordUI(self)
    }

    /// Hands WebKit the site's own `theme-color` to paint behind the page — the
    /// colour over-scroll and the gap before first paint show — or nil, which
    /// gives the question back to WebKit and its computed answer.
    ///
    /// Written where the answer changes, never off a read. This and
    /// `resetPerDocumentState`'s clear are the only two writes, which is what
    /// lets the property be observed: a write wakes the observation, the
    /// observation publishes, and publishing writes nothing.
    ///
    /// `publishState` wrote it too, which is what the old comment there called a
    /// loop with no exit. It would in fact have stopped after one turn: WebKit's
    /// setter coalesces, and assigning a value equal to the one it holds posts no
    /// change at all (measured). The real cost was never the loop — it was that
    /// the write forced a read of an answer WebKit had not worked out yet.
    func matchBackgroundToTheme() {
        webView?.underPageBackgroundColor = webView?.themeColor
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
            // Read, never written. This is the colour the page is actually
            // painted on, which is what §3.2b's bar matches; it is written only by
            // `matchBackgroundToTheme` and by `resetPerDocumentState`, and observed
            // like every other property here. This method used to assign it and
            // read it back in the same statement, and that answer was behind:
            // nil hands the question back to WebKit, which recomputes off the next
            // paint, so the read returned the document that had just gone away.
            // Measured on two local pages, A `#0a0a14` and B `#3a0a0a`: `didFinish`
            // for B reported A's `10,10,20`, and Back to A reported B's `58,10,10`.
            next.pageBackground = webView.underPageBackgroundColor
                .flatMap { ColorBridge.rgba(from: $0.cgColor) }
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
        let favicons = favicons
        Task { [weak self] in
            let png = await favicons.fetchFavicon(for: webView, host: host)
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

    /// §17.2's YouTube script, reporting its running total. Main frame only: on a watch
    /// page that is the frame the ads are in, and accepting subframes would have two
    /// counters overwriting one slot.
    func handleYouTubeMessage(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let count = body["count"] as? Int else { return }
        ContentBlocker.shared.setYouTubeBlockedCount(count, tab: id)
    }

    func handleMediaMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let audible = body["audible"] as? Bool
        else { return }
        let frame = message.frameInfo.isMainFrame
            ? "" : (message.frameInfo.request.url?.absoluteString ?? "subframe")
        // Only when the set actually moved. `publishState` reads eight properties
        // off the web view and converts two colours, and a message that says what
        // the last one said is not news — the script below already drops most of
        // those, and this is the half of the guard that does not trust a page.
        let changed = audible ? audibleFrames.insert(frame).inserted : audibleFrames.remove(frame) != nil
        guard changed else { return }
        publishState()
    }

    /// Reports whether any media element in the frame is audible — playing, unmuted
    /// and above zero volume. `requestMediaPlaybackState()` would call a muted autoplay
    /// video "playing" and put a speaker badge on half the sidebar.
    ///
    /// Media events do not bubble, so the listeners are registered in the capture phase;
    /// that is the only way one document-level listener sees every `<video>`.
    /// It only speaks when the answer changes. This runs in every frame
    /// (`forMainFrameOnly: false`, because an embedded player lives in a
    /// subframe), and it used to post from every one of them at document end to
    /// say what silence already said: a page with ten ad iframes was ten
    /// messages across the process boundary and ten `publishState` calls before
    /// it had finished loading. `false` is what the tab already is — nothing
    /// reaches `audibleFrames` until something says otherwise, and
    /// `resetPerDocumentState` empties it on every navigation — so the opening
    /// `post()` has nothing to report unless the frame is already making
    /// noise, which is the autoplay case it is there for.
    ///
    /// The same latch pays again during playback: `volumechange` fires on every
    /// tick of a volume drag, and all but the one that crosses zero say what the
    /// last one did.
    ///
    /// Internal rather than private so `MediaScriptTests` can run it —
    /// the same reason `scrollScript` is, and the same lesson behind it.
    static let mediaScript = """
    (function () {
      var last = false;
      var post = function () {
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaMedia;
        if (!h) { return; }
        var audible = false;
        var media = document.querySelectorAll('video, audio');
        for (var i = 0; i < media.length; i++) {
          var m = media[i];
          if (!m.paused && !m.muted && m.volume > 0) { audible = true; break; }
        }
        if (audible === last) { return; }
        last = audible;
        h.postMessage({ audible: audible });
      };
      ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied'].forEach(function (name) {
        document.addEventListener(name, post, true);
      });
      post();
    })();
    """
}
