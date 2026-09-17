//
//  ParticleSweepView.swift
//  Luna
//
//  `docs/UI-SPEC.md` §5.1 — the filename dissolves into particles and
//  reassembles when a download lands. It is the one piece of motion in the
//  reference that nothing else in the app does, so it is worth the file.
//
//  WHY THIS IS ONE VIEW AND NOT 1200 LAYERS, AND NOT `CAEmitterLayer` EITHER:
//
//  §5.1 names `CAEmitterLayer` or Metal, and rules out 1200 `CALayer`s. The
//  rule behind that is one composited layer, not one per particle — 1200 layers
//  means 1200 nodes for the render server to transform and blend every frame,
//  which is the stutter §5.1 is warning about.
//
//  `CAEmitterLayer` cannot do the second half of §5.1. It is a *simulation*:
//  cells describe birth rate, velocity and lifetime, and there is no handle on
//  an individual particle afterwards. "Settle back into place over 0.18 s with
//  a 0.04 s stagger" requires addressing each particle by its home position,
//  which the emitter model does not offer. Its `emitterPosition` is also a
//  single point, so particles cannot be sampled from the *shape* of the text.
//
//  Metal would do it, at the cost of a device, a pipeline, a shader and a
//  vertex buffer for 0.4 s of animation on a 330 pt popover.
//
//  So: **one layer-backed `NSView`, drawing every particle itself once per
//  frame**, driven by the display link. One composited node, full per-particle
//  control, no GPU plumbing. Cost is ~1200 `CGContext` fills into a ~460 × 40 px
//  backing store, ≈0.3 ms of the 8.3 ms a 120 Hz frame gets, for 0.4 s.
//
//  ponytail: per-particle `setFillColor` + `fill`. If that ever shows on a
//  profile, bucket the particles by alpha and use `CGContext.fill(_ rects:)` —
//  eight state changes instead of 1200. Not worth it at this size.
//
//  §5.1 / §21.2: **under Reduce Motion this does not run at all.** The caller
//  checks `Tokens.Motion.reduceMotion` and simply shows the label.
//

import AppKit
import QuartzCore

@MainActor
final class ParticleSweepView: NSView {

    /// §5.1's "~1200 particles". A count, not a metric — there is no token for
    /// it because there is nothing else in the app that could share one.
    private static let targetCount = 1200

    private struct Particle {
        /// Home, in view points. Where it starts and where it settles back to.
        var home: CGPoint
        /// Full displacement at the end of the dissolve: up, outward, jittered.
        var throwOff: CGVector
        /// The ink alpha sampled from the text bitmap.
        var ink: CGFloat
        /// 0 at the left edge, 1 at the right — what makes the sweep directional.
        var sweep: CGFloat
    }

