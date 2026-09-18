//
//  SpaceWashView.swift
//  Luna
//
//  §8.2a's second intensity: the active Space's gradient, held at
//  `Tokens.Gradient.washAlpha`, behind the whole sidebar. It is the reason two
//  Spaces stop looking like the same window — the one visible gap the Spaces
//  feature still had.
//
//  **It draws under everything and it is not a second glass surface.**
//  `BrowserWindowController` already applies `Glass.sidebar` to the window's
//  root plane; this is a tint laid *on* that material, which is why it paints
//  translucent stops rather than the flattened ones `Tokens.Gradient.planes`
//  hands back. See `washStops` for the difference — getting it the wrong way
//  round replaces the glass with a coloured plate.
//
//  §21.2 in full, and all three settings are live signals rather than an
//  appearance:
//
//    · **Reduce Transparency** — the wash goes opaque, because there is no
//      glass left to see through and a 16 % film over a solid plane is a
//      smudge. `washStops` makes that decision, so this view has no branch.
//    · **Reduce Motion** — a Space switch replaces the gradient outright
//      instead of cross-fading it. `Tokens.Motion.animate` degrades to zero
//      duration, so the layer lands on the new colours in the same frame.
//    · **Increase Contrast** — not an `NSAppearance` on macOS 26.5, so the
//      only way to hear about it is
//      `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`. It
//      matters here because Reduce Transparency arrives on the *same*
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

    private func apply(animated: Bool) {
        guard let gradient else { return }
        let stops = Tokens.Gradient.washStops(gradient, in: effectiveAppearance)
        let colors = [stops.start.cgColor, stops.end.cgColor]
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
