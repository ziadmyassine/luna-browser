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

    let dataStore: WKWebsiteDataStore
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
    private var youTubeScriptInstalled = false, fileSeedInstalled = false
    /// Whether `FileStorageSeed`'s script is in the set — only while the tab is
    /// on a `file:` page.
    /// The hidden-elements stylesheet in the current script set, empty when there is
    /// none — see `TabController+Hiding.swift`.
    var hiddenStyleInstalled = ""
    /// Storage for `TabController+Reader.swift` and `TabController+Hiding.swift`,
    /// which cannot carry their own.
    var readerIsOn = false { didSet { publishState() } }
    /// Storage for `probeForArticle`.
    var isArticle = false { didSet { publishState() } }
    var picking: ElementPicking?
    /// Storage for `Reading/TabController+Markdown.swift`.
    public internal(set) var markdownDocument: MarkdownDocument? { didSet { publishState() } }
    /// Storage for `Reading/TabController+Reading.swift`: the view the
    /// Markdown page is in, and the preferences it was last handed.
    public internal(set) var readingView = ReadingView.read
    var appliedReading: ReadingPreferences?
    /// `markdownHistory`: the document each history entry showed, for a Back
    /// that WebKit answers from its page cache without the load `show` starts.
    var pendingMarkdown: MarkdownDocument?, markdownHistory: [WKBackForwardListItem: MarkdownDocument] = [:]
    var markdownFetch: Task<Void, Never>?
    var fetchText: @Sendable (URL) async throws -> Data = TabController.fetchMarkdownText
    /// Storage for `Reading/TabController+Editing.swift`: the editor's text
    /// while it differs from the file, the pending autosave, whether saving
    /// stopped over a change on disk, and Edit's own undo list.
    var editedText: String? { didSet { publishState() } }
    var autosave: Task<Void, Never>?
    var saveHalted = false
    let editUndo = UndoManager()
    private static let recoveryLimit = 3
    private static let recoveryWindow: TimeInterval = 60

    static let mediaMessageName = "lunaMedia"

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

    /// Every response a document in this tab arrives with, main frame and
    /// subframes, before WebKit decides whether to show or download it. Luna
    /// Control's network log is the one reader.
    public var onNavigationResponse: ((WKNavigationResponse) -> Void)?
    /// Set by the page's Open Link in New Tab just before it sends WebKit's own
    /// new-window item: the tab `createWebViewWith` asks for then stays behind
    /// this one. The host reads and clears it.
    public var nextNewTabIsBackground = false

    /// User scripts added from outside for the life of the tab, kept so
    /// `installUserScripts`, which starts from nothing, puts them back.
    private var addedUserScripts: [WKUserScript] = []

    /// Adds a user script for every document from the next one on.
    public func addUserScript(_ script: WKUserScript) {
        addedUserScripts.append(script)
        webView?.configuration.userContentController.addUserScript(script)
    }

    private let messageRelay = ScriptMessageRelay()

    /// §14's password state for this tab: the form the page is showing, the
    /// frame it lives in, and the §14.8 gate every fill passes through.
    ///
    /// One stored property rather than five, because a Swift extension cannot
    /// carry storage. The behaviour is next door in `Passwords/`.
    public let passwords = PasswordCoordinator()

    /// §17's pop-up state for this tab; the behaviour is in
    /// `TabController+Popups.swift`.
    public let popups = PopupGuard()

    /// Where the pop-up mode is read from. A seam for tests, which must not
    /// write the shared defaults — the same one `ContentBlocker` has.
    var settings: UserDefaults = .standard

    /// A blank pop-up's probation, between `allowsPopup` and the delegate
    /// building its tab. Here because an extension cannot carry storage.
    var pendingProbation: PopupProbation?

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
        followReadingPreferences()
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
        // Closing the tab or the window and quitting all end here.
        saveEditsBeforeClosing()
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
        // Luna's own loads arrive as `.other`, the type the tab-under guard refuses.
        popups.disarm()
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

    /// Where §8.1's tracking strip last sent this tab, until that page commits;
    /// `decidePolicyFor` reads it to break a redirect loop.
    var lastTrackingStrip: URL?

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
                     ContentBlocker.youTubeMessageName, Self.popupMessageName] {
            controller.removeScriptMessageHandler(forName: name)
            controller.add(messageRelay, name: name)
        }
        attachPicker(to: controller, relay: messageRelay)
        attachReading(to: controller, relay: messageRelay)
        installUserScripts(into: controller, host: state.url?.host(), isFile: (state.url ?? fallbackURL)?.isFileURL ?? false)

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
    func installUserScripts(into controller: WKUserContentController, host: String?, isFile: Bool) {
        controller.removeAllUserScripts()
        youTubeScriptInstalled = ContentBlocker.shared.blocksYouTubeAds(forHost: host, in: sitePermissions)
        fileSeedInstalled = false
        if isFile, let seed = FileStorageSeed.userScript() {
            controller.addUserScript(seed)
            fileSeedInstalled = true
        }

        controller.addUserScript(Self.documentEndScript())
        // §14.10: hides `PublicKeyCredential` until Apple grants the
        // entitlement, so sites offer a password instead of a passkey button
        // that cannot work. Returns nil — and injects nothing — once it is
        // granted. `documentStart`, because feature detection runs early.
        if let passkeyGuard = PasskeySupport.userScript() {
            controller.addUserScript(passkeyGuard)
        }
        // §17's pop-up witness. `documentStart`, so `window.open` is wrapped
        // before the page's own scripts take a reference to it; every frame,
        // because ad pop-ups are opened from ad frames.
        controller.addUserScript(
            WKUserScript(source: Self.popupScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        // Main frame only: an ad iframe scrolling itself is not the page moving,
        // and §3.2b's bar collapses on the page moving.
        controller.addUserScript(
            WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // §17.2. `documentStart` is load-bearing, not a preference — see
        // `ContentBlockerYouTube.swift`. Every frame, because a
        // `youtube-nocookie` embed is a frame and plays the same pre-roll; the
        // script's first act is to check its own hostname and leave.
        if youTubeScriptInstalled {
            controller.addUserScript(
                WKUserScript(
                    source: ContentBlocker.youTubeScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
            )
        }
        installHiddenStyle(into: controller, host: host)
        addedUserScripts.forEach(controller.addUserScript)
    }

    /// Re-installs the scripts when — and only when — §17.2's answer for the site the
    /// tab is headed to differs from the answer it was built with, it is headed
    /// to or away from a file (`FileStorageSeed`), or the site has a different
    /// list of hidden elements.
    ///
    /// Called from `decidePolicyFor`, which is early enough: WebKit takes the
    /// script set when it creates the document, and the document does not exist
    /// yet. Guarded rather than unconditional because `removeAllUserScripts()`
    /// throws away WebKit's compiled copy of four sources.
    func refreshUserScriptsIfNeeded(host: String?, isFile: Bool = false) {
        guard let controller = webView?.configuration.userContentController else { return }
        let blocks = ContentBlocker.shared.blocksYouTubeAds(forHost: host, in: sitePermissions)
        let seeds = isFile && FileStorageSeed.userScript() != nil
        guard blocks != youTubeScriptInstalled || seeds != fileSeedInstalled || hiddenStyleIsStale(for: host) else { return }
        installUserScripts(into: controller, host: host, isFile: isFile)
    }

    /// Everything that has to happen before the last reference to the web view
    /// goes away. The user content controller holds its handlers and scripts
    /// strongly, so leaving them registered pins the web view — and a WebContent
    /// process with it — for as long as the configuration lives (§19.2).
    ///
    /// Audio is turned off explicitly and first rather than left to
    /// deallocation: a `WKWebView` closes its page only when the last reference
    /// goes, and WebKit's own async completions, a floating Picture-in-Picture
    /// window, element fullscreen or a snapshot in flight can each outlive this
    /// call by an unbounded amount. A closed pinned tab with a video running
    /// kept its sound going with nothing on screen to stop it.
    ///
    /// Suspended rather than paused: suspending also refuses the page's own
    /// attempts to start again, and there is no resume to pair it with because
    /// this view never comes back — `ensureWebView` builds a new one.
    private func detach() {
        guard let view = webView else { return }
        webView = nil
        let retirement = WebViewRetirement(view)

        view.setAllMediaPlaybackSuspended(true, completionHandler: retirement.completion())

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
        controller.removeScriptMessageHandler(forName: Self.popupMessageName)
        detachPicker(from: controller)
        controller.removeScriptMessageHandler(forName: Self.readingMessageName, contentWorld: .defaultClient)

        // Picture-in-Picture and element fullscreen outlive their web view: without this
        // a hibernated tab leaves a floating video playing with nothing behind it.
        view.closeAllMediaPresentations(completionHandler: retirement.completion())
        view.removeFromSuperview()
        retirement.start()
    }
}

// MARK: - Crash recovery

extension TabController {

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
/// length limit. Everything here is about what the tab currently is — its
/// published state, the colour behind the page, and the scripts every document
/// gets — rather than about building or tearing down a web view.
extension TabController {

    // MARK: - State

    /// A new document owns neither the old title nor the old tint, and none of the old
    /// frames are still making noise.
    func resetPerDocumentState() {
        // First: its storage publishes on every set, and a publish re-reads
        // WebKit's colour, which still answers for the document that went away.
        forgetPageTools()
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
        lastTrackingStrip = nil
        popups.pressedLink = nil
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
    /// `publishState` must not write it. Not for fear of a loop — WebKit's setter
    /// coalesces, and assigning a value equal to the one it holds posts no
    /// change (measured) — but because the write forces a read of an answer
    /// WebKit has not worked out yet.
    func matchBackgroundToTheme() {
        webView?.underPageBackgroundColor = webView?.themeColor
    }

    func publishState() {
        var next = state
        next.isArticle = webView != nil && isArticle
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
            // like every other property here. Assigning it and reading it back in
            // the same statement gives an answer that is behind: nil hands the
            // question back to WebKit, which recomputes off the next paint, so the
            // read returns the document that has just gone away.
            // Measured on two local pages, A `#0a0a14` and B `#3a0a0a`: `didFinish`
            // for B reported A's `10,10,20`, and Back to A reported B's `58,10,10`.
            next.pageBackground = webView.underPageBackgroundColor
                .flatMap { ColorBridge.rgba(from: $0.cgColor) }
            next.isPlayingAudio = !audibleFrames.isEmpty
            next.isReading = markdownDocument != nil || readerIsOn
            next.isEdited = editedText != nil
        } else {
            // A cold tab keeps its identity (url, title, tint) and loses everything that
            // only a live process can answer.
            next.isLoading = false
            next.progress = 0
            next.canGoBack = false
            next.canGoForward = false
            next.isPlayingAudio = false
            next.isReading = false
            next.isEdited = false
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
    ///
    /// It only speaks when the answer changes. This runs in every frame
    /// (`forMainFrameOnly: false`, because an embedded player lives in a
    /// subframe), and posting from each at document end to say what silence
    /// already says makes a page with ten ad iframes ten messages across the
    /// process boundary and ten `publishState` calls before it has loaded.
    /// `false` is what the tab already is — `resetPerDocumentState` empties
    /// `audibleFrames` on every navigation — so the opening `post()` reports
    /// only a frame already making noise, the autoplay case. The same latch
    /// drops the `volumechange` ticks of a volume drag that do not cross zero.
    ///
    /// Internal rather than private so `MediaScriptTests` can run it — the
    /// same reason `scrollScript` is.
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

    /// The document-end scripts every frame on the page gets, as one
    /// `WKUserScript` rather than three.
    ///
    /// They are `forMainFrameOnly: false` because the things they watch live in
    /// subframes — an embedded player makes sound, an ad frame is where a
    /// blocked request happens, a sign-in form is very often in an iframe — so
    /// a news page with thirty ad frames is thirty injections of each.
    ///
    /// One seam, not a saving: measured as a dead heat on a 31-frame page, two
    /// harness binaries interleaved over ten rounds each, `+14.53 ms` merged
    /// against `+14.35 ms` split (`docs/PERF.md`). WebKit compiles a source once
    /// and evaluates it per frame, and the evaluating is the same code either
    /// way. Do not merge anything else in hoping for speed.
    ///
    /// As three `WKUserScript`s, one throwing left the other two running;
    /// ``isolated(_:)`` keeps that and does nothing else.
    /// They share no scope either: each source is its own IIFE.
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
}

// MARK: - Reload

extension TabController {

    /// Past the cache for a page on this Mac (`NavigationPolicy.isLocalDevelopment`).
    /// A text file shown by `localText` is loaded again instead: its page is
    /// the text as it was read, and reloading that shows the same copy.
    /// A Markdown document from the web is fetched again: WebKit's reload
    /// would show the page Luna rendered from the first copy.
    public func reload() {
        guard let url = webView?.url, NavigationPolicy.isLocalDevelopment(url) || markdownDocument != nil
        else { webView?.reload(); return }
        reloadFromOrigin()
    }

    public func reloadFromOrigin() {
        guard let webView else { return }
        if let document = markdownDocument, !document.url.isFileURL {
            fetchMarkdown(at: document.url, into: webView)
        } else if let url = webView.url, Self.isLocalText(url) {
            Self.load(url, into: webView)
        } else {
            webView.reloadFromOrigin()
        }
    }
}
