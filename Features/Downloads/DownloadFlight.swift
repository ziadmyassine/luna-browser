//
//  DownloadFlight.swift
//  Luna
//
//  `docs/UI-SPEC.md` §5.0 — a download starting, as a thing that travels.
//  The file's own icon leaves the page on an arc and lands in the Downloads
//  button, the button's glass bulges as it catches it, and the §15.3 list opens
//  underneath showing how far the bytes have got.
//
//  The whole point is that the button is in two different places. Luna has
//  two chromes: §3.5 puts Downloads at the bottom-left corner of the window and
//  §4 puts it at the top-right. A download that lands with a flash somewhere
//  fixed teaches the user nothing; an arc that ends on the button they will
//  later press to find the file teaches them where it went, and it has to be
//  the same animation in both layouts or it teaches them twice. So nothing
//  here knows which chrome is up — the caller hands over a landing point and
//  the glass that owns it, and the arc is drawn between two points.
//
//  Driven a frame at a time rather than by a path animation: a
//  `CAKeyframeAnimation` along a `CGPath` wants that path in the superlayer's
//  geometry, and a layer-backed AppKit view may or may not have its geometry
//  flipped depending on what it was added to. A display link and a frame per
//  tick is a few lines, is exact in view coordinates, and is what
//  `SpaceSwipeSettle` already does for the same reason. It also means the
//  scale and the fade come off the same clock as the position, instead of
//  three animations agreeing by construction.
//
//  The arithmetic is separate from the view (`DownloadFlight`), because the
//  arc is the part that can be wrong in a way nobody sees: turning the wrong
//  way, missing the button, or flat between two points that share a line.
//  `DownloadFlightTests` asserts it in both directions without a window.
//
//  §21.2: under Reduce Motion nothing flies and nothing bulges. The list still
//  opens — that is information, not motion.
//

import AppKit
import QuartzCore

// MARK: - The arithmetic

/// Where the file is, partway between the page and the shelf.
///
/// Points are in the overlay's own coordinates, which are not flipped: `y`
/// grows upward, so "above the straight line" here means a larger `y`.
enum DownloadFlight {

    /// The smallest bow any throw gets, so two points on one line still travel
    /// on a curve rather than sliding along a ruler.
    ///
    /// Derived from the thing being thrown rather than measured: a hop that
    /// clears its own height is a hop, and there is no other length in §5 this
    /// could sensibly be a fraction of.
    static var minimumLift: CGFloat { Tokens.Metric.downloadsFileIcon }

    /// The size the icon shrinks to on the way: the glyph it lands on top of.
    ///
    /// It arrives the size of the button's own mark, which is what makes the
    /// landing read as the file going *into* the shelf rather than sitting on
    /// it. Both numbers are already tokens, so the scale is their ratio and not
    /// a third number.
    static var landingScale: CGFloat { Tokens.Metric.glyphSize / Tokens.Metric.downloadsFileIcon }

    /// The quadratic's control point — the corner of the box the two points
    /// make, nudged the other way vertically.
    ///
    /// This is the whole of why the flight reads as a throw, and it replaced a
    /// midpoint lifted straight up. A lob to a button in the *bottom* corner
    /// went up before it went down, which is a detour the eye follows as a
    /// detour: the file left the page in the wrong direction and then came
    /// back. The corner instead covers the ground first and turns into the
    /// button at the end.
    ///
    /// Put algebraically, and this is the reason it needs no easing of its
    /// own: with the control at `(landing.x, origin.y)` the curve is
    /// `x(t) = origin.x(1−t)² + landing.x(1−(1−t)²)` and
    /// `y(t) = origin.y(1−t²) + landing.y·t²` — horizontal speed decaying,
    /// vertical accelerating as the square. That is a projectile, exactly, and
    /// it falls out of the *path* rather than being painted on with a timing
    /// curve. See `Motion.downloadFlight`, which is therefore linear.
    ///
    /// The vertical nudge is away from the landing — up when the button is
    /// below, down when it is above — so a throw gets a little wind-up and a
    /// throw along one line still gets an arc.
    static func control(from origin: CGPoint, to landing: CGPoint) -> CGPoint {
        CGPoint(x: landing.x, y: origin.y + (landing.y <= origin.y ? minimumLift : -minimumLift))
    }

    /// The point on the arc at `progress` (0 = the file, 1 = the button).
    static func point(at progress: CGFloat, from origin: CGPoint, to landing: CGPoint) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let inverse = 1 - t
        let control = control(from: origin, to: landing)
        return CGPoint(
            x: inverse * inverse * origin.x + 2 * inverse * t * control.x + t * t * landing.x,
            y: inverse * inverse * origin.y + 2 * inverse * t * control.y + t * t * landing.y
        )
    }

    /// Full size at the page, `landingScale` at the button, linearly between:
    /// it gets smaller because it is getting further away.
    static func scale(at progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return 1 + (landingScale - 1) * t
    }

    /// The icon's own opacity. It is solid until the very end, and then
    /// goes in the last sixth, because the catch is what finishes the movement:
    /// the bulge and the last of the icon happen together, so the file reads as
    /// absorbed rather than as switched off next to a button that then
    /// twitched. A ghost that faded across the whole arc would be a file
    /// evaporating on the way.
    static func opacity(at progress: CGFloat) -> CGFloat {
        let solid: CGFloat = 0.84
        guard progress > solid else { return 1 }
        return max(1 - (progress - solid) / (1 - solid), 0)
    }
}

