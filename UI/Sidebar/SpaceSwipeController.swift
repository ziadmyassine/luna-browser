//
//  SpaceSwipeController.swift
//  Luna
//
//  The wiring half of §30.9's swipe: the events, the live read-out and the one
//  commit — plus the two views that offer it a scroll before taking one.
//
//  Split out of `SpaceSwipe.swift` when that file crossed SwiftLint's 400-line
//  limit, along the seam that file's own header names. `SpaceSwipe` is pure
//  arithmetic and is asserted by `SpaceSwipeTests`; everything here touches an
//  `NSEvent`, and `SpaceGestureTests` drives it with synthesized ones.
//

import AppKit
import BrowserKit

/// The gesture itself: the events, the live read-out, and the one commit.
@MainActor
final class SpaceSwipeController {

    /// The Spaces, newest answer each time — the session is the truth and this
    /// holds none of it.
    var spaces: () -> (all: [UUID], active: UUID?) = { ([], nil) }
    /// The page's own width, asked for fresh every time: the §3.7 handle can be
    /// dragged mid-gesture, and a ruler measured once at `.began` would be the
    /// wrong ruler by the release.
    var span: () -> CGFloat = { 0 }
    /// The read-out: the dot strip, the wash, and the pages that ride along.
    var onUpdate: ((SpaceSwipe) -> Void)?
    /// The fingers came up. Carries where the gesture had got to and whether
    /// it was a release rather than a cancel.
    ///
    /// What happens next is not this object's call. There is a page still
    /// half way across the column when the hand leaves, and settling it is the
    /// same act as deciding what the gesture meant — see
    /// `SidebarSpaceGestures.settle`. A controller that switched the Space here
    /// would switch it under a column that had not finished moving.
    var onFinish: ((_ state: SpaceSwipe, _ speed: CGFloat, _ committing: Bool) -> Void)?

    /// Points accumulated in this gesture, positive toward the next Space.
    private var offset: CGFloat = 0
    /// Cross-axis travel, which is how a vertical scroll that wandered is told
    /// from a horizontal one that meant it.
    private var drift: CGFloat = 0
    private var isTracking = false
    /// When the last event this gesture counted arrived, for
    /// `Metric.spaceSwipeSpeed`'s ceiling. 0 means "nothing yet".
    private var lastEventTime: TimeInterval = 0
    /// How fast the hand is moving right now, in points of damped travel
    /// per second — the same units `offset` is kept in, so `spaceFlickSpeed`
    /// can be one plain number rather than one per trackpad.
    ///
    /// Smoothed, because a single event is not a hand. Trackpad deltas arrive
    /// unevenly enough that any one of them can read at twice or half the
    /// speed the fingers are actually going, and a release that landed on one
    /// of those would turn a page the user was only looking at.
    private var speed: CGFloat = 0
    /// This gesture was ours, and its momentum tail is ours too — see
    /// `scrollWheel`.
    private var ownsMomentum = false

    /// Handles `event` if it is this gesture, and says so.
    ///
    /// Momentum never decides anything, and it is not handed back either. A
    /// flick's momentum phase keeps delivering deltas for up to a second after
    /// the fingers have gone: a gesture that kept counting them would commit —
    /// or worse, create — long after the hand had stopped asking, and one that
    /// released them to the list would let a Space switch end in the list
    /// lurching sideways under the new Space's rows. So the tail of a gesture
    /// this took is swallowed, and the tail of one it did not is passed on
    /// untouched.
    ///
    /// Every phase is seen, including the ones with no travel in them. The
    /// `.ended` event of a horizontal swipe carries zero deltas, so a caller
    /// that routed events here by axis would never deliver the one event that
    /// commits the gesture. `SidebarScrollView` therefore offers all of them
    /// and takes this answer for whether it keeps the event — which is also why
    /// `.ended` resets even when nothing was being tracked: an untracked
    /// gesture still left travel in `offset`, and the next one must not inherit
    /// it.
    func scrollWheel(with event: NSEvent) -> Bool {
        guard event.momentumPhase.isEmpty else { return ownsMomentum }
        switch event.phase {
        case .began:
            reset()
            return false
        case .changed:
            return track(event)
        case .ended, .cancelled:
            guard isTracking else {
                reset()
                return false
            }
            finish(committing: event.phase == .ended, at: event.timestamp)
            return true
        default:
            return false
        }
    }

