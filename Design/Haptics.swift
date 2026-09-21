//
//  Haptics.swift
//  Luna
//
//  The things the chrome says with the hand rather than the eye: a tab that
//  has changed places, §30.9's ring closing, and the Space that comes of it.
//
//  It lives in `Design/` beside `Motion.swift` for the same reason that file
//  does: a tick under the finger is feel, not behaviour, and the gesture code
//  should ask for it by name rather than decide what it feels like. Nothing
//  here is a colour or a length, so §0.3's two ownership rules do not apply —
//  but the rule they are an instance of does, and this is the only file in Luna
//  permitted to name `NSHapticFeedbackManager`.
//
//  MEASURED, and it decides the API: `NSHapticFeedbackPattern` ships exactly
//  three cases in the macOS 26.5 SDK — `.generic`, `.alignment`, `.levelChange`
//  — and there is no intensity, no duration and no way to build one. So the
//  only real decision is *which* of the three, and `.alignment` is the one the
//  system itself uses when something snaps into a position: dragging a shape
//  onto a guide in Keynote, a window onto a screen edge, a marker onto a
//  boundary in QuickTime. A tab crossing its neighbour is that same event.
//
//  **It is silent on most Macs, and that is not a failure.** `defaultPerformer`
//  only reaches hardware on a Force Touch trackpad, and it already honours the
//  user's System Settings ▸ Trackpad preference — so there is no setting to add
//  here and nothing to check before calling. On anything else this costs a
//  method call and does nothing, which is the correct behaviour for feedback
//  the machine cannot give.
//

import AppKit

extension Tokens {

    /// §6.6's feedback under the hand.
    @MainActor
    enum Haptics {

        /// One tick, for a lift that has just changed places with a neighbour.
        ///
        /// Called from the one place that knows a *step* happened rather than a
        /// movement: `SidebarTabDragController.move(to:)`, where the drop target
        /// changes. The pointer moves continuously and the list does not — it
        /// steps — and this is the step.
        ///
        /// `.drawCompleted`, not `.now`: the tick is about the row that has just
        /// moved, so it should land with the frame that shows it moving rather
        /// than a few milliseconds before it. The same gesture on a 120 Hz
        /// trackpad can cross several rows in a flick, and the performer's own
        /// rate limiting is what keeps that from buzzing.
        static func step() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }

        /// §30.9's ring has just closed: from here, letting go makes a Space.
        ///
        /// **A detent, which is what `.levelChange` is for** — the slider that
        /// has reached a stop, the value that has clicked over. The ring is not
        /// snapping to anything, so `.alignment` would be the wrong one of the
        /// three; it is a threshold the hand has crossed while still moving,
        /// and the tick is the only way the user finds that out without
        /// watching a 46 pt hoop at the far edge of the column.
        ///
        /// It fires **once per gesture**, on the way in. A detent that ticked
        /// again every time the fingers wandered back and forth across the
        /// threshold would buzz for the rest of the swipe, and there are two
        /// thirds of `spaceCreateTravel` still to go after this.
        static func latch() {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .drawCompleted)
        }

        /// The gesture ended in something being made.
        ///
        /// `.generic` rather than the other two on purpose: nothing aligned and
        /// no level changed — a Space now exists. It is the plainest of the
        /// three patterns, which is the right weight for a confirmation that
        /// arrives at the same moment as a whole column of new chrome.
        static func commit() {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
        }
    }
}
