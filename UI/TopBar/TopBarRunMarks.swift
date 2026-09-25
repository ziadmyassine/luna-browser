//
//  TopBarRunMarks.swift
//  Luna
//
//  What §4's run draws that is not a tab: the plate the Space's name and its
//  kept tabs stand on — and each open folder, on one of its own — and the
//  dashed slot a lift is about to land in.
//
//  The dash is §3.3's — what Luna draws where a thing goes, in the grid's
//  empty slot and round a folder taking a drop.
//
//  The slot takes no click: it is a mark. The plate does — it is a shelf of
//  controls rather than bar, so a press on it does not move the window (§4),
//  and a right-click on it is the bar's menu, or its folder's.
//

import AppKit

/// §4's plate: one piece of glass under the Space's name and its kept tabs —
/// §4's action capsule's material, at the capsule's height, so the two ends of
/// the bar are made of the same thing. An `NSControl` so a press on it stays
/// its own — see `TopBarTabRow`.
@MainActor
final class TopBarPlate: NSControl {

    var menuBuilder: (() -> NSMenu?)?

    /// §6.6's lift is going into the folder this plate holds. It lifts the
    /// way a row does under the pointer — §3.4's hover wash over the glass —
    /// the plate's answer to the column's dashed box round a folder.
    var isAimedAt = false {
        didSet { if isAimedAt != oldValue { applyLight() } }
    }

    /// A folder's plate answers the pointer anywhere on the folder — its
    /// name, its tabs, the room between them — the way §3.4b's plate closes
    /// round a folder in the column: the same wash, with the hairline that
    /// plate is drawn with. The Space's plate does not; it is the bar's shelf,
    /// not a thing the pointer is in.
    var lightsUnderPointer = false {
        didSet { if lightsUnderPointer != oldValue { updateTrackingAreas() } }
    }

    private var isPointerInside = false {
        didSet { if isPointerInside != oldValue { applyLight() } }
    }

    /// The hover wash and the folder's hairline, over the glass. Read by tests.
    let wash = NSView()

    private func applyLight() {
        let lit = isAimedAt || isPointerInside
        let outlined = isPointerInside
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Tokens.Motion.wash(self.wash.layer, to: lit ? Tokens.Surface.hover : nil)
            // The hairline on the wash's clock, as `wash` sets the fill.
            let instant = Tokens.Motion.reduceMotion
            CATransaction.begin()
            CATransaction.setDisableActions(instant)
            CATransaction.setAnimationDuration(instant ? 0 : Tokens.Motion.controlHover.duration)
            CATransaction.setAnimationTimingFunction(Tokens.Motion.controlHover.timingFunction)
            self.wash.layer?.borderColor = (outlined ? Tokens.Line.border : NSColor.clear).cgColor
            CATransaction.commit()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        guard lightsUnderPointer else {
            isPointerInside = false
            return
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isPointerInside = true }
    override func mouseExited(with event: NSEvent) { isPointerInside = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLight()
    }

    /// How far a Space switch has carried the plate from `morphFrom` to
    /// `morphTo`: its glass reshaped for real on every frame, the one way
    /// glass changes shape on screen — `TopBarSpaceName.widthMorph`. An
    /// implicit frame animation moves the view and leaves the material at
    /// its new size from the first frame.
    @objc dynamic var frameMorph: CGFloat = 1 {
        didSet { landMorph() }
    }

    private var morphFrom: NSRect = .zero
    private var morphTo: NSRect = .zero

    /// Mid-morph, a layout pass moves where the morph is going rather than
    /// landing the plate there — `settle(at:)`.
    var isMorphing: Bool { frameMorph < 1 }

    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "frameMorph" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    /// From where it stands to `target`, on `spec`.
    func morph(to target: NSRect, on spec: MotionSpec) {
        guard frame != target, frame != .zero, !Tokens.Motion.reduceMotion else {
            return settle(at: target)
        }
        morphFrom = frame
        morphTo = target
        frameMorph = 0
        Tokens.Motion.animate(spec) { context in
            context.allowsImplicitAnimation = true
            animator().frameMorph = 1
        }
    }

    /// Where the layout says the plate belongs, from a pass that is not a
    /// morph: landed at once, or made the end of the morph under way.
    func settle(at target: NSRect) {
        morphTo = target
        guard !isMorphing else { return }
        morphFrom = target
        landMorph()
    }

    private func landMorph() {
        let travel = frameMorph
        func toward(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * travel }
        let target = NSRect(
            x: toward(morphFrom.minX, morphTo.minX),
            y: toward(morphFrom.minY, morphTo.minY),
            width: toward(morphFrom.width, morphTo.width),
            height: toward(morphFrom.height, morphTo.height)
        )
        Tokens.Motion.immediately { frame = target }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: TopBarMetrics.plate.cornerRadius)
        wash.wantsLayer = true
        wash.layer?.cornerCurve = .continuous
        wash.layer?.cornerRadius = TopBarMetrics.plate.cornerRadius
        wash.layer?.borderWidth = Tokens.Metric.hairline
        wash.layer?.borderColor = NSColor.clear.cgColor
        addSubview(wash)
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { wash.frame = bounds }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }

    /// Its glass is a subview that would otherwise take the press — and say
    /// the window may move.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point).map { _ in self }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    /// Kept, not passed on up to the window — `TopBarSpaceName.mouseDown`.
    override func mouseDown(with event: NSEvent) {}
}

/// §3.3's empty slot: a dashed outline where a lift is about to land — a
/// tile's shape among the kept tabs, a row's for a new folder.
@MainActor
final class TopBarSlotOutline: NSView {

    /// A glyph saying what landing here makes, centred in the outline. Nil
    /// for a tile's slot, which is a place and needs no caption.
    var symbolName: String? {
        didSet {
            glyph.image = symbolName.flatMap { TopBarButton.symbol($0) }
            glyph.isHidden = symbolName == nil
        }
    }

    /// A lift is over it. It fills the way a row does under the pointer —
    /// `SidebarPinHintView.isAimedAt`, the column's well, answers the same.
    var isAimedAt = false {
        didSet {
            guard isAimedAt != oldValue else { return }
            Tokens.Motion.wash(layer, to: isAimedAt ? Tokens.Surface.hover : nil)
        }
    }

    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = TopBarMetrics.keptTile.cornerRadius
        // Redrawn at every size rather than stretched: the dash is a fixed
        // length, and a scaled copy of it comes out at a different pitch.
        layerContentsRedrawPolicy = .duringViewResize
        glyph.isHidden = true
        glyph.contentTintColor = Tokens.Text.tertiary
        addSubview(glyph)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func layout() {
        super.layout()
        let size = TopBarMetrics.glyph
        Tokens.Motion.immediately {
            glyph.frame = NSRect(
                x: ((bounds.width - size) / 2).rounded(),
                y: ((bounds.height - size) / 2).rounded(),
                width: size,
                height: size
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = TopBarMetrics.keptTile.cornerRadius
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: Tokens.Metric.hairline / 2, dy: Tokens.Metric.hairline / 2),
            xRadius: radius,
            yRadius: radius
        )
        path.lineWidth = Tokens.Metric.hairline
        let dash = Tokens.Metric.pinHintDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        Tokens.Line.border.setStroke()
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glyph.contentTintColor = Tokens.Text.tertiary
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
