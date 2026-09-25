//
//  URLPillExtensions.swift
//  Luna
//
//  §16.4 in the sidebar's pill: the extensions button in the trailing slot,
//  where the site settings glyph used to stand (it leads now, as it does on
//  §3.2b's pill), and the pinned extensions to its left, as many as the
//  address can spare (`URLPillView.fittingPins`).
//
//  Every one of them is the chip the pill's other glyphs are — the same
//  capsule, hover and press — so the row of them reads as the pill's own
//  controls rather than a toolbar parked inside it.
//

import AppKit

extension URLPillView {

    /// One chip per pin, kept in pin order; the layout shows as many of them
    /// as fit and hides the rest.
    func dressPins() {
        let pins = showsExtensions ? extensionPins : []
        while pinGlyphs.count > pins.count { pinGlyphs.removeLast().removeFromSuperview() }
        while pinGlyphs.count < pins.count {
            let glyph = RowGlyphView()
            glyph.isRound = true
            addSubview(glyph, positioned: .below, relativeTo: loadLine)
            pinGlyphs.append(glyph)
        }
        for (glyph, pin) in zip(pinGlyphs, pins) {
            glyph.configure(
                image: ExtensionBadge.composite(pin.icon ?? ExtensionsSymbol.image, badge: pin.badge),
                label: pin.badge.isEmpty ? pin.name : "\(pin.name), \(pin.badge)"
            )
            glyph.tint = Tokens.Text.secondary
            glyph.onActivate = { [weak self, weak glyph] in
                guard let self, let glyph else { return }
                onExtension?(pin.id, glyph)
            }
        }
        needsLayout = true
    }

    /// The button in the trailing slot, the pins leftwards from it one chip
    /// apart. Chips touch: only one is ever lit, and a gap between them would
    /// be a dead strip of pill between two controls.
    func placeExtensions(trailingX: CGFloat, y: CGFloat, chip: NSSize) {
        guard showsExtensions else {
            for glyph in pinGlyphs { glyph.isHidden = true }
            return
        }
        extensionsGlyph.frame = NSRect(x: trailingX, y: y, width: chip.width, height: chip.height).integral
        let fitting = fittingPins
        for (index, glyph) in pinGlyphs.enumerated() {
            glyph.isHidden = index >= fitting
            guard index < fitting else { continue }
            // Pin order runs left to right, ending beside the button.
            let fromButton = CGFloat(fitting - index)
            glyph.frame = NSRect(x: trailingX - fromButton * chip.width, y: y, width: chip.width, height: chip.height).integral
        }
    }
}
