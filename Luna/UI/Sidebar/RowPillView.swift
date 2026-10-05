//
//  RowPillView.swift
//  Luna
//
//  §3.4's two row fills. Split out of `TabListController.swift` to keep that
//  file inside SwiftLint's length limit.
//

import AppKit

/// §3.4's two row fills, the selected pill and the hover lift, and §3.4b's
/// plate round a hovered folder, which travels between folders on the same
/// terms the hover lift travels between rows.
///
/// Glass alone is not visible: `.clear` glass over the sidebar's own glass is
/// very nearly the sidebar, and a selected row read as unselected. So the fills
/// carry `Surface.selected` and `Surface.hover`, translucent washes that leave
/// the glass under them still glass.
@MainActor
final class RowPillView: NSView {

    /// `working` is the outline round a tab an agent is acting on: the
    /// folder plate's tinted rim and spark with no fill, so the tab's own
    /// pill shows through it.
    enum Role { case selected, hover, folder, working }

    /// Kept for the callers that track the table's focus, and changes nothing
    /// drawn: a blue ring around the current tab is a system list, not this
    /// one. The selection reads as glass — the material plus §3.4's wash — in
    /// every focus state.
    var isFocused = false

    /// How far through its page the selected tab has been read, 0...1, or nil
    /// for a page that does not scroll. Drawn as `Surface.readBand` over the
    /// selected wash from the leading edge, so the part read is one step
    /// lighter and nothing new is added to the row: no line, no colour.
    var progress: CGFloat? {
        didSet { if progress != oldValue { needsLayout = true } }
    }

    /// A folder plate in a colour of its own: a Luna Control folder's, filled
    /// and outlined in its app's colour (`Tokens.Agent`), where every other
    /// folder's plate is the neutral well.
    var tint: NSColor? {
        didSet { if tint != oldValue { needsDisplay = true } }
    }

    /// The folder plate's corner, which Luna Control's working capsule
    /// (`ControlSurfaceView`) rounds into a capsule.
    var cornerRadius = Tokens.Metric.rowCornerRadius {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }

    /// Astro's plate: a soft glow of its lavender round the rim, brighter
    /// while it works, and a spark that runs lavender into ice.
    var glows = false {
        didSet { if glows != oldValue { needsDisplay = true } }
    }

    /// Whether the agent a tinted plate belongs to is working in its folder:
    /// a spark of the tint runs round the rim (`Motion.agentSpark`).
    var isWorking = false {
        didSet { if isWorking != oldValue { applyWorking() } }
    }
    /// The spark: a conic gradient turning inside a mask that is only the
    /// rim, so the light travels along the edge. Core Animation turns it on
    /// the render server; the title shimmer it replaces redrew the row.
    private let rim = CALayer()
    private let rimMask = CAShapeLayer()
    private let spark = CAGradientLayer()

    private let role: Role
    /// Rounds the band's leading end into the pill's own corners. Its trailing
    /// end stays square — that edge is the reading position, not a shape.
    private let bandClip = NSView()
    /// Internal so a test can read where the band ends.
    let band = CALayer()

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        // The folder plate is a pinned tile's resting surface, which carries no
        // glass either — see `updateLayer`.
        if role != .folder, role != .working {
            Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
        }
        bandClip.wantsLayer = true
        bandClip.layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        bandClip.layer?.cornerCurve = .continuous
        bandClip.layer?.masksToBounds = true
        bandClip.layer?.addSublayer(band)
        bandClip.autoresizingMask = [.width, .height]
        addSubview(bandClip)
        spark.type = .conic
        spark.startPoint = CGPoint(x: 0.5, y: 0.5)
        spark.endPoint = CGPoint(x: 0.5, y: 0)
        // Clear for most of the lap, then the light with a short tail.
        spark.locations = [0, 0.78, 0.94, 1]
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = Tokens.Agent.sparkWidth
        rim.mask = rimMask
        rim.addSublayer(spark)
        rim.opacity = 0
        layer?.addSublayer(rim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.backgroundColor = fill.cgColor
        // §3.4 gives the selected row a visible border and the hover lift none:
        // a border that appeared under the pointer would read as a second
        // selection. The border is the glass's own edge — `Line.border`, never
        // the accent: no blue anywhere on a selected tab. The folder plate takes
        // the same hairline a pinned tile's well does.
        let bordered = role != .hover
        layer.borderWidth = bordered ? Tokens.Metric.hairline : 0
        // Under Reduce Motion the spark does not run, and a working folder's
        // rim comes up to full strength instead.
        let rimAlpha = isWorking && Tokens.Motion.reduceMotion ? 1 : Tokens.Agent.rimAlpha
        layer.borderColor = bordered ? (tint?.withAlphaComponent(rimAlpha) ?? Tokens.Line.border).cgColor : nil
        band.backgroundColor = Tokens.Surface.readBand.cgColor
        let light = (tint?.blended(withFraction: Tokens.Agent.sparkLift, of: .white) ?? .white).cgColor
        let clear = light.copy(alpha: 0) ?? NSColor.clear.cgColor
        spark.colors = [clear, clear, light, clear]
        layer.shadowOpacity = 0
        guard glows else { return }
        let ice = Tokens.Astro.to.blended(withFraction: Tokens.Agent.sparkLift, of: .white)?.cgColor ?? light
        spark.colors = [clear, clear, light, ice]
        layer.shadowColor = (tint ?? Tokens.Astro.from).cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = isWorking ? 8 : 5
        layer.shadowOpacity = isWorking ? 0.55 : 0.25
    }

