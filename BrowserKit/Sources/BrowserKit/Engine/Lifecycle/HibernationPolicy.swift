import Foundation

/// What the lifecycle pass knows about one live tab — the inputs §19.2's
/// policy is defined against, and nothing else. Keeping it a value type is what
/// lets the policy be tested without a window, a web view or a clock.
public struct TabActivity: Sendable, Equatable {
    public var id: UUID
    /// The last moment the tab was in front: when it was left, not when it
    /// was chosen. Measured from the choosing, an hour spent reading a tab
    /// counted as an hour of idleness the moment the user moved on.
    public var lastActiveAt: Date

    /// Whether any media element in any frame is audible: playing, unmuted,
    /// volume above zero. That is what `TabController`'s injected listener
    /// reports, and it is deliberately not what WebKit's own API reports —
    /// `requestMediaPlaybackState()` calls a muted autoplay video "playing",
    /// and `_isPlayingAudio` is SPI (D10). So a tab playing a silent video or a
    /// muted stream is not protected here and will hibernate; a tab playing
    /// a video with the sound on is (§18.4).
    public var isAudible: Bool

    /// The user has typed into a form control or a `contenteditable` since the
    /// document loaded. A heuristic, not a guarantee — see
    /// `BrowserSession+Lifecycle`'s script for exactly what it detects.
    public var hasUnsavedInput: Bool

    /// Playing audio or holding unsaved input: closing the web view would stop
    /// the one or drop the other, and neither comes back from
    /// `interactionState`. Hibernation and auto-archive both keep these.
    public var mustStayOpen: Bool { isAudible || hasUnsavedInput }

    public init(id: UUID, lastActiveAt: Date, isAudible: Bool = false, hasUnsavedInput: Bool = false) {
        self.id = id
        self.lastActiveAt = lastActiveAt
        self.isAudible = isAudible
        self.hasUnsavedInput = hasUnsavedInput
    }
}

/// How hard macOS is asking for memory back, as the dispatch source reports it.
public enum MemoryPressure: Sendable, Equatable {
    case normal
    /// The system is short but managing: shed the tabs least likely to be
    /// wanted, keep the few most recent.
    case warning
    /// The next step is the system killing WebContent processes itself.
    case critical
}

/// §19.2's keep-alive rule, as a pure function.
///
/// Hibernating is cheap to get wrong in an invisible way: too eager and the
/// user loses a half-written comment, too lazy and the memory budget is a
/// slogan. So the decision lives here, where a test can state every case, and
/// the side effects — snapshot, tear down, persist — live in the session.
public struct HibernationPolicy: Sendable, Equatable {

    /// The active tab plus the last N used. `BrowserSession.liveTabBudget`
    /// passes 8. A sleeping tab reloads its page from scratch when it is
    /// chosen again, which is the wait Chromium browsers do not make anyone
    /// sit through. Six live tabs measured 808 MB of footprint (docs/PERF.md),
    /// so eight is about 1.1 GB, well inside §19.1's 3.5 GB.
    public var liveBudget: Int

    /// How long a tab outside the budget must sit untouched before it loses its
    /// web view. Memory pressure ignores it.
    public var idleThreshold: TimeInterval

    /// What a `.warning` keeps besides the active tab: the tabs one switch
    /// away, so the system's first request for memory does not turn every
    /// tab switch into a reload.
    public var pressureBudget: Int

    public init(liveBudget: Int = 8, idleThreshold: TimeInterval = 30 * 60, pressureBudget: Int = 3) {
        self.liveBudget = liveBudget
        self.idleThreshold = idleThreshold
        self.pressureBudget = pressureBudget
    }

    /// Tabs that must keep their `WKWebView`.
    ///
    /// - Parameters:
    ///   - live: every tab that currently holds a web view.
    ///   - mru: tab ids, most recently used first (`BrowserSession.recentTabs`).
    ///   - activeID: the selected tab. Kept whatever else is true of it.
    ///   - pressure: `.warning` shrinks the budget to `pressureBudget`;
    ///     `.critical` collapses it to the active tab, because the alternative
    ///     is the system killing our WebContent processes for us.
    public func keepAlive(
        live: [TabActivity],
        mru: [UUID],
        activeID: UUID?,
        pressure: MemoryPressure = .normal
    ) -> Set<UUID> {
        // `mustStayOpen` survives memory pressure: stopping the music or
        // dropping a half-typed reply is a bug the user can see.
        var keep = Set(live.filter(\.mustStayOpen).map(\.id))
        if let activeID { keep.insert(activeID) }
        switch pressure {
        case .normal: keep.formUnion(mru.prefix(liveBudget))
        case .warning: keep.formUnion(mru.prefix(pressureBudget))
        case .critical: break
        }
        return keep
    }

    /// Tabs to tear down now: outside the keep-alive set and idle past the
    /// threshold. Under pressure the threshold does not apply.
    public func tabsToHibernate(
        live: [TabActivity],
        mru: [UUID],
        activeID: UUID?,
        now: Date,
        pressure: MemoryPressure = .normal
    ) -> [UUID] {
        let keep = keepAlive(live: live, mru: mru, activeID: activeID, pressure: pressure)
        return live
            .filter { !keep.contains($0.id) }
            .filter { pressure != .normal || now.timeIntervalSince($0.lastActiveAt) >= idleThreshold }
            .map(\.id)
    }
}
