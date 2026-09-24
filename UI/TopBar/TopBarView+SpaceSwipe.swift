//
//  TopBarView+SpaceSwipe.swift
//  Luna
//
//  §30.9's swipe on §4's bar: the tabs travel with the fingers. The column
//  moves its page with the hand, and the bar used to move nothing but the
//  Space's name, so a swipe here was a nudge followed by a new set of tabs
//  appearing in one frame. Now the run slides out the way the hand is going,
//  one point per point, fading as it goes, and the next Space's run slides in
//  from the other side at the pace the old one left.
//
//  Split from `TopBarView` for SwiftLint's file length.
//

import AppKit

extension TopBarView {

    /// One frame of a held or settling swipe. `travel` is in Spaces; the run
    /// moves `travel` of `TopBarSpaceName.swipeSpan`, which is the distance the
    /// fingers cover for one Space.
    func slideTabs(_ travel: CGFloat) {
        guard let layer = strip.content.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(translationX: -travel * spaceName.swipeSpan, y: 0))
        layer.opacity = Float(1 - min(abs(travel), 1))
        CATransaction.commit()
    }

    /// The new Space's run coming in from the side the old one did not leave
    /// by, on the spec the old one left on.
    func tabsArrive(from direction: CGFloat, on spec: MotionSpec) {
        guard let layer = strip.content.layer, !Tokens.Motion.reduceMotion, spec.duration > 0 else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = direction * spaceName.swipeSpan
        slide.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [slide, fade]
        group.duration = spec.duration
        group.timingFunction = spec.timingFunction
        layer.add(group, forKey: "luna.space.arrive")
    }
}
