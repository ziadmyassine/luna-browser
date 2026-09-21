//
//  ReloadBloomArc.swift
//  Luna
//
//  The two pieces of UI-SPEC §7 that are about pixels rather than phases: the
//  gradient that is the arc, and the one Core Image pass behind the blur.
//
//  WHAT THE REFERENCE ACTUALLY SHOWS. `inspiration/refresh-animation-ui.mov`
//  was re-sampled frame by frame rather than taken from §7's transcription.
//  At t ≈ 1.40 / 1.55 / 1.70 s the bands run, inner edge to outer:
//
//      white → amber (hue 56°) → mint (hue 194°) → lavender (hue 277°)
//
//  compositing over the clip's paper-white page as #EEECCA, #E1EBEF, #E2D0EE.
//  §7's prose has the last two the wrong way round. The bands are concentric
//  about a centre well above the top of the screen, which is why they read as
//  one wide concave-up crescent — and why this is a radial `CAGradientLayer`
//  with its centre pushed off the top edge rather than anything hand-drawn.
//
//  WHY THE BLUR IS A STILL IMAGE. §7 forbids blurring the live `WKWebView`,
//  and a `CIGaussianBlur` in `CALayer.filters` is the same trap one layer
//  down: the render server re-evaluates a layer filter whenever its inputs
//  change, so an animated radius is a full-viewport Core Image pass every
//  frame. The snapshot is blurred once into a `CGImage` instead, and everything
//  that moves afterwards is `opacity` and `position`. Steady state is six extra
//  composited quads and zero CPU, which is what keeps §19.1's 120 fps intact.
//

import AppKit
import CoreImage
import QuartzCore
import WebKit

/// The gradient's own parameters: unit-space stops and fractions of the card,
/// not pt sizes, so they are not `Tokens.Metric` material. The two real
/// measurements §7 states in points — `reloadBlurRadius` and
/// `reloadProgressLine` — are tokens.
enum ReloadArc {

    /// Centre of the radial gradient, above the card's top edge (unit y > 1).
    /// Pushing the centre off-card is what turns concentric rings into one
    /// shallow concave-up crescent across the viewport.
    static let centre = CGPoint(x: 0.5, y: 1.09)

    /// Ellipse radii in unit space. Much wider than tall, which is what makes
    /// the crescent shallow: solved from the clip's measured sag, ~9 % of the
    /// viewport height across a half-width.
    static let radius = CGSize(width: 0.95, height: 0.51)

    /// Where each band peaks along the radius. Derived from the clip at
    /// t ≈ 1.55 s, where amber, mint and lavender peak at 26.7 %, 33.0 % and
    /// 41.5 % of the viewport height and the bloom is gone by 50 %.
    static let stops: [NSNumber] = [0.0, 0.45, 0.62, 0.72, 0.86, 1.0]

    /// Fraction of the card height the arc drifts down between progress 0 and
    /// 1 (§7: "drifting slowly downward. Honest progress, not theatre").
    static let drift: CGFloat = 0.20

    /// Inner edge to outer, one per entry in `stops`. `core` appears twice so
    /// the inside of the crescent stays flat instead of ramping into amber the
    /// moment it clears the card's top edge.
    ///
    /// Resolve these under the view's appearance — i.e. inside `updateLayer` —
    /// per the house rule, even though a bloom is light and therefore the same
    /// in both themes.
    static var bands: [NSColor] {
        [
            Tokens.Bloom.core,
            Tokens.Bloom.core,
            Tokens.Bloom.amber,
            Tokens.Bloom.mint,
            Tokens.Bloom.lavender,
            Tokens.Bloom.lavender.withAlphaComponent(0)
        ]
    }
}

/// §7's blur: one Core Image pass over a snapshot, never over the live view.
@MainActor
struct PageBlur {

    private let context = CIContext()

    /// Snapshots `web`'s viewport, blurs it once and hands the result back.
    /// Silently does nothing if the web process cannot produce a snapshot —
    /// the arc alone is a perfectly good degraded state.
    ///
    /// `takeSnapshot` and not a layer capture: a `WKWebView` renders in the web
    /// process and the layer this process holds is a remote proxy with no local
    /// backing store, so `CALayer.render(in:)` and
    /// `bitmapImageRepForCachingDisplay` come back empty for page content.
    /// `takeSnapshot` is the only API that asks the web process for pixels.
    func capture(_ web: WKWebView, viewHeight: CGFloat, then deliver: @escaping @MainActor (CGImage) -> Void) {
        let configuration = WKSnapshotConfiguration()
        // What is on screen now, not a forced re-render: `true` stalls the web
        // process for a paint that is about to be blurred away regardless.
        configuration.afterScreenUpdates = false
        // The completion handler is `NS_SWIFT_UI_ACTOR` in `WKWebView.h`, so it
        // is already main-actor isolated — verified against MacOSX26.5.sdk.
        web.takeSnapshot(with: configuration) { image, _ in
            guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let blurred = blur(cgImage, viewHeight: viewHeight)
            else { return }
            deliver(blurred)
        }
    }

    // ponytail: full-resolution snapshot. Measured on an M4, a 3200 × 2000
    // snapshot at sigma 16 costs 6.8 ms median to rasterise and read back;
    // 1600 × 1000 at sigma 8 costs 2.2 ms. `createCGImage` is deferred, so the
    // main thread does not actually block on either — but if the pass ever
    // shows up in a 120 fps trace, halve it with `configuration.snapshotWidth`
    // and let the sigma follow: an 8 pt blur has no detail left to lose.
    private func blur(_ image: CGImage, viewHeight: CGFloat) -> CGImage? {
        let source = CIImage(cgImage: image)
        // §7's 8 pt in snapshot pixels: the snapshot comes back at the display's
        // backing scale, so a fixed pixel radius would be half as strong on a
        // 1x display and twice as strong on a future 3x one.
        let sigma = Tokens.Metric.reloadBlurRadius * CGFloat(image.height) / max(viewHeight, 1)
        // Clamping first is what stops the blur pulling transparency in from
        // outside the extent and leaving a soft rim down every edge of the card.
        let blurred = source.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigma))
            .cropped(to: source.extent)
        return context.createCGImage(blurred, from: source.extent)
    }
}

extension CALayer {

    /// Opacity is the only thing the bloom ever animates besides `position` —
    /// which is the whole performance argument at the top of this file.
    ///
    /// - Parameters:
    ///   - duration: overrides `spec`'s, for the de-blur strips that have to
    ///     share §7's 0.30 s with the 40 ms stagger.
    ///   - delay: that strip's place in the stagger.
    func fade(to opacity: Float, _ spec: MotionSpec, duration: TimeInterval? = nil, delay: TimeInterval = 0) {
        let from = presentation()?.opacity ?? self.opacity
        self.opacity = opacity
        guard !Tokens.Motion.reduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = duration ?? spec.duration
        animation.timingFunction = spec.timingFunction
        animation.beginTime = CACurrentMediaTime() + delay
        // Without `.backwards` a staggered strip would snap to its end value
        // and sit there until its turn came round.
        animation.fillMode = .backwards
        add(animation, forKey: "opacity")
    }
}
