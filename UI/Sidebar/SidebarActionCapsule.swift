//
//  SidebarActionCapsule.swift
//  Luna
//
//  §3.5's Downloads and History, as **one cylinder rather than two circles**.
//
//  They were two `GlassButton`s standing side by side, each carrying its own
//  `.control` backing. Two glass discs 5 pt apart do not read as a pair — they
//  read as two controls that happen to be near each other, each with its own
//  specular rim catching the light at a different angle. `TopBarActionCapsule`
//  found the same thing at the other end of the window and came to the same
//  answer: apply the glass **once**, at full radius, and let the buttons inside
//  it be bare glyphs.
//
//  That is also why the buttons are `GlassMode.none` rather than `.dormant`.
//  Dormant would fade a second material in under the pointer, inside a surface
//  that is already the material; the hover here is the glyph lifting from
//  `Text.secondary` to `Text.primary`, which is §3.1's rule and what the rest
//  of the sidebar does.
//
//  The cylinder is exactly `bottomCircle` tall — it is two of those circles
//  fused, not a new size — so it still sits on the avatar's centre line and
//  the foot of the sidebar stays one row of equal-height controls.
//

import AppKit

@MainActor
final class SidebarActionCapsule: NSView {

    private let buttons: [GlassButton]

    /// - Parameter items: glyph, VoiceOver label and what the button does, in
    ///   the order they appear. Two today; the array is what lets a third
    ///   arrive without re-measuring the bar around it.
    init(items: [(symbolName: String, label: String, action: () -> Void)]) {
        buttons = items.map { item in
            let button = GlassButton(
                shape: Tokens.Metric.bottomCircle,
                symbolName: item.symbolName,
                pointSize: Tokens.Metric.glyphSize,
                label: item.label,
                glassMode: .none
            )
            button.onActivate = item.action
            return button
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.bottomCircle.height / 2)
        for button in buttons { addSubview(button) }
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Library"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The button at `index`, for a pop-out to stand on. A pop-out anchored to
    /// the whole cylinder would point at the gap between its two glyphs.
    func button(at index: Int) -> NSView {
        buttons.indices.contains(index) ? buttons[index] : self
    }

    override var intrinsicContentSize: NSSize {
        let circle = Tokens.Metric.bottomCircle
        return NSSize(width: circle.width * CGFloat(buttons.count), height: circle.height)
    }

    /// **Butted, not spaced.** The gap is what made two circles read as two;
    /// the glyphs are already a `glyphSize` mark inside a `bottomCircle` slot,
    /// so each one keeps its own air without any between the slots.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            let circle = Tokens.Metric.bottomCircle
            let originY = ((bounds.height - circle.height) / 2).rounded()
            for (index, button) in buttons.enumerated() {
                button.frame = NSRect(
                    x: CGFloat(index) * circle.width,
                    y: originY,
                    width: circle.width,
                    height: circle.height
                ).pixelAligned
            }
        }
    }

    /// §30.1: the sidebar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }
}