    private func applyWorking() {
        needsDisplay = true
        guard !Tokens.Motion.reduceMotion else { return }
        if isWorking, spark.animation(forKey: "lap") == nil {
            let lap = CABasicAnimation(keyPath: "transform.rotation.z")
            lap.fromValue = 0
            lap.toValue = -2 * CGFloat.pi
            lap.duration = Tokens.Motion.agentSpark.duration
            lap.timingFunction = Tokens.Motion.agentSpark.timingFunction
            lap.repeatCount = .infinity
            spark.add(lap, forKey: "lap")
        }
        // In and out on the load line's fade: both say work started or ended.
        CATransaction.begin()
        CATransaction.setAnimationDuration(Tokens.Motion.loadLineFade.duration)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isWorking else { return }
                self.spark.removeAnimation(forKey: "lap")
            }
        }
        rim.opacity = isWorking ? 1 : 0
        CATransaction.commit()
    }

    /// The folder plate is a pinned tile's well, not a wash. A hover or a
    /// selected pill lying on it adds its own ink on top, so the three still
    /// step in order in both themes — plate, then hover, then selected with
    /// its hairline.
    private var fill: NSColor {
        switch role {
        case .selected: Tokens.Surface.selected
        case .hover: Tokens.Surface.hover
        case .folder: tint?.withAlphaComponent(Tokens.Agent.fillAlpha) ?? Tokens.Surface.well
        case .working: .clear
        }
    }

    override func layout() {
        super.layout()
        // Moved on every frame of a scroll, so it never animates: a band
        // easing behind the page reads as lag.
        Tokens.Motion.immediately {
            placeSpark()
            // The glow round the plate's shape, not round its faint fill.
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            bandClip.frame = bounds
            let width = (bounds.width * (progress ?? 0)).rounded()
            let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0
            band.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
    }

    /// The rim's mask on the plate's edge, and the gradient a square round
    /// the plate's centre, large enough that turning never shows its corners.
    private func placeSpark() {
        let width = Tokens.Agent.sparkWidth
        rim.frame = bounds
        rimMask.frame = bounds
        let radius = max(cornerRadius - width / 2, 0)
        rimMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), cornerWidth: radius, cornerHeight: radius,
            transform: nil
        )
        let side = hypot(bounds.width, bounds.height)
        spark.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        spark.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Moving one pill between rows

/// One pill travels; it is never re-created per row. Both lists that wear
/// §3.4's fills — the sidebar's tabs and §2's section list — keep exactly two
/// of these and move them, which is what makes the selection slide from one
/// row to the next instead of blinking out of one and into another. It lives
/// here rather than in either list so the two cannot drift apart: a settings
/// row and a tab row answer the pointer on the same spring.
extension RowPillView {

    /// Move to `target`, springing on `spec` — or land there with no animation
    /// when the pill was parked, which is a pill arriving rather than moving.
    func move(to target: NSRect, spec: MotionSpec?) {
        let wasParked = alphaValue == 0 || frame == .zero
        if !wasParked, let spring = spec?.springAnimation(keyPath: "position") {
            let from = layer?.position ?? .zero
            frame = target
            spring.fromValue = NSValue(point: from)
            spring.toValue = NSValue(point: layer?.position ?? .zero)
            layer?.add(spring, forKey: "position")
        } else {
            // Layer-backed frames animate themselves; `SidebarRowView.layout`
            // takes the same precaution for the same reason.
            Tokens.Motion.immediately {
                // "bounds" too: a stretch still running would otherwise carry
                // the old height into the new place.
                for key in ["position", "bounds"] { layer?.removeAnimation(forKey: key) }
                frame = target
            }
        }
        // No spec means no transition at all, alpha included. A move the
        // pill did not make — a live resize, a list that has been replaced
        // under it — lands; it does not arrive.
        fade(to: 1, animated: spec != nil)
    }

    /// Resize in place on `spec`'s duration and curve, from wherever the pill
    /// is standing on screen. §3.4b's plate does this as its folder folds, so
    /// its bottom edge keeps pace with the rows `NSTableView` is sliding on
    /// the same clock; a spring from `move` would overshoot past them.
    func stretch(to target: NSRect, spec: MotionSpec) {
        guard let layer, !Tokens.Motion.reduceMotion else { return move(to: target, spec: nil) }
        let from = layer.presentation() ?? layer
        let (bounds, position) = (from.bounds, from.position)
        Tokens.Motion.immediately { frame = target }
        let changes = [
            ("bounds", NSValue(rect: bounds), NSValue(rect: layer.bounds)),
            ("position", NSValue(point: position), NSValue(point: layer.position))
        ]
        for (key, old, new) in changes where old != new {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = old
            animation.toValue = new
            animation.duration = spec.duration
            animation.timingFunction = spec.timingFunction
            layer.add(animation, forKey: key)
        }
    }

    /// Park the pill, or bring it back. A row with nothing selected and nothing
    /// hovered has no fill at all (§30.7).
    ///
    /// `animated: false` is a cancel, not a shorter fade, so it skips the
    /// animated path's `alphaValue` short-cut: a running animation may already
    /// be heading to the value asked for, and the pill has to be there now.
    /// §6's Space switch needs it, or a fill still fading out of the Space you
    /// left lies empty in the one you arrived in. Clearing every animation is
    /// safe: each one this view carries — this fade, `move`'s spring,
    /// `stretch` — is one a cancel should end.
    func fade(to alpha: CGFloat, animated: Bool = true) {
        guard animated else {
            return Tokens.Motion.immediately {
                layer?.removeAllAnimations()
                alphaValue = alpha
            }
        }
        guard alphaValue != alpha else { return }
        Tokens.Motion.animate(Tokens.Motion.rowHover) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = alpha
        }
    }
}
