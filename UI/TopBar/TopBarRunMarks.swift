//
//  TopBarRunMarks.swift
//  Luna
//
//  What §4's run draws that is not a tab: the plate the Space's name and its
//  kept tabs stand on, the dashed slot a lift is about to land in, and the
//  spine that says which tabs are in a folder.
//
//  Both are the column's, turned on their side. The dash is §3.3's — what Luna
//  draws where a thing goes, in the grid's empty slot and round a folder taking
//  a drop. The spine is §3.4b's hairline down the leading edge of a folder's
//  tabs; a bar has no leading edge to run down, so it runs along under them.
//
//  The slot and the spine take no click: they are marks. The plate does — it
//  is a shelf of controls rather than bar, so a press on it does not move the
//  window (§4), and a right-click on it is the bar's.
//

import AppKit

/// §4's plate: one piece of glass under the Space's name and its kept tabs —
/// §4's action capsule's material, at the capsule's height, so the two ends of
/// the bar are made of the same thing. An `NSControl` so a press on it stays
/// its own — see `TopBarTabRow`.
@MainActor
final class TopBarPlate: NSControl {

    var menuBuilder: (() -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: TopBarMetrics.plate.cornerRadius)
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

/// §3.4b's spine, along the foot of a folder's open tabs.
@MainActor
final class TopBarFolderSpine: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func applyTokens() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = Tokens.Line.hairline.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }
}