    /// Cancels an unfinished gesture — the sidebar went away, or the window
    /// did. Silent: nothing is committed by a gesture nobody finished.
    func cancel() {
        guard isTracking else { return }
        finish(committing: false)
    }

    private func reset() {
        offset = 0
        drift = 0
        speed = 0
        isTracking = false
        ownsMomentum = false
        lastEventTime = 0
    }

    /// How much of `speed` a fresh event is worth.
    ///
    /// Light, and deliberately lighter than it looks. At 60 Hz this is a
    /// half-life of about two frames, so the number answers a hand that is
    /// genuinely accelerating within a couple of events and shrugs off the one
    /// jittery delta that a lift or a re-grip produces. Heavier and a flick is
    /// missed; lighter and a twitch is read as one.
    private static let smoothing: CGFloat = 0.3

    /// How long after the last counted event a release still carries its speed.
    ///
    /// Three frames. A hand that pushed the page out, came to rest and then
    /// lifted has not flicked — but the events stop the moment it rests, so
    /// without this the gesture would be judged on the speed it had before
    /// it stopped. That is exactly the create gesture, and it would never make
    /// a Space.
    private static let flickWindow: TimeInterval = 3.0 / 60

    private func track(_ event: NSEvent) -> Bool {
        // `scrollingDeltaX` is positive when the fingers move right, which
        // on this platform means "back" — Safari's two-finger swipe, and every
        // horizontal list in AppKit. Toward the next Space is therefore the
        // negative one, and this is the single place the sign is flipped.
        let step = -Self.damped(event.scrollingDeltaX, since: lastEventTime, at: event.timestamp)
        let interval = Self.interval(since: lastEventTime, at: event.timestamp)
        // Damped against damped. `drift` used to add the raw
        // `scrollingDeltaY` to a comparison with an `offset` the ceiling had
        // already folded down, so a brisk horizontal swipe with any wobble in
        // it lost to its own wobble and the list kept the scroll. The two sides
        // of the guard have to have come through the same curve or it is not a
        // comparison. Taken before `lastEventTime` moves, so both axes of one
        // event are measured over one interval.
        drift += abs(Self.damped(event.scrollingDeltaY, since: lastEventTime, at: event.timestamp))
        let instant = step / CGFloat(interval)
        // The first event of a gesture has nothing to smooth against, and
        // easing up from zero would under-read exactly the gesture the speed
        // exists to catch: a flick is over in five or six events.
        speed = lastEventTime > 0 ? speed + (instant - speed) * Self.smoothing : instant
        offset += step
        lastEventTime = event.timestamp
        guard isTracking else {
            // A vertical flick always carries a little sideways travel, so the
            // gesture has to out-travel its own drift before it claims the
            // event. Until it does, the list keeps every scroll.
            guard abs(offset) > Tokens.Metric.dragThreshold, abs(offset) > drift else { return false }
            isTracking = true
            return update()
        }
        return update()
    }

    /// One event's `scrollingDeltaX`, with the system's acceleration bent back
    /// off the top.
    ///
    /// A trackpad does not report distance; it reports scaled distance.
    /// macOS multiplies a precise scroll by how fast the fingers were moving,
    /// so the same eighty points of hand arrive as eighty points when dragged
    /// and as three hundred when flicked — and a page bound to that delta races
    /// out from under the fingers pushing it.
    ///
    /// The curve bends; it does not stop. This was a hard clip for one
    /// build and a hard clip is a worse gesture than no damping at all: every
    /// event of a real swipe lands above the ceiling, so every event comes back
    /// as exactly the ceiling and the page travels at one fixed speed no
    /// matter what the hand does. The gesture stops being followed. `tanh` is
    /// the same ceiling with the corner taken off — its slope is 1 at the
    /// origin, so movement well under `Metric.spaceSwipeSpeed` passes through
    /// as itself, and it flattens smoothly toward the ceiling rather than
    /// meeting it at an edge. There is no boundary for a hand to sit on top of
    /// and no discontinuity for a jittery one to chatter across.
    ///
    /// The interval is clamped at both ends rather than trusted. A first
    /// `.changed` has nothing to measure from, and a frame the app spent
    /// elsewhere would otherwise hand one event the budget of ten — so the gap
    /// is read as a frame in both cases, which is what it was in all but name.
    ///
    /// Internal rather than private so `SpaceSwipeTests` can assert the curve;
    /// nothing outside this file calls it.
    static func damped(_ delta: CGFloat, since last: TimeInterval, at now: TimeInterval) -> CGFloat {
        let ceiling = Tokens.Metric.spaceSwipeSpeed * CGFloat(interval(since: last, at: now))
        guard ceiling > 0 else { return 0 }
        return ceiling * CGFloat(tanh(Double(delta / ceiling)))
    }

