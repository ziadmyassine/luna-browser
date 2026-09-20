//
//  SpaceSwipe.swift
//  Luna
//
//  §30.9 / SPACES-SPEC D-S12's two-finger sidebar swipe: slide sideways
//  anywhere on the sidebar to change Space, and keep sliding past the last one
//  to make a new one.
//
//  **The arithmetic is a value type and the wiring is a controller**, because
//  the two fail for different reasons and only one of them can be tested
//  without a trackpad. `SpaceSwipe.resolve` is pure: given how far the fingers
//  have travelled, which Space is active and how many there are, it says where
//  the strip's indicator sits, how full the `+` ring is, and what letting go
//  would do. Every rule worth arguing about — the half-a-Space commit, the
//  clamp at the leading end, the doubled travel that makes a Space — is in
//  those twenty lines and is asserted by `SpaceSwipeTests`.
//
//  **One Space per gesture, however hard the flick**, and this is the rule that
//  was missing. The travel used to accumulate without a ceiling, so a single
//  firm swipe from the first of two Spaces ran 80 pt to reach the second and
//  then kept going into the 160 pt that makes a new one — and the gesture the
//  user performs to *change* Space created one instead. A trackpad flick is
//  accelerated by the system and routinely delivers several hundred points in
//  one stroke; no threshold survives that. A page swipe turns one page.
//
//  So the create zone is not somewhere a long swipe can reach. It is only
//  there **when there is no next Space**, which is the only situation in which
//  "further" can mean anything other than "the one after this".
//
//  **Two thresholds, deliberately unequal.** Moving between Spaces commits at
//  half of `Metric.spaceSwipeTravel`; creating one needs the whole of
//  `Metric.spaceCreateTravel`, which is twice as far again. That asymmetry is
//  the resistance the feature was asked for: reaching the end of the Spaces you
//  have is not the same act as making another, and it should not cost the same.
//
//  **Nothing is decided while the fingers are down.** `.changed` only moves the
//  read-out; the switch and the create both happen on `.ended`. A gesture that
//  committed as it crossed a threshold would make an overshoot unrecoverable,
//  and the whole point of the ring is that you can see what you are about to
//  get while you can still not get it.
//

import AppKit
import BrowserKit

/// Where a swipe has got to, and what letting go now would do.
struct SpaceSwipe: Equatable {

    /// The indicator's position relative to the active Space, in Spaces: −1 is
    /// the previous one, +1 the next, and **it never leaves that range**. Where
    /// there is no next Space, +1 is the slot the `+` stands in instead.
    var travel: CGFloat
    /// 0…1 — how much of §30.9's ring is drawn. 1 is a closed circle.
    var creation: CGFloat
    /// The index a release would switch to, or nil for "stay where you are".
    var landing: Int?
    /// A release would make a new Space. Never true at the same time as
    /// `landing`: the fingers have left the Spaces that exist.
    var createsSpace: Bool

    /// - Parameters:
    ///   - offset: finger travel in points, **positive toward the next Space**.
    ///     `SpaceSwipeController` flips `scrollingDeltaX` into this convention;
    ///     see `accumulate`.
    ///   - activeIndex: the Space the window is in.
    ///   - count: how many there are.
    static func resolve(offset: CGFloat, activeIndex: Int, count: Int) -> SpaceSwipe {
        guard count > 0, activeIndex >= 0, activeIndex < count else { return .rest }
        let reach = offset / Tokens.Metric.spaceSwipeTravel

        guard offset > 0 else {
            // Backward, and the first Space simply stops: a rubber band here
            // would be motion that means nothing, which is worse than none.
            guard activeIndex > 0 else { return .rest }
            let travel = max(reach, -1)
            return SpaceSwipe(
                travel: travel,
                creation: 0,
                landing: travel <= -0.5 ? activeIndex - 1 : nil,
                createsSpace: false
            )
        }

        // Forward, with a Space to go to. **Capped at one**, so a hard flick
        // arrives at the next Space rather than sailing through it — see the
        // file header for what happened without this line.
        guard activeIndex == count - 1 else {
            let travel = min(reach, 1)
            return SpaceSwipe(
                travel: travel,
                creation: 0,
                landing: travel >= 0.5 ? activeIndex + 1 : nil,
                createsSpace: false
            )
        }

        // Forward from the last Space, where "further" has only one meaning.
        // The travel stops being a distance and becomes an intention: the
        // indicator crosses into the `+`'s slot at exactly the rate the ring
        // fills, and arrives as it closes. One mark, one meaning.
        let creation = min(offset / Tokens.Metric.spaceCreateTravel, 1)
        return SpaceSwipe(travel: creation, creation: creation, landing: nil, createsSpace: creation >= 1)
    }

