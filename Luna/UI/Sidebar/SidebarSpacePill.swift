//
//  SidebarSpacePill.swift
//  Luna
//
//  §3.5's Space pill: the active Space's name in a capsule of glass at the
//  leading end of the sidebar's foot, the same cylinder §4's bar ends on
//  (`TopBarSpaceCapsule`). The dots stand on their own in the middle of the
//  foot, so here the pill is only the name, with §9's picture ahead of it when
//  the Space has one.
//
//  The capsule is a `GlassButton` stretched wide, so hover, press and focus are
//  that button's. The name is drawn inside the button, so it swells with it.
//

import AppKit

@MainActor
final class SidebarSpacePill: NSView {

    /// The control. `SidebarUtilityBar` wires its press and its menu.
    let button = GlassButton(
        shape: Tokens.Metric.bottomCircle,
        symbolName: "",
        pointSize: Tokens.Metric.glyphSize,
        label: String(localized: "Space")
    )
    /// Clips a name past the ceiling, or past what the foot has room for, and
    /// carries the ramp that ends it — three characters spent on an `…` say less than three more of
    /// the name. Internal for `SidebarSpacePillTests`.
    let clip = NSView()
    let label = NSTextField(labelWithString: "")
    /// §9's picture, hidden when the Space has none. Internal for `ProfilePictureTests`.
    let portrait = NSImageView()
    private let fadeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Clipping, not truncating: the fade is what ends an over-long name,
        // and an ellipsis would be drawn before it got there.
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(label)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        portrait.imageScaling = .scaleProportionallyUpOrDown
        portrait.wantsLayer = true
        portrait.layer?.masksToBounds = true
        portrait.isHidden = true
        button.addSubview(portrait)
        button.addSubview(clip)
        addSubview(button)
        button.onInkChange = { [weak self] ink in self?.label.textColor = ink }
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    func show(name: String?, picture: NSImage?) {
        label.stringValue = name ?? ""
        portrait.image = picture
        portrait.isHidden = picture == nil
        needsLayout = true
    }

    /// The whole name, its padding and the picture if there is one — sized
    /// the way §4's Space cylinder is, with the same ceiling on the name
    /// (`TopBarMetrics.nameCeiling`) — and never narrower than the circle this
    /// replaced: a one-letter name in a pill thinner than the Downloads button
    /// reads as a mistake.
    var naturalWidth: CGFloat {
        let name = min(Self.textWidth(label.stringValue), TopBarMetrics.nameCeiling)
        let height = Tokens.Metric.bottomCircle.height
        return max(ceil(nameLead + name + Tokens.Metric.sidebarSpacePillPad), height)
    }

    /// Where the name starts: at the pill's padding, or after the picture.
    /// The picture fills the circle at the pill's end, so the name starts
    /// where that circle stops.
    private var nameLead: CGFloat {
        portrait.isHidden ? Tokens.Metric.sidebarSpacePillPad : Tokens.Metric.bottomCircle.height
    }

    /// The picture sits in the capsule's end the way a glyph sits in a circle
    /// of glass: a ring of material round it, as thick as §4's capsule leaves
    /// round its items (`TopBarMetrics.capsuleInset`).
    private static var pictureInset: CGFloat { TopBarMetrics.capsuleInset }

    /// What the glyphs measure, which is not what the field reports: the cell
    /// keeps 2 pt of its own either side and `intrinsicContentSize` counts
    /// none of it, so a box cut to that width loses the last letter.
    private static func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: Tokens.TypeScale.topBarSpaceName]).size().width
    }

    /// The leading half of what the cell keeps for itself, asked of the cell
    /// so nothing here breaks if it stops being 2 pt.
    static func padding(of field: NSTextField) -> CGFloat {
        let cell = field.cell?.cellSize.width ?? 0
        return max((cell - textWidth(field.stringValue)) / 2, 0)
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`,
        // which also stops the mask below animating its own frame.
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        button.frame = bounds
        let inset = Self.pictureInset
        let side = max(bounds.height - 2 * inset, 0)
        portrait.frame = NSRect(x: inset, y: inset, width: side, height: side)
        portrait.layer?.cornerRadius = side / 2

        let natural = ceil(Self.textWidth(label.stringValue))
        let room = max(bounds.width - nameLead - Tokens.Metric.sidebarSpacePillPad, 0)
        let shown = min(natural, room)
        // Centred in its room, which is the room exactly unless the pill is
        // held at its one-circle minimum around a short name.
        let box = NSRect(
            x: nameLead + (room - shown) / 2,
            y: 0,
            width: shown,
            height: bounds.height
        ).integral
        clip.frame = box
        let pad = Self.padding(of: label)
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(
            x: -pad,
            y: ((box.height - height) / 2).rounded(),
            width: max(natural, box.width) + 2 * pad,
            height: height
        )
        applyFade(overflowing: natural > box.width, width: box.width)
    }

    /// Nil when the name fits: a gradient that is opaque end to end is a
    /// masked composite drawing nothing.
    private func applyFade(overflowing: Bool, width: CGFloat) {
        let ramp = Tokens.Metric.sidebarSpaceNameFade
        guard overflowing, width > ramp else {
            clip.layer?.mask = nil
            return
        }
        // A mask reads alpha and nothing else, so this is not an ink and no
        // token belongs in it.
        fadeMask.frame = clip.bounds
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - ramp / width)), 1]
        clip.layer?.mask = fadeMask
    }

    /// The name and the picture are the button's face, not controls of their
    /// own, so a press anywhere on the pill is the button's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : button
    }

    private func applyTokens() {
        // §4's name, in the same type and ink, so the Space reads as the same
        // control in both layouts. The ink is the glyphs' beside it: resting
        // at `secondary` and lifting under the pointer, which the button
        // reports through `onInkChange`.
        label.font = Tokens.TypeScale.topBarSpaceName
        label.textColor = button.ink
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// §21.2: Increase Contrast is not an appearance, so the sidebar tells this
    /// by hand along with every other surface that draws text.
    func accessibilityDisplayOptionsChanged() {
        applyTokens()
    }
}