// MARK: - The view

/// A full-window overlay that throws one icon and takes itself down.
///
/// It is its own container rather than a bare view added to the window's
/// content view, so the coordinate system the arc is computed in is one this
/// file chose: a plain unflipped `NSView`, whatever it was added to.
@MainActor
final class DownloadFlightView: NSView {

    private let ghost = NSView()
    private let origin: CGPoint
    private let landing: CGPoint
    private let onLanding: () -> Void
    private var startedAt: CFTimeInterval = 0
    private var link: CADisplayLink?

    /// Throws `icon` from `origin` to `landing`, both in `root`'s coordinates,
    /// and calls `onLanding` when it arrives — or immediately under Reduce
    /// Motion, which is the same call at the same place in the sequence.
    static func fly(
        _ icon: NSImage,
        from origin: CGPoint,
        to landing: CGPoint,
        in root: NSView,
        onLanding: @escaping () -> Void
    ) {
        guard !Tokens.Motion.reduceMotion else { return onLanding() }
        let flight = DownloadFlightView(
            icon: icon,
            from: root.convert(origin, to: nil),
            to: root.convert(landing, to: nil),
            onLanding: onLanding
        )
        flight.frame = root.bounds
        flight.autoresizingMask = [.width, .height]
        root.addSubview(flight, positioned: .above, relativeTo: nil)
        flight.start()
    }

    /// `origin` and `landing` arrive in window coordinates and are
    /// converted once the overlay is in the tree — see `start()`. Taking them
    /// in the caller's space and converting later is what lets the overlay own
    /// its own geometry.
    private init(icon: NSImage, from origin: CGPoint, to landing: CGPoint, onLanding: @escaping () -> Void) {
        self.origin = origin
        self.landing = landing
        self.onLanding = onLanding
        super.init(frame: .zero)
        wantsLayer = true
        ghost.wantsLayer = true
        ghost.layer?.contents = icon
        ghost.layer?.contentsGravity = .resizeAspect
        addSubview(ghost)
        // Decorative, and over the page: it must not take a click meant for a
        // link, and a screen reader is told about the download by the row in
        // the list rather than by an icon in flight (§21.1).
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func start() {
        // The backing scale, or the icon flies blurred. A layer whose
        // `contents` is an image renders at `contentsScale`, which starts at 1
        // — so on every display Luna actually runs on, a 34 pt file icon was
        // being drawn from a 34 px bitmap and scaled up. Nothing else in the
        // chrome hits this because nothing else assigns an image to a layer
        // directly.
        ghost.layer?.contentsScale = window?.backingScaleFactor ?? 2
        // The chrome's one drop shadow (§5). The icon crosses an arbitrary
        // page on its way to the button — white, dark, an image — and its own
        // edge is all that separates it from whatever is under it, which is
        // the same argument the popover's shadow is there for.
        ghost.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        place(at: 0)
        startedAt = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startedAt
        let spec = Tokens.Motion.downloadFlight
        place(at: spec.progress(at: elapsed))
        guard elapsed >= spec.duration else { return }
        link?.invalidate()
        link = nil
        removeFromSuperview()
        onLanding()
    }

    private func place(at progress: CGFloat) {
        // A frame computed from a clock, not from `bounds` — but it must still
        // land rather than animate, because this is the animation.
        Tokens.Motion.immediately {
            let side = Tokens.Metric.downloadsFileIcon * DownloadFlight.scale(at: progress)
            let centre = DownloadFlight.point(
                at: progress,
                from: convert(origin, from: nil),
                to: convert(landing, from: nil)
            )
            ghost.frame = NSRect(
                x: centre.x - side / 2,
                y: centre.y - side / 2,
                width: side,
                height: side
            )
            ghost.alphaValue = DownloadFlight.opacity(at: progress)
        }
    }
}

// MARK: - The catch

extension Tokens.Motion {

    /// The glass catching the file: `downloadCatchSwell` on the way in,
    /// springing back to rest on `downloadCatch`.
    ///
    /// The same shape as `swell(_:to:)` and not a call to it, because the two
    /// answers are different sizes on different springs — a press is the user
    /// doing something to the button, this is the button answering something
    /// that arrived. See `downloadCatchSwell`.
    ///
    /// It is the capsule that bulges, never the glyph inside it, for
    /// exactly the reason `SidebarActionCapsule` gives for the press: half a
    /// cylinder growing inside the other half is not a control reacting. The
    /// caller passes the surface that owns the material.
    @MainActor
    static func catchDownload(on view: NSView) {
        guard !reduceMotion, let layer = view.layer,
              let spring = downloadCatch.springAnimation(keyPath: "transform.scale")
        else { return }
        let swollen = downloadCatchSwell
        // Set outright first so the spring has somewhere to come back from
        // and the model layer is already at rest — an interrupted animation
        // then leaves the button its own size rather than 18 % too big.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        spring.fromValue = swollen
        spring.toValue = 1
        layer.add(spring, forKey: "downloadCatch")
    }
}
