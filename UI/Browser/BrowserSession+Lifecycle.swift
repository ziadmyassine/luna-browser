//
//  BrowserSession+Lifecycle.swift
//  Luna
//
//  §19.2 hibernation, §6.3 auto-archive and §6.8 snapshots — the half of the
//  lifecycle that needs the session, a web view or AppKit. The decisions
//  themselves are in `BrowserKit/Engine/Lifecycle`, as pure functions over
//  values, so this file is only side effects and timing.
//
//  Timing is the part that is easy to get wrong:
//
//  · Snapshot before hibernate, never after. `takeSnapshot` talks to the
//    WebContent process; once that process is gone there is nothing to ask, and
//    the archive row loses its picture for good. So the sweep captures first and
//    tears down in the completion — except under critical memory pressure,
//    where holding a renderer alive for a thumbnail is the wrong trade.
//  · Never break §6.2. Nothing here reads `interactionState` late:
//    `BrowserSession+Engine` already caches the blob at every settled load, and
//    `cacheSession(of:)` after `hibernate()` only moves the copy the controller
//    already holds. A dead WebContent process reads back nil, and that is fine,
//    because by then the blob is already on the `Tab`.
//  · Energy (§19.6). One 60 s timer with 30 s tolerance, so it coalesces
//    with whatever else the system is doing rather than pinning a wake-up.
//    Nothing here calls `beginActivity`, so App Nap still applies, and Luna
//    terminates when its last window closes, so there is no window-less state
//    for a timer to keep running in.
//
//  Install with one line where the session is built:
//
//      TabLifecycle.install(in: session)
//

import AppKit
import BrowserKit
import WebKit

extension BrowserSession {

    /// §19.2 / §6.3 / §6.8, running. Idempotent.
    ///
    /// Also the launch sweep for orphaned `WKWebsiteDataStore`s — one call, one
    /// place the app already calls, and the drain for the deferred store-removal
    /// queue. It lives in `BrowserSession+Spaces.swift`, with the rest of the
    /// profile lifecycle.
    func installLifecycle() {
        TabLifecycle.install(in: self)
        sweepOrphanedProfileStores()
    }
}

/// The lifecycle pass. One per session.
@MainActor
final class TabLifecycle {

    /// The installed passes, keyed by session.
    ///
    /// A registry rather than a property because a `BrowserSession` extension
    /// cannot add stored state, and the alternative — handing the object back
    /// for `AppDelegate` to retain — makes the integration two lines and a
    /// property in a file this agent does not own. Entries are dropped by
    /// `uninstall(from:)`; the app has one session, for the lifetime of the app.
    private static var installed: [ObjectIdentifier: TabLifecycle] = [:]

    /// §19.2's budget on demand — what `BrowserSession.enforceLiveTabBudget`
    /// calls when a new web view is created. A no-op until the pass is
    /// installed, which `AppDelegate` does before the first tab exists.
    static func enforceBudget(in session: BrowserSession) {
        installed[ObjectIdentifier(session)]?.sweep(underMemoryPressure: false)
    }

    static func install(in session: BrowserSession) {
        let key = ObjectIdentifier(session)
        guard installed[key] == nil else { return }
        installed[key] = TabLifecycle(session: session)
    }

    static func uninstall(from session: BrowserSession) {
        let key = ObjectIdentifier(session)
        installed[key]?.tearDown()
        installed[key] = nil
    }

    /// Stops the clock. Explicit rather than a `deinit`, because a `deinit` is
    /// nonisolated and Swift 6 will not let it touch main-actor state — and
    /// reaching for `nonisolated(unsafe)` to get at a `Timer` would be silencing
    /// the checker rather than answering it.
    func tearDown() {
        timer?.invalidate()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
        observation = nil
    }

    private weak var session: BrowserSession?
    private let policy = HibernationPolicy(liveBudget: BrowserSession.liveTabBudget)
    private let snapshots: SnapshotStore
    private var timer: Timer?
    private var pressureSource: (any DispatchSourceMemoryPressure)?
    private var observation: ObservationToken?

    /// Tabs whose page reported typed-but-unsubmitted input (§19.2).
    private var dirtyTabIDs: Set<UUID> = []
    /// Web views already carrying the form-watch script, so it is installed once.
    private var instrumented: Set<ObjectIdentifier> = []
    /// Which tab the last snapshot-on-blur was taken against.
    private var lastActiveID: UUID?
    private var lastPurge = Date.distantPast

    static let formMessageName = "lunaForm"
    /// §6.8 — "downsampled". A sidebar hover preview is ~200 pt wide; 320 gives
    /// it a retina source and keeps a PNG in the tens of kilobytes.
    static let snapshotWidth = 320.0

