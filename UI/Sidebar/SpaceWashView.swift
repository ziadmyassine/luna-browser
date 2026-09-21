//
//  SpaceWashView.swift
//  Luna
//
//  §8.2a's second intensity: the active Space's gradient, held at
//  `Tokens.Gradient.washAlpha`, behind the whole sidebar. It is the reason two
//  Spaces stop looking like the same window — the one visible gap the Spaces
//  feature still had.
//
//  It draws under everything and is not a second glass surface.
//  `BrowserWindowController` already applies `Glass.sidebar` to the window's
//  root plane; this is a tint laid on that material, which is why it paints
//  translucent stops rather than the flattened ones `Tokens.Gradient.planes`
//  returns. Getting it the wrong way round replaces the glass with a coloured
//  plate — see `washStops`.
//
//  §21.2 in full, and all three settings are live signals rather than an
//  appearance:
//
//    · Reduce Transparency — the wash goes opaque, because there is no
//      glass left to see through and a 16 % film over a solid plane is a
//      smudge. `washStops` makes that decision, so this view has no branch.
//    · Reduce Motion — a Space switch replaces the gradient outright
//      instead of cross-fading it. `Tokens.Motion.animate` degrades to zero
//      duration, so the layer lands on the new colours in the same frame.
//    · Increase Contrast — not an `NSAppearance` on macOS 26.5, so the
//      only way to hear about it is
//      `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`. It
//      matters here because Reduce Transparency arrives on the same
//      notification, and without it a user turning that setting on would keep
//      a translucent wash until the next Space switch.
//

import AppKit
import BrowserKit

/// The active Space's gradient, behind the sidebar.
@MainActor
final class SpaceWashView: NSView {

    private let wash = CAGradientLayer()
    private var gradient: GradientPair?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Top-leading to bottom-trailing: the sidebar is tall and narrow, so a
        // purely vertical ramp reads as two bands rather than as one surface.
        wash.startPoint = CGPoint(x: 0, y: 1)
        wash.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(wash)
        // Decorative: the Space is named and badged elsewhere, and a colour
        // VoiceOver reads out loud is noise (§21.1).
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Never hit-tests: every control in the sidebar sits above this, and a
    /// backdrop that swallowed clicks would be a dead 240 pt column.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `gradient`, cross-fading from whatever was there (§6's
    /// `spaceSwitchCrossfade`, the same 0.18 s the sidebar's content uses).
    ///
    /// Passing the pair it is already showing is free — the guard is what keeps
    /// `SidebarViewController.refresh`, which runs on every session change,
    /// from restarting the fade on every tab title update.
    func show(_ gradient: GradientPair) {
        guard gradient != self.gradient else { return }
        let isFirst = self.gradient == nil
        self.gradient = gradient
        apply(animated: !isFirst)
    }

    /// While §30.9's swipe is in the hand: the Space you are in, blended
    /// `mix` of the way toward the one you are sliding toward.
    ///
    /// The wash is the largest thing on screen saying which Space this is, so
    /// it is the most honest place to show one arriving. It moves with the
    /// fingers and back when they stop, which is what makes an abandoned swipe
    /// read as abandoned rather than as a switch that did not take.
    ///
    /// Never animated: `mix` is the animation, one frame per event. `nil` or
    /// `mix: 0` restores the active pair.
    ///
    /// A straight four-channel lerp, not `blended(toward:)`. That one is
    /// alpha-correct for laying a translucent fill over a colour, so a target
    /// of zero alpha contributes nothing — and sliding from a coloured Space
    /// toward a neutral one would have shown no change at all, in the one
    /// direction where the wash is what is going away. A cross-fade is two
    /// layers, one of them leaving, and alpha is one of the things travelling.
    /// - Parameters:
    ///   - lower: the Space on the left of where the indicator currently is.
    ///   - upper: the one on its right. The two are the same pair whenever the
    ///     indicator is sitting on a Space rather than between two.
    ///   - mix: 0 is all `lower`, 1 all `upper`.
    func preview(between lower: GradientPair, and upper: GradientPair, mix: CGFloat) {
        let fraction = max(0, min(Double(mix), 1))
        let appearance = effectiveAppearance
        let here = Self.washColors(for: lower, in: appearance)
        let there = Self.washColors(for: upper, in: appearance)
        let blended = zip(here, there).map { Self.lerp($0, $1, fraction, in: appearance).cgColor }
        Tokens.Motion.immediately { wash.colors = blended }
    }