    /// Nothing happening — the resting read-out, and what a gesture in a window
    /// with no Spaces resolves to.
    static let rest = SpaceSwipe(travel: 0, creation: 0, landing: nil, createsSpace: false)
}

/// The gesture itself: the events, the live read-out, and the one commit.
@MainActor
final class SpaceSwipeController {

    /// The Spaces, newest answer each time — the session is the truth and this
    /// holds none of it.
    var spaces: () -> (all: [UUID], active: UUID?) = { ([], nil) }
    /// The read-out: the dot strip, the wash, and the pages that ride along.
    var onUpdate: ((SpaceSwipe) -> Void)?
    /// The fingers came up. Carries where the gesture had got to and whether
    /// it was a release rather than a cancel.
    ///
    /// **What happens next is not this object's call.** There is a page still
    /// half way across the column when the hand leaves, and settling it is the
    /// same act as deciding what the gesture meant — see
    /// `SidebarSpaceGestures.settle`. A controller that switched the Space here
    /// would switch it under a column that had not finished moving.
    var onFinish: ((SpaceSwipe, Bool) -> Void)?

    /// Points accumulated in this gesture, positive toward the next Space.
    private var offset: CGFloat = 0
    /// Cross-axis travel, which is how a vertical scroll that wandered is told
    /// from a horizontal one that meant it.
    private var drift: CGFloat = 0
    private var isTracking = false
    /// This gesture was ours, and its momentum tail is ours too — see
    /// `scrollWheel`.
    private var ownsMomentum = false

    /// Handles `event` if it is this gesture, and says so.
    ///
    /// **Momentum never decides anything, and it is not handed back either.** A
    /// flick's momentum phase keeps delivering deltas for up to a second after
    /// the fingers have gone: a gesture that kept counting them would commit —
    /// or worse, create — long after the hand had stopped asking, and one that
    /// released them to the list would let a Space switch end in the list
    /// lurching sideways under the new Space's rows. So the tail of a gesture
    /// this took is swallowed, and the tail of one it did not is passed on
    /// untouched.
    ///
    /// **Every phase is seen, including the ones with no travel in them.** The
    /// `.ended` event of a horizontal swipe carries zero deltas, so a caller
    /// that routed events here by axis would never deliver the one event that
    /// commits the gesture. `SidebarScrollView` therefore offers *all* of them
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
            finish(committing: event.phase == .ended)
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
        isTracking = false
        ownsMomentum = false
    }

    private func track(_ event: NSEvent) -> Bool {
        // `scrollingDeltaX` is positive when the fingers move **right**, which
        // on this platform means "back" — Safari's two-finger swipe, and every
        // horizontal list in AppKit. Toward the *next* Space is therefore the
        // negative one, and this is the single place the sign is flipped.
        offset -= event.scrollingDeltaX
        drift += abs(event.scrollingDeltaY)
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

    @discardableResult
    private func update() -> Bool {
        let state = spaces()
        guard let active = state.active, let index = state.all.firstIndex(of: active) else { return false }
        onUpdate?(SpaceSwipe.resolve(offset: offset, activeIndex: index, count: state.all.count))
        return true
    }

    private func finish(committing: Bool) {
        let state = spaces()
        let active = state.active.flatMap { state.all.firstIndex(of: $0) }
        let resolved = active.map {
            SpaceSwipe.resolve(offset: offset, activeIndex: $0, count: state.all.count)
        } ?? .rest
        reset()
        ownsMomentum = true
        onFinish?(resolved, committing)
    }
}

/// The sidebar's own plane, which is where §30.9's swipe is caught.
///
/// A view rather than a gesture recogniser: `NSPanGestureRecognizer` does not
/// see a trackpad *scroll*, only a click-drag, and the two-finger slide the
/// feature is named after arrives as `scrollWheel` with a phase. `NSEvent`'s
/// own `trackSwipeEvent` was the other candidate and cannot express this
/// gesture: it clamps the amount it reports to the range it was given, so the
/// travel *past* the last Space — the half that makes one — is exactly what it
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
/// **It offers the swipe every event rather than deciding by axis**, because
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