    private init(session: BrowserSession) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        snapshots = SnapshotStore(directory: caches
            .appending(path: Bundle.main.bundleIdentifier ?? "dk.novapps.luna")
            .appending(path: "snapshots"))

        observation = session.addChangeObserver { [weak self] in self?.sessionDidChange() }

        // `[weak self]`: the timer retains its block, so a strong capture would
        // be a cycle that outlives the window.
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep(underMemoryPressure: false) }
        }
        // §19.6: a timer that insists on an exact fire time is a timer that
        // wakes an idle Mac. This one has no deadline worth defending.
        timer.tolerance = 30
        self.timer = timer

        // §19.2: under pressure, do not wait for the 5-minute threshold.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let critical = source.data.contains(.critical)
                self.sweep(underMemoryPressure: true, skipSnapshots: critical)
            }
        }
        source.resume()
        pressureSource = source
    }

    // MARK: - The sweep

    func sweep(underMemoryPressure: Bool, skipSnapshots: Bool = false) {
        guard let session else { return }
        let now = Date()

        let live = session.controllers.compactMap { (id, controller) -> TabActivity? in
            guard controller.webView != nil, let tab = session.tab(id) else { return nil }
            return TabActivity(
                id: id,
                lastActiveAt: tab.lastActiveAt,
                isAudible: controller.state.isPlayingAudio,
                hasUnsavedInput: dirtyTabIDs.contains(id)
            )
        }
        let doomed = policy.tabsToHibernate(
            live: live,
            mru: session.recentTabs,
            activeID: session.activeTabID,
            now: now,
            underMemoryPressure: underMemoryPressure
        )
        for id in doomed {
            if skipSnapshots {
                hibernate(id)
            } else {
                captureSnapshot(of: id) { [weak self] in self?.hibernate(id) }
            }
        }

        archiveIdleTabs(now: now)

        // The 30-day purge is not a per-minute job.
        if now.timeIntervalSince(lastPurge) > 60 * 60 {
            lastPurge = now
            purgeExpiredArchive(now: now)
        }
    }

    private func hibernate(_ id: UUID) {
        guard let session, let controller = session.controller(for: id) else { return }
        // `hibernate()` closes media presentations itself — without that a
        // hibernated tab leaves an orphan Picture-in-Picture window (§19.3).
        controller.hibernate()
        session.cacheSession(of: controller)
        dirtyTabIDs.remove(id)
    }

    // MARK: - §6.3 auto-archive

    /// 6 / 12 / 24 hours, or never. No settings UI exists yet (§23), so the key
    /// is read straight from defaults and the default is §6.3's 12 hours.
    static let autoArchiveHoursKey = "luna.autoArchiveHours"

    static var autoArchiveHours: Double {
        UserDefaults.standard.object(forKey: autoArchiveHoursKey) as? Double ?? AutoArchive.defaultHours
    }

    private func archiveIdleTabs(now: Date) {
        guard let session else { return }
        let doomed = AutoArchive.idleTabs(
            session.allTabs(includeArchived: false),
            now: now,
            hours: Self.autoArchiveHours,
            excluding: session.activeTabID
        )
        guard !doomed.isEmpty else { return }
        // `closeTab` is §6.3's archive — same soft delete as ⌘W, so the row
        // keeps its title, URL and favicon. The undo stack is the user's record
        // of what they did, so a background sweep stays out of it.
        session.undoManager.disableUndoRegistration()
        for id in doomed { session.closeTab(id) }
        session.undoManager.enableUndoRegistration()
    }

    private func purgeExpiredArchive(now: Date) {
        guard let session else { return }
        let expired = AutoArchive.expired(session.archived, now: now)
        guard !expired.isEmpty else { return }
        session.archived.removeAll { expired.contains($0.id) }
        let store = session.store
        let snapshots = snapshots
        Task {
            for id in expired {
                try? await store.delete(tabID: id)
                await snapshots.remove(id)
            }
        }
        session.notifyChange()
    }

    // MARK: - §6.8 snapshots

    /// The tab's last snapshot, for the sidebar hover preview and the archive.
    func snapshot(for id: UUID) async -> NSImage? {
        (await snapshots.snapshot(for: id)).flatMap(NSImage.init(data:))
    }

    /// - Parameter then: runs after the snapshot has been handed to the store —
    ///   or immediately if there is nothing to capture. The tear-down goes here,
    ///   because a snapshot taken after the WebContent process dies comes back
    ///   nil (§6.8).
    private func captureSnapshot(of id: UUID, then: (@MainActor () -> Void)? = nil) {
        guard let webView = session?.controller(for: id)?.webView,
              webView.bounds.width > 1, webView.bounds.height > 1
        else {
            then?()
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Self.snapshotWidth)
        // A tab that is not the active one has no screen updates coming, and the
        // default (YES) waits for one that never arrives.
        configuration.afterScreenUpdates = false
        let snapshots = snapshots
        Task {
            let image = try? await webView.takeSnapshot(configuration: configuration)
            if let png = image.flatMap(Self.pngData) {
                await snapshots.store(png, for: id)
            }
            then?()
        }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Selection changes

    private func sessionDidChange() {
        guard let session else { return }
        instrumentLiveWebViews()
        let active = session.activeTabID
        guard active != lastActiveID else { return }
        // §6.8: "on blur". The outgoing tab is still live at this point, which
        // is the only moment its snapshot is cheap and possible.
        if let previous = lastActiveID { captureSnapshot(of: previous) }
        lastActiveID = active
    }

    // MARK: - Unsaved form input

    /// Adds the form watcher to any live web view that does not have it.
    ///
    /// Done from here rather than in `TabController` because the handler and its
    /// state belong to the lifecycle pass, and `TabController` is not this
    /// agent's file. `evaluateJavaScript` covers the document that is already
    /// loaded; the user script covers every one after it.
    private func instrumentLiveWebViews() {
        guard let session else { return }
        var seen: Set<ObjectIdentifier> = []
        for (id, controller) in session.controllers {
            guard let webView = controller.webView else { continue }
            let key = ObjectIdentifier(webView)
            seen.insert(key)
            guard !instrumented.contains(key) else { continue }
            instrumented.insert(key)

            let content = webView.configuration.userContentController
            // Re-registering a name raises `NSInvalidArgumentException`;
            // removing one that is not there is free.
            content.removeScriptMessageHandler(forName: Self.formMessageName)
            content.add(FormRelay(tabID: id, owner: self), name: Self.formMessageName)
            content.addUserScript(WKUserScript(
                source: Self.formScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
            // The document that is already open; the user script covers the rest.
            webView.evaluateJavaScript(Self.formScript, completionHandler: nil)
        }
        // A web view that has gone away takes its entry with it.
        instrumented.formIntersection(seen)
    }

    func setDirty(_ dirty: Bool, for id: UUID) {
        if dirty { dirtyTabIDs.insert(id) } else { dirtyTabIDs.remove(id) }
    }

    func hasUnsavedInput(_ id: UUID) -> Bool { dirtyTabIDs.contains(id) }

    /// §19.2's "unsaved form input", and exactly what it detects:
    ///
    /// · an `input` event from an `<input>`, `<textarea>`, `<select>` or a
    ///   `contenteditable` element — i.e. the user typed something that has not
    ///   been submitted. Cleared on `submit`, and by the next document, because
    ///   this script re-runs on every one.
    /// · a `beforeunload` handler assigned to `window.onbeforeunload`. A handler
    ///   registered with `addEventListener` instead is invisible to any page
    ///   script, so a site that guards its draft that way is not detected. There
    ///   is no API that reports it; this is the honest ceiling of the heuristic.
    ///
    /// It does not know whether the input was meaningful, and it never reads the
    /// values — only that the page was touched.
    private static let formScript = """
    (function () {
      var post = function (dirty) {
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lunaForm;
        if (h) { h.postMessage({ dirty: dirty }); }
      };
      var dirty = false;
      document.addEventListener('input', function (event) {
        if (dirty) { return; }
        var target = event.target;
        if (!target) { return; }
        var name = (target.tagName || '').toLowerCase();
        if (name === 'input' || name === 'textarea' || name === 'select' || target.isContentEditable) {
          dirty = true;
          post(true);
        }
      }, true);
      document.addEventListener('submit', function () { dirty = false; post(false); }, true);
      post(typeof window.onbeforeunload === 'function');
    })();
    """
}

/// Holds the lifecycle pass weakly: `WKUserContentController` retains its
/// message handlers strongly, so a strong reference here would pin the web view
/// and its WebContent process for as long as the configuration lives — the
/// exact leak `TabController`'s `MediaMessageRelay` header describes.
@MainActor
private final class FormRelay: NSObject, WKScriptMessageHandler {
    private let tabID: UUID
    private weak var owner: TabLifecycle?

    init(tabID: UUID, owner: TabLifecycle) {
        self.tabID = tabID
        self.owner = owner
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == TabLifecycle.formMessageName,
              let body = message.body as? [String: Any],
              let dirty = body["dirty"] as? Bool
        else { return }
        owner?.setDirty(dirty, for: tabID)
    }
}
