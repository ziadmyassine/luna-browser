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

extension Tokens {

    /// §6, in full. Companion values that §6 states inline (a cross-fade, a
    /// stagger, an intent delay) sit next to the spec they belong to.
    enum Motion {

        // MARK: Rows and controls (§3.4, §3.1)

        /// Row hover fill, lifting to 6 % (§3.4).
        static let rowHover = MotionSpec(0.12)
        /// Control button hover *lift* — the fill, not the border (§3.1).
        static let controlHover = MotionSpec(0.10)
        /// **A glass control being pressed**, and the one place §6 asks for a
        /// spring on a state the pointer holds.
        ///
        /// The fill is the hover fill again, one step up — `wash` does that on
        /// `controlHover`, because a press is a state and states cross-fade.
        /// What this spec is for is the *shape*: the material swells under the
        /// finger and springs back when it is let go, which is how a Liquid
        /// Glass control answers a click on macOS 26 and what Martin asked for
        /// in as many words — "that liquid glass click where the button almost
        /// pops out".
        ///
        /// Lightly damped on purpose. The swell is a twentieth, so at 0.8 the
        /// return is a ramp and there is no pop in it at all; at 0.62 it passes
        /// its rest size by about a third of a point on the way back, which is
        /// under a pixel of overshoot and the whole of what makes it read as
        /// release rather than as decay.
        static let controlPress = MotionSpec(response: 0.16, damping: 0.62, settling: 0.18)
        /// How far `controlPress` swells: **5 %, and it is a scale rather than
        /// a length**, which is why it lives here rather than in `Metric`.
        ///
        /// Measured against the reference captures: a 36 pt circle grows by
        /// 1.8 pt, a 21 pt glyph chip by one. Big enough to see at the edge of
        /// a capsule, small enough that a pressed control is still the same
        /// control in the same place.
        static let pressSwell: CGFloat = 1.05
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

        /// §30.9's page, **released**, finishing its travel on its own — and
        /// the two bounds the answer is held between.
        ///
        /// **A settle is not a transition, it is the rest of a movement the
        /// hand started**, and the one fixed duration it used to have was wrong
        /// at both ends of the gesture. Let go a tenth of a page from home and
        /// the column crawled the last 28 pt over 0.18 s; flick from a
        /// standstill and it crossed a whole page in the same 0.18 s. Neither
        /// is the page the fingers were pushing.
        ///
        /// So the duration is the distance divided by the speed the hand let go
        /// at, which is the one formula that makes the animation continue the
        /// gesture rather than replace it: the page leaves the fingers at the
        /// speed the fingers had. The bounds are there because the arithmetic
        /// alone has no floor and no ceiling — a hard flick would land the page
        /// in a single frame, and a release from a dead stop divides by nothing
        /// at all.
        ///
        /// Ease-out for the same reason: a page carrying momentum decelerates
        /// into place. It never accelerates away from the hand that let it go.
        static func spaceSettle(across points: CGFloat, at speed: CGFloat) -> MotionSpec {
            guard speed > 0 else { return spaceSettleSlowest }
            let seconds = Double(points / speed)
            return MotionSpec(
                min(max(seconds, spaceSettleFastest.duration), spaceSettleSlowest.duration),
                .easeOut
            )
        }

        /// Released mid-flick with almost nothing left to travel. Short enough
        /// to feel like the hand finished the job and long enough not to read
        /// as a jump cut.
        static let spaceSettleFastest = MotionSpec(0.12, .easeOut)
        /// Released from a standstill, or from far enough out that even a quick
        /// hand has a page to cover. This is `spaceSwitch`'s settling time,
        /// which is what §6 asks a Space switch to take when nothing is
        /// carrying it.
        static let spaceSettleSlowest = MotionSpec(0.30, .easeOut)

        // MARK: The load line (§3.2c)

        /// How long the fill takes to reach a newly reported progress value.
        ///
        /// Ease-out, and well inside §6's budget — this is not the shimmer's
        /// case. `estimatedProgress` arrives in **jumps**, a handful of them
        /// across a load, and each jump is a discrete change with a start and
        /// an end. What must never happen is the opposite mistake: a fill that
        /// runs on a clock of its own is a progress bar that lies, so this
        /// spec times the *travel* between two honest values and nothing else.
        static let loadLineAdvance = MotionSpec(0.20, .easeOut)
        /// The line arriving, and leaving once the page has finished.
        ///
        /// A load is over the moment `didFinish` lands; the line is not, or the
        /// last thing the user sees of it is a bar that vanished at four
        /// fifths. It runs to full on `loadLineAdvance` and then fades on this.
        static let loadLineFade = MotionSpec(0.20)

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

        /// **The hover and press fill, on every button in the chrome** (§3.1,
        /// §3.4): a wash that fades in under the pointer and one step up under
        /// a press, painted by the control's own layer so it is behind whatever
        /// the control draws and in front of whatever it is made of.
        ///
        /// `nil` is the resting state and fades the fill out. The colour is the
        /// caller's — `Surface.hover` and `Surface.selected` are the two §3.4
        /// names — and the timing is `controlHover` for both directions,
        /// because hover is a state the pointer can scrub in and out of a dozen
        /// times a second and none of those passes should linger.
        ///
        /// A `CALayer` property rather than a view's `animator()`: the fill is
        /// on the layer under the button's contents, which is the only place
        /// that is *behind* an `NSImageView`'s image and in front of a glass
        /// backing. That means the timing comes off a `CATransaction` rather
        /// than an `NSAnimationContext`, and Reduce Motion has to be checked
        /// here — see this file's header.
        @MainActor
        static func wash(_ layer: CALayer?, to colour: NSColor?, animated: Bool = true) {
            guard let layer else { return }
            let instant = !animated || reduceMotion
            CATransaction.begin()
            CATransaction.setDisableActions(instant)
            CATransaction.setAnimationDuration(instant ? 0 : controlHover.duration)
            CATransaction.setAnimationTimingFunction(controlHover.timingFunction)
            layer.backgroundColor = (colour ?? .clear).cgColor
            CATransaction.commit()
        }

        /// `controlPress`'s swell: scales `view` about its own centre and
        /// springs it there.
        ///
        /// The scale is written to the model layer as well as animated, so a
        /// control that is *held* stays swollen for as long as the button is
        /// down rather than springing back under the finger.
        ///
        /// Reduce Motion lands it without the spring, which for a 5 % scale is
        /// very nearly nothing — and that is the right answer: the press still
        /// reads, through the fill, which is not motion.
        @MainActor
        static func swell(_ view: NSView, to scale: CGFloat) {
            guard let layer = view.layer else { return }
            let from = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale.x") as? CGFloat ?? 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
            CATransaction.commit()
            guard let spring = controlPress.springAnimation(keyPath: "transform.scale") else { return }
            spring.fromValue = from
            spring.toValue = scale
            layer.add(spring, forKey: "controlPress")
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
