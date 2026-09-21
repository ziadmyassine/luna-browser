//
//  MotionSpec.swift
//  Luna
//
//  One row of docs/UI-SPEC.md §6, as a value, and the two ways a view can run
//  it: hand it to `Motion.animate`, or ask it where it has got to when the
//  animation has to be driven a frame at a time.
//
//  Split out of Motion.swift at the 400-line limit. The specs themselves —
//  every named row of §6 — stayed there.
//

import AppKit
import QuartzCore

/// One row of §6.
///
/// `response`/`damping` are non-nil for a spring and nil for a timed curve.
/// `duration` is always meaningful, so a caller that only needs "how long until
/// this settles" never has to branch.
struct MotionSpec: Sendable {

    /// The curve a timed spec animates on. Ignored by springs.
    enum Curve: Sendable { case easeOut, easeInOut, linear }

    var duration: TimeInterval
    /// SwiftUI-style spring response, in seconds. Nil for a timed spec.
    var response: Double?
    /// Spring damping fraction, 0...1. Nil for a timed spec.
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

    /// Where a hand-driven animation has got to, 0…1, on this spec's curve.
    ///
    /// §30.9's page turn is the case this exists for. On release the column,
    /// the still, the §8.2a wash and the §3.5 dot strip all have to move
    /// together, and only the first two are layer properties — the other two
    /// are frames recomputed from a number. Animating what can be animated and
    /// setting the rest outright is how the strip came to jump to its Space
    /// while the column was still sliding there.
    ///
    /// So the number is tweened instead, and the read-out is applied the same
    /// way it is while a finger is down. The curve is read off the same
    /// `CAMediaTimingFunction` the animated half would have used rather than
    /// approximated beside it.
    ///
    /// Newton–Raphson on the unit bezier, falling back to bisection on the flat
    /// stretches where the derivative is too small to divide by. Four
    /// iterations is well inside a pixel for the curves §6 names.
    func progress(at time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        let fraction = CGFloat(min(max(time / duration, 0), 1))
        guard curve != .linear else { return fraction }
        var points = [Float](repeating: 0, count: 2)
        var control: [CGPoint] = []
        for index in 0...3 {
            timingFunction.getControlPoint(at: index, values: &points)
            control.append(CGPoint(x: CGFloat(points[0]), y: CGFloat(points[1])))
        }
        return Self.bezier(control[1], control[2], at: fraction)
    }

    /// The unit cubic bezier through (0,0), `first`, `second`, (1,1), solved
    /// for y at the x the clock is at.
    private static func bezier(_ first: CGPoint, _ second: CGPoint, at x: CGFloat) -> CGFloat {
        func axis(_ one: CGFloat, _ two: CGFloat, _ t: CGFloat) -> CGFloat {
            let a = 3 * one, b = 3 * (two - one) - a, c = 1 - a - b
            return ((c * t + b) * t + a) * t
        }
        func slope(_ one: CGFloat, _ two: CGFloat, _ t: CGFloat) -> CGFloat {
            let a = 3 * one, b = 3 * (two - one) - a, c = 1 - a - b
            return (3 * c * t + 2 * b) * t + a
        }
        var t = x
        for _ in 0..<4 {
            let error = axis(first.x, second.x, t) - x
            let derivative = slope(first.x, second.x, t)
            guard abs(derivative) > 1e-6 else { break }
            t -= error / derivative
        }
        var low: CGFloat = 0, high: CGFloat = 1
        while axis(first.x, second.x, t) - x > 1e-5 || x - axis(first.x, second.x, t) > 1e-5 {
            if axis(first.x, second.x, t) < x { low = t } else { high = t }
            let next = (low + high) / 2
            guard abs(next - t) > 1e-7 else { break }
            t = next
        }
        return axis(first.y, second.y, t)
    }

    /// A `CASpringAnimation` matching `response`/`damping`, or nil when this is
    /// not a spring or Reduce Motion is on. In both cases the caller should set
    /// the value outright instead of animating it.
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