    /// The fingers came up. Back to the Space the window is actually in, with
    /// no animation: either the swipe was abandoned and the wash was never more
    /// than a point or two away from here, or it committed and `show(_:)` is
    /// about to cross-fade to somewhere else entirely.
    func endPreview() {
        apply(animated: false)
    }

    /// `fraction` of the way from `from` to `to`, alpha included.
    ///
    /// A fully transparent end has no hue to travel toward, and `.clear` is
    /// stored as transparent black — so mixing its channels in would drag a
    /// Space's colour through grey on its way out. Neutral is exactly that
    /// case, and it is the one pair a user reaches for when they want the tint
    /// gone. Either end being clear therefore fades the other end's hue by
    /// alpha alone.
    static func lerp(_ from: NSColor, _ to: NSColor, _ fraction: Double, in appearance: NSAppearance) -> NSColor {
        let lhs = from.srgbComponents(for: appearance)
        let rhs = to.srgbComponents(for: appearance)
        let hue = lhs.alpha == 0 ? rhs : rhs.alpha == 0 ? lhs : nil
        let mix = { (start: Double, end: Double) in start + (end - start) * fraction }
        return NSColor(
            srgbRed: hue?.red ?? mix(lhs.red, rhs.red),
            green: hue?.green ?? mix(lhs.green, rhs.green),
            blue: hue?.blue ?? mix(lhs.blue, rhs.blue),
            alpha: mix(lhs.alpha, rhs.alpha)
        )
    }

    override func layout() {
        super.layout()
        // Bounds-derived, so it may never animate — see `Motion.immediately`.
        Tokens.Motion.immediately { wash.frame = bounds }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(animated: false)
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        apply(animated: false)
    }

    /// The two stops the wash lands on — and neutral paints nothing at all.
    ///
    /// `washStops` hands back a desaturated grey pair for neutral, which is a
    /// 16 % grey film over the glass: a visibly greyer sidebar, not the sidebar
    /// as it was before Spaces had colours. A Space nobody has coloured has to
    /// be indistinguishable from no Space colour, or "no colour" is just a
    /// thirteenth colour.
    ///
    /// Two clear stops rather than `isHidden`, so the cross-fade runs in both
    /// directions: picking a colour fades up from nothing and "No Colour" fades
    /// back down, instead of the layer snapping in and out under the tab list.
    ///
    /// A `static` taking the appearance, rather than a method reading
    /// `effectiveAppearance`, so the neutral rule can be proved without a
    /// window around it.
    static func washColors(for gradient: GradientPair, in appearance: NSAppearance) -> [NSColor] {
        guard !Tokens.Gradient.isNeutral(gradient) else { return [.clear, .clear] }
        let stops = Tokens.Gradient.washStops(gradient, in: appearance)
        return [stops.start, stops.end]
    }

    private func apply(animated: Bool) {
        guard let gradient else { return }
        let colors = Self.washColors(for: gradient, in: effectiveAppearance).map(\.cgColor)
        guard animated, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately { wash.colors = colors }
            return
        }
        let fade = CABasicAnimation(keyPath: "colors")
        fade.fromValue = wash.colors
        fade.toValue = colors
        fade.duration = Tokens.Motion.spaceSwitchCrossfade.duration
        fade.timingFunction = Tokens.Motion.spaceSwitchCrossfade.timingFunction
        wash.colors = colors
        wash.add(fade, forKey: "spaceWash")
    }
}
