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

    /// The margin `centresText` layout keeps at each end.
    private var centredMargin: CGFloat {
        // Bare, there is no glyph to clear and the text keeps §3.2's own inset.
        // Read from the surface, not from the glyph's `isHidden`: the glyph
        // fades out over §3.2b's morph and is hidden at the end of it, and a
        // margin that waited for that would size the collapsed capsule for a
        // control it is in the middle of dropping.
        guard surface != .bare else { return Tokens.Metric.pillTextInset }
        let overhang = (Tokens.Metric.rowTrailingChip.width - Tokens.Metric.pillGlyphSize) / 2
        let trailingEdge = (Tokens.Metric.pillGlyphInset - overhang
            + Tokens.Metric.rowTrailingChip.width).rounded(.up)
        return trailingEdge + Tokens.Metric.chromeGap
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

    /// The leading mark's box, and the room the text gives up for it.
    ///
    /// Square and `faviconSize`, because it is §3.4's favicon slot — see
    /// `URLPillView.mark`.
    private var markBox: CGFloat { Tokens.Metric.faviconSize }
    private var markRun: CGFloat { markBox + Tokens.Metric.chromeGap }

    /// How wide what the field is *showing* needs to draw in full — the
    /// address, or the placeholder when there is no address.
    ///
    /// Asked of the **cell**, not of `intrinsicContentSize` and not of the
    /// string. A truncating `NSTextField` answers `noIntrinsicMetric` for its
    /// width — a -1 that became a zero-width frame and a bar with a magnifier
    /// and no address in it — and the string's own `size()` is a couple of
    /// points short of what the cell draws in, which truncated `New Tab` to
    /// `New T…` in a bar with 600 pt to spare. `cellSize` is the one of the
    /// three that answers the question actually being asked: how wide this
    /// cell has to be to show all of itself.
    ///
    /// Measured through a *copy* of the cell, because the placeholder has to be
    /// measured as though it were the value, and the live cell is mid-edit.
    private var textWidth: CGFloat {
        let showing = field.stringValue.isEmpty ? (field.placeholderString ?? "") : field.stringValue
        guard !showing.isEmpty, let cell = field.cell?.copy() as? NSTextFieldCell else { return 0 }
        cell.stringValue = showing
        let width = cell.cellSize.width
        return width.isFinite ? width : 0
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
        let markY = (bounds.height - markBox) / 2

        guard !centresText else {
            // **Trailing, the same side as §3.2's.** It led the capsule when
            // the text was centred in whatever the glyph left over, and a lone
            // control on the left of a centred phrase reads as the start of it
            // — the address looked pushed rather than placed. One control, one
            // side, in both layouts.
            sliders.frame = NSRect(
                x: bounds.maxX - inset + overhang - chip.width,
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
            //
            // **The mark travels with the text, and the pair is what is
            // centred.** Pinning it to the leading edge would leave it stranded
            // a long way from the address it is about, with the sliders glyph
            // already there; kept against the text it reads as one phrase —
            // what this is, then what it says.
            let margin = centredMargin
            let box = max(bounds.width - 2 * margin, 0)
            let natural = ceil(textWidth)
            let text = min(natural, max(box - markRun, 0))
            let run = markRun + text
            let start = margin + max((box - run) / 2, 0)
            mark.frame = NSRect(x: start, y: markY, width: markBox, height: markBox).integral
            field.frame = NSRect(x: start + markRun, y: textY, width: text, height: height).integral
            // Centred in a box it exactly fits, so this only matters while the
            // address is long enough to be truncated — and a truncated address
            // is read from its front.
            field.alignment = .natural
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
        // The mark takes §3.2's own text inset and the text starts after it —
        // a column of rows reads down its leading edge, so that is where the
        // thing that says what this row *is* belongs.
        mark.frame = NSRect(
            x: Tokens.Metric.pillTextInset,
            y: markY,
            width: markBox,
            height: markBox
        ).integral
        let textLeft = Tokens.Metric.pillTextInset + markRun
        field.frame = NSRect(
            x: textLeft,
            y: textY,
            width: max(textRight - textLeft, 0),
            height: height
        ).integral
    }
}
