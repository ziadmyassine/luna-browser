//
//  Haptics.swift
//  Luna
//
//  What the chrome says with the hand rather than the eye: a tab that has
//  changed places, §30.9's ring closing, and the Space that comes of it.
//
//  In Design/ beside Motion.swift, for the same reason: a tick under the finger
//  is feel, not behaviour, so gesture code asks for it by name instead of
//  deciding what it feels like. This is the only file in Luna permitted to name
//  `NSHapticFeedbackManager`.
//
//  MEASURED, and it decides the API: `NSHapticFeedbackPattern` ships exactly
//  three cases in the macOS 26.5 SDK — `.generic`, `.alignment`, `.levelChange`
//  — with no intensity, no duration and no way to build one. The only decision
//  is which of the three.
//
//  It is silent on most Macs, and that is not a failure. `defaultPerformer`
//  only reaches hardware on a Force Touch trackpad and already honours System
//  Settings ▸ Trackpad, so there is no setting to add and nothing to check
//  before calling. Elsewhere it costs a method call and does nothing.
//

import AppKit

extension Tokens {

    /// §6.6's feedback under the hand.
    @MainActor
    enum Haptics {

        /// One tick, for a lift that has just changed places with a neighbour.
        ///
        /// Called from the one place that knows a step happened rather than a
        /// movement: `SidebarTabDragController.move(to:)`, where the drop
        /// target changes. The pointer moves continuously and the list does
        /// not — it steps, and this is the step.
        ///
        /// `.alignment` is what the system itself uses when something snaps
        /// into position: a shape onto a guide, a window onto a screen edge. A
        /// tab crossing its neighbour is the same event.
        ///
        /// `.drawCompleted`, not `.now`, so the tick lands with the frame that
        /// shows the row moving. A flick on a 120 Hz trackpad can cross several
        /// rows, and the performer's own rate limiting keeps that from buzzing.
        static func step() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }

        /// §30.9's ring has just closed: from here, letting go makes a Space.
        ///
        /// A detent, which is what `.levelChange` is for — the slider that has
        /// reached a stop, the value that has clicked over. The ring is not
        /// snapping to anything, so `.alignment` would be wrong; it is a
        /// threshold the hand crosses while still moving, and the tick is how
        /// the user finds out without watching a 46 pt hoop at the far edge of
        /// the column.
        ///
        /// It fires again on a second arming, but only after the hand has
        /// retreated a good way rather than at the crossing itself, or a hand
        /// holding a stiff stop would buzz across it. See
        /// `SidebarSpaceGestures.ringReArm`.
        static func latch() {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .drawCompleted)
        }

        /// The gesture ended in something being made.
        ///
        /// `.generic` rather than the other two: nothing aligned and no level
        /// changed — a Space now exists. The plainest of the three patterns,
        /// which is the right weight for a confirmation arriving at the same
        /// moment as a whole column of new chrome.
        static func commit() {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
        }
    }
}
