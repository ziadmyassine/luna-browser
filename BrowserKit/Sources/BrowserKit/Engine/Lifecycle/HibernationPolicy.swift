import Foundation

/// What the lifecycle pass knows about one **live** tab — the inputs §19.2's
/// policy is defined against, and nothing else. Keeping it a value type is what
/// lets the policy be tested without a window, a web view or a clock.
public struct TabActivity: Sendable, Equatable {
    public var id: UUID
    public var lastActiveAt: Date

    /// Whether any media element in any frame is **audible**: playing, unmuted,
    /// volume above zero. That is what `TabController`'s injected listener
    /// reports, and it is deliberately not what WebKit's own API reports —
    /// `requestMediaPlaybackState()` calls a muted autoplay video "playing",
    /// and `_isPlayingAudio` is SPI (D10). So a tab playing a silent video or a
    /// muted stream is **not** protected here and will hibernate; a tab playing
    /// a video with the sound on is (§18.4).
    public var isAudible: Bool

    /// The user has typed into a form control or a `contenteditable` since the
    /// document loaded. A heuristic, not a guarantee — see
    /// `BrowserSession+Lifecycle`'s script for exactly what it detects.
    public var hasUnsavedInput: Bool

    public init(id: UUID, lastActiveAt: Date, isAudible: Bool = false, hasUnsavedInput: Bool = false) {
        self.id = id
        self.lastActiveAt = lastActiveAt
        self.isAudible = isAudible
        self.hasUnsavedInput = hasUnsavedInput
    }
}

/// §19.2's keep-alive rule, as a pure function.
///
/// Hibernating is cheap to get wrong in an invisible way: too eager and the
/// user loses a half-written comment, too lazy and the memory budget is a
/// slogan. So the decision lives here, where a test can state every case, and
/// the side effects — snapshot, tear down, persist — live in the session.
public struct HibernationPolicy: Sendable, Equatable {

    /// The active tab plus the last N used. `BrowserSession.liveTabBudget`
    /// passes 4: active + 3 (§19.2's default).
    public var liveBudget: Int

    /// How long a tab outside the budget must sit untouched before it loses its
    /// web view. Memory pressure ignores it.
    public var idleThreshold: TimeInterval

    public init(liveBudget: Int = 4, idleThreshold: TimeInterval = 5 * 60) {
        self.liveBudget = liveBudget
        self.idleThreshold = idleThreshold
    }

    /// Tabs that must keep their `WKWebView`.
    ///
    /// - Parameters:
    ///   - live: every tab that currently holds a web view.
    ///   - mru: tab ids, most recently used first (`BrowserSession.recentTabs`).
    ///   - activeID: the selected tab. Kept whatever else is true of it.
    ///   - underMemoryPressure: collapses the budget to the active tab, because
    ///     the alternative is the system killing our WebContent processes for us.
    public func keepAlive(
        live: [TabActivity],
        mru: [UUID],
        activeID: UUID?,
        underMemoryPressure: Bool = false
    ) -> Set<UUID> {
        // Audio and unsaved input survive memory pressure: stopping the music
        // or dropping a half-typed reply is a bug the user can see, and neither
        // comes back from `interactionState`.
        var keep = Set(live.filter { $0.isAudible || $0.hasUnsavedInput }.map(\.id))
        if let activeID { keep.insert(activeID) }
        guard !underMemoryPressure else { return keep }
        keep.formUnion(mru.prefix(liveBudget))
        return keep
    }

    /// Tabs to tear down now: outside the keep-alive set **and** idle past the
    /// threshold. Under pressure the threshold does not apply.
    public func tabsToHibernate(
        live: [TabActivity],
        mru: [UUID],
        activeID: UUID?,
        now: Date,
        underMemoryPressure: Bool = false
    ) -> [UUID] {
        let keep = keepAlive(live: live, mru: mru, activeID: activeID, underMemoryPressure: underMemoryPressure)
        return live
            .filter { !keep.contains($0.id) }
            .filter { underMemoryPressure || now.timeIntervalSince($0.lastActiveAt) >= idleThreshold }
            .map(\.id)
    }
}