    /// How much time one event is allowed to account for.
    ///
    /// Shared by the ceiling and by `speed` so the two cannot disagree about
    /// what "per second" means — a speed measured over a different interval
    /// than the distance it came from is not a speed.
    static func interval(since last: TimeInterval, at now: TimeInterval) -> TimeInterval {
        let frame: TimeInterval = 1.0 / 60
        return last > 0 ? min(max(now - last, 1.0 / 240), frame) : frame
    }

    @discardableResult
    private func update() -> Bool {
        let state = spaces()
        guard let active = state.active, let index = state.all.firstIndex(of: active) else { return false }
        // No speed while the fingers are down: `landing` and `createsSpace`
        // are answers to a question only a release asks, and a read-out that
        // flickered between "this turns the page" and "this does not" as the
        // hand sped up and slowed down would be drawing the future.
        onUpdate?(SpaceSwipe.resolve(offset: offset, span: span(), activeIndex: index, count: state.all.count))
        return true
    }

    private func finish(committing: Bool, at now: TimeInterval = 0) {
        let state = spaces()
        let active = state.active.flatMap { state.all.firstIndex(of: $0) }
        // A hand that stopped before it lifted is not flicking — see
        // `flickWindow`. A cancel has no release at all and carries none.
        let released = now > 0 && lastEventTime > 0 && now - lastEventTime <= Self.flickWindow ? speed : 0
        let resolved = active.map {
            SpaceSwipe.resolve(
                offset: offset, speed: released, span: span(), activeIndex: $0, count: state.all.count
            )
        } ?? .rest
        reset()
        ownsMomentum = true
        onFinish?(resolved, released, committing)
    }
}

/// The sidebar's own plane, which is where §30.9's swipe is caught.
///
/// A view rather than a gesture recogniser: `NSPanGestureRecognizer` does not
/// see a trackpad scroll, only a click-drag, and the two-finger slide the
/// feature is named after arrives as `scrollWheel` with a phase. `NSEvent`'s
/// own `trackSwipeEvent` was the other candidate and cannot express this
/// gesture: it clamps the amount it reports to the range it was given, so the
/// travel past the last Space — the half that makes one — is exactly what it
/// throws away.
@MainActor
final class SidebarRootView: NSView {

    /// Returns true when the swipe took the event.
    var onScroll: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        guard onScroll?(event) != true else { return }
        super.scrollWheel(with: event)
    }
}

/// §3.4's list, offering every scroll to §30.9's swipe before taking it.
///
/// The list scrolls in one axis and `NSScrollView` consumes both, so without
/// this the swipe would work everywhere on the sidebar except over the rows —
/// which is most of the sidebar, and the part a hand rests on.
///
/// It offers the swipe every event rather than deciding by axis, because
/// the events that matter most have no axis: `.began` carries no travel and
/// `.ended` carries none either, and a scroll view that kept those two would
/// leave the gesture unable to start cleanly or to finish at all. The swipe
/// answers for each one — it claims nothing until a finger has out-travelled
/// its own drift — and a scroll it does not claim reaches `super` exactly as
/// it always did.
@MainActor
final class SidebarScrollView: NSScrollView {

    /// Returns true when the swipe took the event.
    var onScroll: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        guard onScroll?(event) != true else { return }
        super.scrollWheel(with: event)
    }
}