    private var particles: [Particle] = []
    private var ink: SRGB = SRGB(red: 0, green: 0, blue: 0, alpha: 1)
    private var startedAt: CFTimeInterval = 0
    private var link: CADisplayLink?
    private weak var sampled: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Decorative: the filename it is made of is announced by the row's own
        // label (§21.1). A screen reader must never have to watch an animation.
        setAccessibilityElement(false)
    }

    /// The sweep overlaps its neighbours by a whole line height; it must never
    /// swallow a click meant for the confirm button next to it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Running it

    /// Dissolves `label`'s rendered text and reassembles it.
    ///
    /// `label` is sampled as it actually draws — middle truncation, font,
    /// colour and all — so the particles are the real glyphs rather than a
    /// second rendering that might disagree with them. It must be visible when
    /// this is called; the sweep hides it for the 0.4 s and puts it back.
    ///
    /// Under Reduce Motion nothing is sampled, nothing is hidden and nothing
    /// animates — the filename simply stays where it is (§5.1, §21.2).
    func run(sampling label: NSView) {
        // A layer-backed view clips to its own bounds, and §5.1 throws the
        // cloud *above* and *outside* the word — so the canvas is the label
        // grown by one line height on every side, and the particles' home
        // coordinates are offset into it.
        let margin = label.bounds.height
        frame = label.frame.insetBy(dx: -margin, dy: -margin)
        guard !Tokens.Motion.reduceMotion, sample(label, margin: margin) else { return }
        sampled = label
        label.isHidden = true
        startedAt = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        needsDisplay = true
    }

    private func finish() {
        link?.invalidate()
        link = nil
        particles = []
        sampled?.isHidden = false
        sampled = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        if elapsed >= Tokens.Motion.downloadsParticleSweep.duration { finish() }
        needsDisplay = true
    }

    private var elapsed: CFTimeInterval { CACurrentMediaTime() - startedAt }

    // MARK: - Step 1: text → bitmap → grid

    /// Redraws `rep` into a context whose byte layout Luna chose, rather than
    /// whatever `cacheDisplay` happened to pick: 8-bit RGBA, alpha last, origin
    /// at the bottom-left — which is this view's coordinate system too.
    private static func ownedBitmap(of rep: NSBitmapImageRep, width: Int, height: Int) -> CGContext? {
        guard let image = rep.cgImage,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// Renders `label` into a bitmap Luna owns the format of and reads its
    /// alpha channel on a grid.
    ///
    /// `cacheDisplay` rather than re-drawing the string: it is the view's own
    /// output, so the sampled particles line up with the label to the pixel and
    /// there is no seam when it comes back at the end.
    private func sample(_ label: NSView, margin: CGFloat) -> Bool {
        let size = label.bounds.size
        let pixels = label.convertToBacking(size)
        let width = Int(pixels.width.rounded()), height = Int(pixels.height.rounded())
        guard width > 0, height > 0,
              let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds)
        else { return false }
        label.cacheDisplay(in: label.bounds, to: rep)

        guard let context = Self.ownedBitmap(of: rep, width: width, height: height),
              let data = context.data
        else { return false }

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let rowStride = context.bytesPerRow
        let scaleX = pixels.width / max(size.width, 1)
        let scaleY = pixels.height / max(size.height, 1)

        var found: [Particle] = []
        found.reserveCapacity(Self.targetCount * 2)
        let rise = size.height
        let centre = size.width / 2

        for row in 0..<height {
            for column in 0..<width {
                let alpha = CGFloat(bytes[row * rowStride + column * 4 + 3]) / 255
                guard alpha > 0 else { continue }
                let point = CGPoint(x: CGFloat(column) / scaleX + margin, y: CGFloat(row) / scaleY + margin)
                // §5.1: upward, outward from the centre, with per-particle
                // jitter so the cloud is not a rigid fan. Every distance is
                // derived from the text's own height — there is no metric token
                // for a particle throw and inventing one would be a literal.
                let outward = centre > 0 ? (point.x - margin - centre) / centre : 0
                found.append(Particle(
                    home: point,
                    throwOff: CGVector(
                        dx: outward * rise + .random(in: -rise...rise) / 2,
                        dy: rise + .random(in: 0...rise)
                    ),
                    ink: alpha,
                    sweep: size.width > 0 ? (point.x - margin) / size.width : 0
                ))
            }
        }
        guard !found.isEmpty else { return false }

        // Every ink pixel is more than §5.1 asks for; keep an even stride
        // through them so the thinned cloud still covers the whole word.
        let stride = max(1, found.count / Self.targetCount)
        particles = stride == 1 ? found : found.enumerated().compactMap {
            $0.offset.isMultiple(of: stride) ? $0.element : nil
        }

        ink = (label as? NSTextField).map { $0.textColor ?? Tokens.Text.primary }
            .map { $0.srgbComponents(for: effectiveAppearance) }
            ?? Tokens.Text.primary.srgbComponents(for: effectiveAppearance)
        return true
    }

    // MARK: - Steps 2–4: the frame

    override func draw(_ dirtyRect: NSRect) {
        guard !particles.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let now = elapsed
        // One pixel of ink per particle, at the smallest size the design system
        // names (§1's hairline). Anything larger reads as confetti, not dust.
        let dot = Tokens.Metric.hairline

        for particle in particles {
            let frame = ParticleSweep.phase(sweep: particle.sweep, at: now)
            guard frame.alpha > 0 else { continue }
            context.setFillColor(
                red: ink.red,
                green: ink.green,
                blue: ink.blue,
                alpha: ink.alpha * frame.alpha * particle.ink
            )
            context.fill(CGRect(
                x: particle.home.x + particle.throwOff.dx * frame.displacement,
                y: particle.home.y + particle.throwOff.dy * frame.displacement,
                width: dot,
                height: dot
            ))
        }
    }
}

// MARK: - §5.1's timeline

/// The dissolve/settle curve, as a pure function of "how far along the sweep
/// this particle sits" and "what time is it" — so the timing §5.1 specifies can
/// be tested without a window, a bitmap or a display link.
///
/// The three published numbers only add up one way. Total is 0.40 s and
/// dissolve + settle is 0.22 + 0.18 = 0.40, so the 0.04 s stagger has to live
/// *inside* each phase rather than extend it: a particle's own dissolve runs
/// for 0.22 − 0.04 and starts at `sweep × 0.04`, and its settle does the same
/// within the second half. The right-most particle finishes at exactly 0.40 s,
/// the left-most 0.04 s earlier, and that gap is the directional read.
enum ParticleSweep {

    /// - Parameters:
    ///   - sweep: 0 at the left edge of the word, 1 at the right.
    ///   - time: seconds since the sweep started.
    /// - Returns: `displacement` scales the particle's full throw (0 = home),
    ///   `alpha` multiplies its ink.
    static func phase(sweep: CGFloat, at time: TimeInterval) -> (displacement: CGFloat, alpha: CGFloat) {
        let dissolve = Tokens.Motion.particleDissolve.duration
        let settle = Tokens.Motion.particleSettle.duration
        let stagger = Tokens.Motion.particleStagger
        let lead = stagger * Double(min(max(sweep, 0), 1))

        if time < dissolve + lead {
            let progress = clamp((time - lead) / max(dissolve - stagger, .leastNonzeroMagnitude))
            return (progress, 1 - progress)
        }
        // Back into place, ease-out, from wherever it was thrown to.
        let progress = easeOut(clamp((time - dissolve - lead) / max(settle - stagger, .leastNonzeroMagnitude)))
        return (1 - progress, progress)
    }

    private static func clamp(_ value: Double) -> CGFloat { CGFloat(min(max(value, 0), 1)) }

    private static func easeOut(_ value: CGFloat) -> CGFloat { 1 - pow(1 - value, 3) }
}
