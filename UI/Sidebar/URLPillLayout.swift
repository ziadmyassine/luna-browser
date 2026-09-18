//
//  URLPillLayout.swift
//  Luna
//
//  Where §3.2's pill puts its two pieces, and how wide and how round it is.
//
//  Split out of `URLPillView.swift` for the reason `Metrics+Windows.swift` was
//  split out of `Metrics.swift`: that file crossed SwiftLint's 400-line limit
//  once the pill grew §3.2b's second layout. Nothing changed on the way across.
//
//  `field` and `sliders` are `internal` rather than `private` so this file can
//  reach them. That is the whole cost of the split, and it is worth naming:
//  they are still the pill's, and nothing outside these two files touches them.
//

import AppKit

extension URLPillView {

    /// The narrowest this pill can be and still show its whole domain, in
    /// `centresText` layout — §3.2b's collapsed capsule shrinks to the address
    /// rather than to a number someone picked.
    var fittingWidth: CGFloat {
        let overhang = (Tokens.Metric.rowTrailingChip.width - Tokens.Metric.pillGlyphSize) / 2
        let margin = Tokens.Metric.pillGlyphInset - overhang
            + Tokens.Metric.rowTrailingChip.width
            + Tokens.Metric.chromeGap
        return 2 * margin + ceil(field.intrinsicContentSize.width)
    }

    /// A capsule at any height: §3.2's is always 34 pt, but §3.2b's collapses,
    /// and a 17 pt radius on a 22 pt capsule is a rectangle with dents in it.
    var cornerRadius: CGFloat {
        min(Tokens.Metric.urlPill.cornerRadius, bounds.height / 2)
    }

    // MARK: - Layout

    /// §3.2's own two insets, which until now were both silently `rowInset`:
    /// the domain starts 12 pt in and the sliders glyph sits 10 pt from the
    /// trailing edge. Both are measured, and they are deliberately unequal — a
    /// glyph is optically smaller than its box.
    ///
    /// **The inset is the glyph's, and the chip grows past it.** `pillGlyphInset`
    /// is measured to the mark the eye sees, so the hover chip — which is
    /// bigger than the glyph inside it — is placed by centring it on where the
    /// glyph would have been rather than by being inset itself. Insetting the
    /// chip instead would move the glyph 2.5 pt further in the moment it gained
    /// a background it only shows on hover.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            placeContents()
            refreshGlassShape()
        }
    }

    private func placeContents() {
        let glyph = Tokens.Metric.pillGlyphSize
        let chip = Tokens.Metric.rowTrailingChip
        let overhang = (chip.width - glyph) / 2
        let height = field.intrinsicContentSize.height
        let inset = Tokens.Metric.pillGlyphInset
        // §3.2: two further slots, reserved and sized, rendering nothing.
        let reserved = 2 * (glyph + Tokens.Metric.chromeGap)
        let chipY = (bounds.height - chip.height) / 2
        let textY = (bounds.height - height) / 2

        guard !centresText else {
            sliders.frame = NSRect(
                x: bounds.minX + inset - overhang,
                y: chipY,
                width: chip.width,
                height: chip.height
            ).integral
            // Symmetric margins, so the text is centred in the **pill** rather
            // than in the space the glyph leaves: an off-centre domain in a
            // centred capsule is worse than no centring at all.
            //
            // **And no reserved slots.** §3.2 holds two glyph-sized places open
            // for controls that are not built; they belong to a pill that is one
            // row of a column, where the column's other rows will grow the same
            // controls. A capsule floating on the page is sized to what it
            // shows, and 42 pt of held-open nothing at each end is what made it
            // read as an empty bar with a word in it.
            let margin = sliders.frame.maxX + Tokens.Metric.chromeGap
            field.frame = NSRect(
                x: margin,
                y: textY,
                width: max(bounds.width - 2 * margin, 0),
                height: height
            ).integral
            field.alignment = .center
            return
        }
        field.alignment = .natural
        sliders.frame = NSRect(
            x: bounds.maxX - inset + overhang - chip.width,
            y: chipY,
            width: chip.width,
            height: chip.height
        ).integral
        let textRight = sliders.frame.minX - reserved
        let textLeft = Tokens.Metric.pillTextInset
        field.frame = NSRect(
            x: textLeft,
            y: textY,
            width: max(textRight - textLeft, 0),
            height: height
        ).integral
    }
}
