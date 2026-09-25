//
//  RowPillView.swift
//  Luna
//
//  §3.4's two row fills. Split out of `TabListController.swift` to keep that
//  file inside SwiftLint's length limit; nothing changed on the way across.
//

import AppKit

/// §3.4's two row fills, the selected pill and the hover lift, and §3.4b's
/// plate round a hovered folder, which travels between folders on the same
/// terms the hover lift travels between rows.
///
/// Clear glass alone was not visible. The pill was `Glass.control` plus a
/// hairline and nothing else, and `.clear` glass over the sidebar's own glass
/// is very nearly the sidebar — a selected row read as unselected. `Tokens`
/// has carried `Surface.selected` and `Surface.hover` for exactly this since
/// M1; they were simply never asked for. Both are translucent washes, so the
/// glass under them is still glass.
@MainActor
final class RowPillView: NSView {

    enum Role { case selected, hover, folder }

    /// Kept for the callers that track the table's focus. It no longer
    /// changes what is drawn: a selected row used to take an accent-coloured
    /// border while the list had focus, and a blue ring around the current tab
    /// is a system list, not this one. The selection reads as glass — the
    /// material plus §3.4's wash — in every focus state.
    var isFocused = false

    /// How far through its page the selected tab has been read, 0...1, or nil
    /// for a page that does not scroll. Drawn as `Surface.readBand` over the
    /// selected wash from the leading edge, so the part read is one step
    /// lighter and nothing new is added to the row: no line, no colour.
    var progress: CGFloat? {
        didSet { if progress != oldValue { needsLayout = true } }
    }

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
        if role != .folder {
            Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.rowCornerRadius)
        }
        bandClip.wantsLayer = true
        bandClip.layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        bandClip.layer?.cornerCurve = .continuous
        bandClip.layer?.masksToBounds = true
        bandClip.layer?.addSublayer(band)
        bandClip.autoresizingMask = [.width, .height]
        addSubview(bandClip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = role == .folder ? Tokens.Metric.groupPlateCornerRadius : Tokens.Metric.rowCornerRadius
        layer.backgroundColor = fill.cgColor
        // §3.4 gives the selected row a visible border and the hover lift none:
        // a border that appeared under the pointer would read as a second
        // selection. The border is the glass's own edge — `Line.border`, never
        // the accent: no blue anywhere on a selected tab. The folder plate takes
        // the same hairline a pinned tile's well does.
        let bordered = role != .hover
        layer.borderWidth = bordered ? Tokens.Metric.hairline : 0
        layer.borderColor = bordered ? Tokens.Line.border.cgColor : nil
        band.backgroundColor = Tokens.Surface.readBand.cgColor
    }

    /// The folder plate is a pinned tile's well, not a wash. A hover or a
    /// selected pill lying on it adds its own ink on top, so the three still
    /// step in order in both themes — plate, then hover, then selected with
    /// its hairline.
    private var fill: NSColor {
        switch role {
        case .selected: Tokens.Surface.selected
        case .hover: Tokens.Surface.hover
        case .folder: Tokens.Surface.well
        }
    }

    override func layout() {
        super.layout()
        // Moved on every frame of a scroll, so it never animates: a band
        // easing behind the page reads as lag.
        Tokens.Motion.immediately {
            bandClip.frame = bounds
            let width = (bounds.width * (progress ?? 0)).rounded()
            let x = userInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0
            band.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
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
    /// `animated: false` is a cancel, not a shorter fade, which is why it does
    /// not take the `alphaValue` short-cut the animated path does: the value
    /// asked for may be the one a running animation is already heading to, and
    /// the point of the call is that the pill has to be there now. §6's Space
    /// switch needs it — the list under this pill is a different Space's by
    /// then, and a fill still fading out of the Space you left is a glass pill
    /// lying in the Space you arrived in with no row inside it.
    ///
    /// Clearing every animation is safe here because each one this view carries
    /// — this fade, `move`'s spring, `stretch` — is one a cancel should end,
    /// and `move` asks for an unanimated fade only on the branch that has just
    /// cancelled the other two.
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
