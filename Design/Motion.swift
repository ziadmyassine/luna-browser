//
//  Motion.swift
//  Luna
//
//  Every row of `docs/UI-SPEC.md` §6, plus the §7 reload timings §6 defers to,
//  as named specs. No duration literal belongs in a view.
//
//  §6's rule: nothing exceeds 0.35 s except the two entries tied to real work
//  rather than taste — the §5.1 particle sweep (0.40 s) and the §7 reload arc
//  (bound to load progress). `TokenCheck` enforces that.
//
//  Reduce Motion (§21.2): **every** entry degrades to instant. `animate` and
//  `springAnimation` below do that for you — a view that hand-rolls a
//  `CAAnimation` must check `Tokens.Motion.reduceMotion` itself.
//

import AppKit
import QuartzCore

/// One row of §6.
///
/// `response`/`damping` are non-nil for a spring and nil for a timed curve;
/// `duration` is always meaningful, so a caller that just needs "how long until
/// this settles" never has to branch.
struct MotionSpec: Sendable {

    /// The curve a timed spec animates on. Ignored by springs.
    enum Curve: Sendable { case easeOut, easeInOut, linear }

    var duration: TimeInterval
    /// SwiftUI-style spring response, in seconds. Nil for a timed spec.
    var response: Double?
    /// Spring damping *fraction*, 0...1. Nil for a timed spec.
    var damping: Double?
    var curve: Curve

    /// A timed spec.
    init(_ duration: TimeInterval, _ curve: Curve = .easeOut) {
        self.duration = duration
        self.response = nil
        self.damping = nil
        self.curve = curve
    }

    /// A spring. `settling` is what §6 quotes as the visible duration; where §6
    /// gives only a response, it is the response.
    init(response: Double, damping: Double, settling duration: TimeInterval) {
        self.duration = duration
        self.response = response
        self.damping = damping
        self.curve = .easeOut
    }

    var isSpring: Bool { response != nil }

    var timingFunction: CAMediaTimingFunction {
        switch curve {
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: CAMediaTimingFunction(name: .easeInEaseOut)
        case .linear: CAMediaTimingFunction(name: .linear)
        }
    }

    /// A `CASpringAnimation` matching `response`/`damping`, or nil when this is
    /// not a spring **or** Reduce Motion is on — in both cases the caller should
    /// set the value outright instead of animating it.
    ///
    /// Unit mass, so SwiftUI's conversion applies directly:
    /// `stiffness = (2π / response)²`, `damping = 4π · fraction / response`.
    func springAnimation(keyPath: String) -> CASpringAnimation? {
        guard !Tokens.Motion.reduceMotion, let response, let damping else { return nil }
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * damping / response
        animation.duration = animation.settlingDuration
        return animation
    }
}

extension Tokens {

    /// §6, in full. Companion values that §6 states inline (a cross-fade, a
    /// stagger, an intent delay) sit next to the spec they belong to.
    enum Motion {

        // MARK: Rows and controls (§3.4, §3.1)

        /// Row hover fill, lifting to 6 % (§3.4).
        static let rowHover = MotionSpec(0.12)
        /// Control button hover *lift* — the fill, not the border (§3.1).
        static let controlHover = MotionSpec(0.10)
        /// The selected-row pill sliding to a new row.
        static let selectedRowMove = MotionSpec(response: 0.28, damping: 0.80, settling: 0.20)

        // MARK: Tabs and Spaces

        /// Tab insert / remove: height + fade, and the list must not jump.
        static let tabInsert = MotionSpec(response: 0.22, damping: 0.85, settling: 0.22)
        /// §3.3's selection glow appearing on the tile you just pressed:
        /// opacity and a **1.06 → 1** scale together, from the tile's centre.
        ///
        /// **A spring, and slower than `controlHover`.** Hover is a state the
        /// pointer can scrub in and out of a dozen times a second, so it is
        /// short and timed; the glow answers a *click*, happens once, and is
        /// the one thing on screen saying which tile you just landed on.
        ///
        /// It contracts rather than growing — `EssentialGlowView.flare` has
        /// why — so the pop is in the *start*, and the damping is only there to
        /// keep the settle from ringing: at 0.75 the undershoot is a tenth of a
        /// point, which is nothing to see and everything to feel.
        static let essentialGlow = MotionSpec(response: 0.22, damping: 0.75, settling: 0.24)
        /// §6 gives only a response and damping for the Space switch itself.
        static let spaceSwitch = MotionSpec(response: 0.30, damping: 0.70, settling: 0.30)
        /// The sidebar content cross-fade that rides along with it.
        static let spaceSwitchCrossfade = MotionSpec(0.18)

        // MARK: Layout

        /// Sidebar collapse / expand — the width half.
        static let sidebarCollapse = MotionSpec(0.20)
        /// …and the opacity half, which finishes first.
        static let sidebarCollapseOpacity = MotionSpec(0.12)
        /// Sidebar ↔ top bar (§4.1). Traffic lights must re-anchor **inside this
        /// transaction**, never as a second step, or they visibly jump.
        static let layoutSwitch = MotionSpec(0.30, .easeInOut)
        /// The 20 ms stagger §4.1 puts on the bar's contents.
        static let layoutSwitchStagger: TimeInterval = 0.020
        /// Split divider snap (§6).
        static let splitDividerSnap = MotionSpec(0.12)
        /// Content card → page fullscreen (§3.6).
        static let cardFullscreen = MotionSpec(0.30, .easeInOut)

