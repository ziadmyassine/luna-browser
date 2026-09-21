//
//  ReloadBloomTimeline.swift
//  Luna
//
//  The phase machine behind UI-SPEC §7's reload bloom, with no AppKit in it.
//
//  Its own type because §7's "a load finishing under 0.15 s plays nothing" is
//  easy to get subtly wrong and is pure logic over two inputs. Separated, it
//  can be asserted in three lines rather than reasoned about inside a view that
//  owns four CALayers.
//
//  A threshold delay rather than a look-back, because nothing can know at
//  commit time whether a load will be fast: the bloom arms on commit, draws
//  nothing, and becomes visible once the threshold elapses — the same shape as
//  "don't show a spinner for the first 150 ms". A cached reload disarms before
//  anything is composited.
//

/// One reload's worth of §7 state. Value type; the view owns exactly one.
struct ReloadBloomTimeline: Equatable {
    enum Phase: Equatable {
        /// Nothing drawn, nothing scheduled.
        case idle
        /// A load is running but `Tokens.Motion.reloadSkipThreshold` has not
        /// elapsed. Still nothing drawn — this is the phase that makes a
        /// cached reload silent.
        case armed
        /// Snapshot, blur and arc are on screen.
        case playing
    }

    /// What the view has to do about the transition it just caused.
    enum Action: Equatable {
        case nothing
        /// Start the skip-threshold timer.
        case arm
        /// Cancel it. Nothing was drawn, so nothing has to be undone.
        case disarm
        /// Snapshot the page, blur it, bring the arc in.
        case begin
        /// Arc out plus the staggered de-blur.
        case end
    }

    private(set) var phase: Phase = .idle

    /// A `TabState.isLoading` value. Only the edges matter: the progress
    /// ticks that arrive with the same `isLoading` are not transitions, which
    /// is why a second reload mid-load does not restart the bloom.
    mutating func loading(_ isLoading: Bool) -> Action {
        switch (phase, isLoading) {
        case (.idle, true):
            phase = .armed
            return .arm
        case (.armed, false):
            phase = .idle
            return .disarm
        case (.playing, false):
            phase = .idle
            return .end
        default:
            return .nothing
        }
    }

    /// The skip-threshold timer fired. Returns `.nothing` if the load already
    /// finished, so a timer that outlives its load cannot draw anything.
    mutating func thresholdPassed() -> Action {
        guard phase == .armed else { return .nothing }
        phase = .playing
        return .begin
    }

    /// The active tab changed, or the view is leaving the window. The caller
    /// tears `.end` down instantly rather than animating it — the page it
    /// belonged to is not on screen any more.
    mutating func cancel() -> Action {
        defer { phase = .idle }
        switch phase {
        case .idle: return .nothing
        case .armed: return .disarm
        case .playing: return .end
        }
    }
}

#if DEBUG
    extension ReloadBloomTimeline {
        /// The §7 rules that are easy to break, as asserts. Call it beside
        /// `TokenCheck.run()` in `AppDelegate`.
        static func selfCheck() {
            var timeline = ReloadBloomTimeline()

            // §7: a load that finishes inside the threshold plays nothing at all.
            assert(timeline.loading(true) == .arm)
            assert(timeline.loading(false) == .disarm)
            assert(timeline.thresholdPassed() == .nothing, "a late timer must not draw")
            assert(timeline.phase == .idle)

            // A slow load plays the whole thing, exactly once.
            assert(timeline.loading(true) == .arm)
            assert(timeline.thresholdPassed() == .begin)
            assert(timeline.loading(true) == .nothing, "progress ticks are not edges")
            assert(timeline.thresholdPassed() == .nothing, "the threshold fires once")
            assert(timeline.loading(false) == .end)
            assert(timeline.loading(false) == .nothing, "idle stays idle")

            // Switching tabs tears down whatever is up, and only what is up.
            assert(timeline.loading(true) == .arm)
            assert(timeline.cancel() == .disarm)
            assert(timeline.loading(true) == .arm)
            assert(timeline.thresholdPassed() == .begin)
            assert(timeline.cancel() == .end)
            assert(timeline.cancel() == .nothing)
        }
    }
#endif
