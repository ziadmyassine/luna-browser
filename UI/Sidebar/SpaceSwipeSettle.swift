//
//  SpaceSwipeSettle.swift
//  Luna
//
//  The rest of §30.9's gesture, after the fingers have gone: the page carried
//  the remaining distance on the speed the hand let go at.
//
//  `Motion.spaceSettle(across:at:)` is the timing half — the duration is the
//  distance over the speed, so the page leaves the fingers at their speed. This
//  is the other half: one clock for the whole read-out. The column and the still
//  are transforms, but the §3.5 strip is frames and the §8.2a wash a gradient;
//  animating only the transforms left the strip and the wash arriving while the
//  column was a third of the way there. So the travel is tweened, and applied
//  the one way it is applied while a finger is down.
//
//  A display link rather than a timer, for `DownloadFlightView`'s reason: it
//  should be asked once per frame by the thing that draws them.
//

import AppKit

/// Runs a released swipe home, one frame at a time.
@MainActor
final class SpaceSwipeSettle {

    private var link: CADisplayLink?
    /// The promise that the journey ends, whether or not anything is drawing
    /// it. See `run`.
    private var deadline: Task<Void, Never>?
    private var startedAt: CFTimeInterval = 0
    private var spec = MotionSpec(0)
    private var from = SpaceSwipe.rest
    private var to = SpaceSwipe.rest
    private var onFrame: ((SpaceSwipe) -> Void)?
    private var onArrival: (() -> Void)?
    /// The view the link is taken from. A `CADisplayLink` belongs to the screen
    /// its view is on, which is how this stays right when the window is dragged
    /// to a display running at another rate.
    private unowned let host: NSView

    init(host: NSView) {
        self.host = host
    }

    /// Travels from `from` to `to` on `spec`'s curve, handing every frame to
    /// `onFrame`, and calls `onArrival` once it is there.
    ///
    /// `onArrival` runs exactly once and always — under Reduce Motion, and when
    /// a second release replaces this one mid-flight — because what waits on it
    /// is the Space switch. So it does not depend on the display link: a link
    /// does not fire for a window that is off screen, minimised or on a sleeping
    /// display, and the switch would wait on the animation being watched. The
    /// link paints and a deadline arrives, whichever gets there first.
    func run(
        from: SpaceSwipe,
        to: SpaceSwipe,
        on spec: MotionSpec,
        onFrame: @escaping (SpaceSwipe) -> Void,
        onArrival: @escaping () -> Void
    ) {
        stop()
        guard !Tokens.Motion.reduceMotion, spec.duration > 0 else {
            // §21.2 takes the journey away, not the arrival.
            onFrame(to)
            return onArrival()
        }
        self.spec = spec
        self.from = from
        self.to = to
        self.onFrame = onFrame
        self.onArrival = onArrival
        startedAt = CACurrentMediaTime()
        let link = host.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        // A couple of frames of grace, so this is the safety net and never the
        // thing that cuts a running animation short.
        let grace = spec.duration + 2.0 / 60
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(grace))
            guard !Task.isCancelled else { return }
            self?.arrive()
        }
    }

    /// Abandons a journey without arriving — the column went away, or the
    /// window did. Silent, for `SpaceSwipeController.cancel`'s reason.
    func stop() {
        link?.invalidate()
        link = nil
        deadline?.cancel()
        deadline = nil
        onFrame = nil
        onArrival = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startedAt
        onFrame?(Self.lerp(from, to, spec.progress(at: elapsed)))
        guard elapsed >= spec.duration else { return }
        arrive()
    }

    /// The end of the journey, from whichever of the two clocks got here first.
    private func arrive() {
        guard let arrived = onArrival else { return }
        // The last frame is stated rather than assumed: the link stops on the
        // frame after the duration, and the deadline may not have drawn any.
        onFrame?(to)
        // Taken before the call, so an arrival that starts another gesture
        // finds this one already finished rather than still holding the link.
        stop()
        arrived()
    }

    /// `fraction` of the way from one read-out to another.
    ///
    /// Only the two continuous fields travel. `landing` and `createsSpace` are
    /// answers to "what would letting go do", and the letting go has happened —
    /// carrying them would be a read-out offering a decision that has been
    /// made.
    static func lerp(_ from: SpaceSwipe, _ to: SpaceSwipe, _ fraction: CGFloat) -> SpaceSwipe {
        SpaceSwipe(
            travel: from.travel + (to.travel - from.travel) * fraction,
            creation: from.creation + (to.creation - from.creation) * fraction,
            landing: nil,
            createsSpace: false
        )
    }
}