        // MARK: Transient surfaces

        /// Command Bar in: scale 0.96 → 1.0 + fade, anchored 20 % from the top.
        static let commandBarIn = MotionSpec(response: 0.18, damping: 0.80, settling: 0.18)
        /// Downloads popover in: scale 0.94 → 1.0, from the tail anchor (§5).
        static let popoverIn = MotionSpec(response: 0.20, damping: 0.80, settling: 0.20)
        /// Hover-peek reveal — the slide. `hoverPeekDelay` is the intent delay
        /// that precedes it; the §3.7 resize handle uses the same 0.10 s.
        static let hoverPeek = MotionSpec(0.15)
        static let hoverPeekDelay: TimeInterval = 0.10
        /// §5: the popover auto-dismisses after 4 s, and hovering cancels the timer.
        static let downloadsAutoDismiss: TimeInterval = 4.0

        // MARK: Page-derived tint (§2, §8.3)

        /// URL pill theme wash. Pair with `Tokens.wash(_:over:upTo:keeping:)`.
        static let themeWash = MotionSpec(0.25, .easeInOut)

        // MARK: Exempt from the 0.35 s budget

        /// §5.1's particle sweep, total 0.40 s: 0.22 s dissolve, 0.18 s settle,
        /// 0.04 s per-particle stagger. Under Reduce Motion it does not run at
        /// all — the filename simply appears.
        static let downloadsParticleSweep = MotionSpec(0.40)
        static let particleDissolve = MotionSpec(0.22)
        static let particleSettle = MotionSpec(0.18)
        static let particleStagger: TimeInterval = 0.04

        /// §7's reload bloom. The arc's *hold* is bound to real load progress,
        /// which is why there is no spec for it: only the in and out are timed.
        static let reloadArcIn = MotionSpec(0.25)
        static let reloadArcOut = MotionSpec(0.30)
        /// De-blur stagger across the viewport, top to bottom (§7).
        static let reloadDeblurStagger: TimeInterval = 0.040
        /// A load finishing faster than this plays nothing — no flash on a
        /// cached reload (§7).
        static let reloadSkipThreshold: TimeInterval = 0.15

        /// §3.4's loading shimmer: a highlight sweeping across the row title,
        /// **not a spinner**. 1.1 s per pass, repeating for as long as the tab
        /// is loading.
        ///
        /// **Legitimately exempt from §6's 0.35 s cap.** That cap governs
        /// *discrete transitions* — the time between a user's action and the
        /// interface settling — and this one never settles: it is a repeating
        /// progress indicator whose duration is a rate, not a delay. Nobody
        /// waits 1.1 s for it, because nothing is pending on it finishing.
        /// Squeezed under 0.35 s it would read as a strobe on a row the user
        /// is trying to read, which is worse on every axis including §21.2's.
        /// `TokenCheck` checks it **by value**, next to §5.1's particle sweep,
        /// rather than against the budget — so deleting the exemption fails the
        /// check instead of quietly capping a loading indicator at a flicker.
        ///
        /// Linear: a repeating ease-out pulses at the seam where it loops.
        /// Reduce Motion: do not run it — the title simply stays put (§21.2).
        static let rowShimmer = MotionSpec(1.10, .linear)

        // MARK: Accessibility

        /// §21.2. Read live on every access — the user can turn Reduce Motion
        /// on while Luna is running, and a value cached at launch is a bug.
        static var reduceMotion: Bool { Tokens.A11y.reduceMotion }

        /// Runs `changes` with **every** animation off — implicit AppKit ones and
        /// CoreAnimation's alike.
        ///
        /// This is for manual layout: a `layout()` or `viewDidLayout` that sets
        /// subview frames from `bounds`. Such a pass can run inside somebody
        /// else's animation transaction — the §4.1 layout switch calls
        /// `layoutSubtreeIfNeeded()` with `allowsImplicitAnimation` on — and
        /// every `frame` assignment then goes through the animator instead of
        /// landing. The sidebar came back from top-bar layout with its control
        /// buttons 1001 pt to the right and its list 1070 pt wide: the frames
        /// the pass computed were correct and were never applied.
        ///
        /// A frame computed from `bounds` is a consequence of the layout, not a
        /// change to animate. The animation belongs to whatever moved `bounds`.
        @MainActor
        static func immediately(_ changes: () -> Void) {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
            NSAnimationContext.endGrouping()
        }

        /// Runs `changes` on `spec`'s timing, or instantly under Reduce Motion.
        ///
        /// Timed specs only. A spring belongs in a `CASpringAnimation` — ask
        /// `spec.springAnimation(keyPath:)` for one.
        @MainActor
        static func animate(
            _ spec: MotionSpec,
            _ changes: (NSAnimationContext) -> Void,
            completion: (@Sendable () -> Void)? = nil
        ) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0 : spec.duration
                context.timingFunction = spec.timingFunction
                changes(context)
            }, completionHandler: completion)
        }
    }
}
