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

    /// How big the pill's two glyphs are drawn, which is a fact about the pill
    /// they are in.
    ///
    /// **14 on the bar, 13 in the column**, and neither is `glyphSize`.
    ///
    /// 16 is the size of a glyph that is its own button — the §3.1 circles,
    /// §3.2b's toggle and history cluster — and the bar's pair started there to
    /// agree with the row of controls they sit in. What a glyph is measured
    /// against, though, is what shares its surface: inside a capsule with an
    /// address in it, 16 read as the loudest mark on the bar. The column's pill
    /// makes the same argument a step further — `pillGlyphSize` is ink beside
    /// text set at 13 with barely a finger's width between them.
    var glyphInk: CGFloat {
        centresText ? Tokens.Metric.barPillGlyphSize : Tokens.Metric.pillGlyphSize
    }

    /// How far that ink sits from its own end of the pill: **the text's own
    /// inset, on both pills.**
    ///
    /// The column's used to be `pillGlyphInset`, two points tighter, on the
    /// argument that a glyph is optically smaller than its box and can afford
    /// to sit closer in. On §3.2b's 420 pt bar that reads as intended; in a
    /// 240 pt column, with the capsule's corner curving away right behind it,
    /// it reads as site settings falling off the end of the pill — which is
    /// what Martin saw. The bar is the one that looks right, so the column now
    /// measures the same: whatever is at either end of a pill stands the same
    /// distance in as the address does.
    private var glyphInset: CGFloat { Tokens.Metric.pillTextInset }

    /// The glyph's hit target: the ink plus a gap's worth of padding, so a
    /// control the size of a word is still something you can hit, without the
    /// box hanging off the end of the pill it is inside.
    private var glyphBox: CGFloat { glyphInk + Tokens.Metric.chromeGap }

    /// **Which end the sliders glyph is on**, which is a fact about whether
    /// this pill also carries a reload.
    ///
    /// One affordance on a pill goes on the trailing edge — that is where §3.2
    /// has always drawn it, and where §3.4's rows draw theirs. A *second* one
    /// has to take the other end, and site settings is the one that describes
    /// what the address is, so it leads and reload trails.
    private var slidersLead: Bool { onReload != nil }

    /// The room a glyph takes out of the text's line: the mark, its inset, and
    /// the gap between it and the address.
    private var glyphRun: CGFloat { glyphInset + glyphInk + Tokens.Metric.chromeGap }

    /// What the text keeps clear at each end.
    ///
    /// Collapsed there is no control to clear and the text keeps §3.2's own
    /// inset. Read from the surface rather than from a glyph's `isHidden`:
    /// they fade out across §3.2b's morph and are hidden at the end of it, and
    /// a margin that waited for that would size the collapsed capsule for
    /// something it is in the middle of dropping.
    private var margins: (leading: CGFloat, trailing: CGFloat) {
        guard surface != .bare else {
            return (Tokens.Metric.pillTextInset, Tokens.Metric.pillTextInset)
        }
        // A pill with both is symmetric, which is what lets §3.2b centre the
        // address in the capsule rather than in the space one glyph leaves.
        guard slidersLead else { return (Tokens.Metric.pillTextInset, glyphRun) }
        return (glyphRun, glyphRun)
    }

    /// A capsule at any height: §3.2's is always 34 pt, but §3.2b's collapses,
    /// and a 17 pt radius on a 22 pt capsule is a rectangle with dents in it.
    var cornerRadius: CGFloat {
        min(Tokens.Metric.urlPill.cornerRadius, bounds.height / 2)
    }

    // MARK: - Layout

    /// §3.2's inset, which until now was silently `rowInset`: everything on the
    /// pill — the address at one end, a glyph at either — stands
    /// `pillTextInset` in from the edge nearest it. See `glyphInset`.
    ///
    /// **The inset is the glyph's ink, and its hit box grows past it.** The
    /// number is measured to the mark the eye sees, so the box — which is
    /// bigger than the glyph inside it — is placed by centring it on where the
    /// glyph would have been rather than by being inset itself. Insetting the
    /// box instead would move the glyph a further half-gap in.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            placeContents()
            refreshGlassShape()
            // **And the corner has to be re-cut.** `cornerRadius` is half the
            // pill's height, `updateLayer` is where it is applied, and nothing
            // marks a view for display merely because it was resized — so the
            // radius was whatever the height happened to be the last time
            // something else asked for a redraw. In the sidebar that was a pass
            // during the column's first layout, at a fraction of the final
            // height, and the pill stayed a rounded rectangle for the rest of
            // the session. `wantsUpdateLayer` makes asking again nearly free.
            needsDisplay = true
        }
    }

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
        // §3.2c, before anything that can return early: the line is the one
        // thing on the pill whose place does not depend on what else is on it.
        loadLine.frame = LoadProgressLine.frame(inPill: bounds)
        let box = min(glyphBox, bounds.height)
        let height = field.intrinsicContentSize.height
        let textY = (bounds.height - height) / 2
        let boxY = (bounds.height - box) / 2
        // Inset to the **ink**, not to the box: the box is a hit target and is
        // bigger than the mark inside it, so insetting it would put the mark
        // further in than the number says.
        let overhang = (box - glyphInk) / 2
        field.alignment = .natural

        let leadingX = glyphInset - overhang
        let trailingX = bounds.maxX - glyphInset + overhang - box
        // Reload always trails. The sliders takes the other end when there is
        // one to take, and the trailing edge itself when there is not.
        sliders.frame = NSRect(
            x: slidersLead ? leadingX : trailingX,
            y: boxY,
            width: box,
            height: box
        ).integral
        reload.frame = NSRect(x: trailingX, y: boxY, width: box, height: box).integral

        let margin = margins
        let run = max(bounds.width - margin.leading - margin.trailing, 0)
        guard !centresText else {
            // **One line, centred between them.** Symmetric margins, so it is
            // centred in the *pill* rather than in the space one glyph leaves:
            // an off-centre domain in a centred capsule is worse than no
            // centring at all. What is centred is the address alone — or the
            // placeholder, measured the same way, which is the whole of what a
            // new tab shows.
            //
            let text = min(ceil(textWidth), run)
            field.frame = NSRect(
                x: margin.leading + max((run - text) / 2, 0),
                y: textY,
                width: text,
                height: height
            ).integral
            return
        }
        // **The two reserved slots are gone.** §3.2 held two further
        // glyph-sized places open beside the sliders for AI and extension
        // actions that are not built and that §16.4 puts in §4's action capsule
        // anyway. They cost 42 pt, and in a column barely 200 pt wide — with a
        // real control now at each end — that was most of the line: the short
        // placeholder itself truncated, to `Search the…`. A slot held open for
        // nothing is not worth a word of the address.
        field.frame = NSRect(x: margin.leading, y: textY, width: run, height: height).integral
    }
}
