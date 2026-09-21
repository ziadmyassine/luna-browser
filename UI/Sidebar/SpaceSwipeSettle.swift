//
//  SpaceSwipeSettle.swift
//  Luna
//
//  The rest of §30.9's gesture, after the fingers have gone: the page carried
//  the remaining distance on the speed the hand let go at.
//
//  **A settle is not a transition, it is the end of a movement somebody else
//  started**, and treating it as a transition is what made the swipe feel like
//  two separate things joined at the release. `Motion.spaceSettle(across:at:)`
//  is the timing half of that — the duration is the distance over the speed, so
//  the page leaves the fingers at the speed the fingers had. This is the other
//  half: **one clock for the whole read-out.**
//
//  **Everything §30.9 draws is a function of one number**, and only some of
//  those things are layer properties. The column and the still are transforms
//  and animate themselves; the §3.5 dot strip is a row of *frames recomputed
//  from the travel*, and the §8.2a wash is a gradient mixed from it. Animating
//  the first two and setting the last two outright is exactly what shipped, and
//  what it looks like is the strip snapping to the Space it is heading for, and
//  the whole sidebar changing colour, while the column is still a third of the
//  way there. Nothing is wrong in any one of those views. They are simply not
//  being asked the same question at the same time.
//
//  So the number is tweened and the read-out is applied the one way it is
//  applied while a finger is down. The release is a hand that kept going, which
//  is both the simplest thing to implement and the thing it should look like.
//
//  A display link rather than a timer, for `ParticleSweepView`'s reason: this
//  draws a frame, so it should be asked once per frame by the thing that draws
//  them — and on a 120 Hz panel that is 120 times a second, not 60.
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
    /// **`onArrival` runs exactly once and always**, including when Reduce
    /// Motion takes the journey away entirely and when a second release
    /// replaces this one mid-flight. What waits on it is the Space switch, and
    /// a switch that did not happen because an animation was interrupted is a
    /// gesture the user performed and the app ignored.
    ///
    /// **Which is why the arrival does not depend on the display link.** A
    /// `CADisplayLink` is a request to be called when a screen is about to draw
    /// and nothing more: a view in a window that is off screen, minimised or on
    /// a sleeping display is not drawn, so the link does not fire and the
    /// journey never reaches its end. Hanging the commit off it makes the Space
    /// switch conditional on the animation being *watched*. So the link paints
    /// and a deadline arrives, whichever gets there first — and on the normal
    /// path, where the link is ticking, it is the link.
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
        // frame *after* the duration, and the deadline may not have drawn any.
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
