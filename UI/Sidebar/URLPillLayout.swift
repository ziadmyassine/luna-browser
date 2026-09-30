//
//  URLPillLayout.swift
//  Luna
//
//  Where §3.2's pill puts its two pieces, and how wide and how round it is.
//
//  Split out of `URLPillView.swift` for its length limit, once the pill grew
//  §3.2b's second layout.
//
//  `field` and `sliders` are `internal` rather than `private` so this file can
//  reach them. That is the whole cost of the split: they are still the pill's,
//  and nothing outside these two files touches them.
//

import AppKit

extension URLPillView {

    /// How big the pill's two glyphs are drawn, which is a fact about the pill
    /// they are in.
    ///
    /// 14 on the bar, 13 in the column, and neither is `glyphSize`: 16 is the
    /// size of a glyph that is its own button (the §3.1 circles, §3.2b's
    /// toggle and history cluster). A glyph is measured against what shares its
    /// surface, and inside a capsule with an address in it 16 read as the
    /// loudest mark on the bar. In the column, `pillGlyphSize` is ink beside
    /// text set at 13 with barely a finger's width between them.
    var glyphInk: CGFloat {
        centresText ? Tokens.Metric.barPillGlyphSize : Tokens.Metric.pillGlyphSize
    }

    /// How far that ink sits from its own end of the pill: the text's own
    /// inset, on both pills, so whatever is at either end stands the same
    /// distance in as the address does.
    ///
    /// Not `pillGlyphInset`, two points tighter: in a 240 pt column, with the
    /// capsule's corner curving away right behind it, a glyph that close in
    /// reads as site settings falling off the end of the pill.
    private var glyphInset: CGFloat { Tokens.Metric.pillTextInset }

    /// The glyph's hit target: the ink plus a gap's worth of padding, so a
    /// control the size of a word is still something you can hit, without the
    /// box hanging off the end of the pill it is inside.
    private var glyphBox: CGFloat { glyphInk + Tokens.Metric.chromeGap }

    /// Which end the sliders glyph is on, which is a fact about whether
    /// this pill also carries a reload or §16.4's extensions.
    ///
    /// One affordance on a pill goes on the trailing edge — that is where §3.2
    /// has always drawn it, and where §3.4's rows draw theirs. A second one
    /// has to take the other end, and site settings is the one that describes
    /// what the address is, so it leads and reload trails.
    private var slidersLead: Bool { onReload != nil || showsExtensions }

    /// The room a glyph takes out of the text's line: the mark, its inset, and
    /// the gap between it and the address.
    private var glyphRun: CGFloat { glyphInset + glyphInk + Tokens.Metric.chromeGap }

    /// The Aa glyph's chip, standing just inside the trailing glyph.
    var readingRun: CGFloat { showsReading ? chipWidth : 0 }

    /// What the text keeps clear at each end.
    private var margins: (leading: CGFloat, trailing: CGFloat) {
        // A pill with both is symmetric, which is what lets §3.2b centre the
        // address in the capsule rather than in the space one glyph leaves.
        guard slidersLead else { return (Tokens.Metric.pillTextInset, glyphRun + readingRun) }
        guard showsExtensions else { return (glyphRun, glyphRun + readingRun) }
        return (glyphRun, glyphRun + readingRun + CGFloat(fittingPins) * chipWidth)
    }

    /// The chip's box, height and width, for a pill of this height — see
    /// `placeContents` for why it is wider than it is tall.
    private var chipBox: CGFloat { min(glyphBox, bounds.height) }
    var chipWidth: CGFloat {
        let box = chipBox
        return max(box, 2 * (glyphInset + glyphInk / 2 - (bounds.height - box) / 2))
    }

    /// §16.4: how many pinned extensions stand beside the extensions button.
    /// The address keeps `pinnedExtensionsAddressShare` of the pill; the
    /// sliders' run and the button's come out of the rest, and the pins share
    /// what is left, one chip each.
    var fittingPins: Int {
        let room = bounds.width * (1 - Tokens.Metric.pinnedExtensionsAddressShare) - 2 * glyphRun - readingRun
        return ExtensionShelfFit.count(extensionPins.count, room: room, pitch: chipWidth)
    }

    /// A capsule at any height: §3.2's is always 34 pt, but §3.2b's collapses,
    /// and a 17 pt radius on a 22 pt capsule is a rectangle with dents in it.
    var cornerRadius: CGFloat {
        min(Tokens.Metric.urlPill.cornerRadius, bounds.height / 2)
    }

    // MARK: - Layout

    /// §3.2's inset: everything on the pill — the address at one end, a glyph
    /// at either — stands `pillTextInset` in from the edge nearest it. See
    /// `glyphInset`, and `placeContents` for why the glyph's box is centred on
    /// the ink rather than inset itself.
    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            placeContents()
            refreshGlassShape()
            // And the corner has to be re-cut. `cornerRadius` is half the
            // pill's height, `updateLayer` is where it is applied, and nothing
            // marks a view for display merely because it was resized. Without
            // this, the sidebar's pill kept the radius from the column's first
            // layout, at a fraction of the final height, and stayed a rounded
            // rectangle. `wantsUpdateLayer` makes asking again nearly free.
            needsDisplay = true
        }
    }

    /// How wide what the field is showing needs to draw in full — the
    /// address, or the placeholder when there is no address.
    ///
    /// Asked of the cell, not of `intrinsicContentSize` and not of the string.
    /// A truncating `NSTextField` answers `noIntrinsicMetric` for its width — a
    /// -1 that became a zero-width frame and a bar with a magnifier and no
    /// address in it — and the string's own `size()` is a couple of points
    /// short of what the cell draws in, which truncated `New Tab` to `New T…`
    /// in a bar with 600 pt to spare. `cellSize` answers the question actually
    /// being asked.
    ///
    /// Measured through a copy of the cell, because the placeholder has to be
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
        // thing on the pill whose place does not depend on what else is on it
        // — only on the capsule it lies in, corner and all.
        loadLine.place(inPill: bounds, cornerRadius: cornerRadius)
        let box = chipBox
        let height = field.intrinsicContentSize.height
        let textY = (bounds.height - height) / 2
        let boxY = (bounds.height - box) / 2
        // Inset to the ink, not to the box: the box is a hit target and is
        // bigger than the mark inside it, so insetting it would put the mark
        // further in than the number says.
        //
        // Across, the box is a capsule concentric with the pill's own end: it
        // stands as far in from that end as from the top and bottom. A circle
        // there was a second curve inside the pill's, and the chip that
        // matches it comes out a few points wider than it is tall.
        let chip = chipWidth
        let overhang = (chip - glyphInk) / 2
        field.alignment = .natural

        let leadingX = glyphInset - overhang
        let trailingX = bounds.maxX - glyphInset + overhang - chip
        // Reload always trails. The sliders takes the other end when there is
        // one to take, and the trailing edge itself when there is not.
        sliders.frame = NSRect(
            x: slidersLead ? leadingX : trailingX,
            y: boxY,
            width: chip,
            height: box
        ).integral
        reload.frame = NSRect(x: trailingX, y: boxY, width: chip, height: box).integral
        // Off reload's rounded frame, not rounded itself: `integral` grows a
        // box that starts on a half point, and two grown boxes overlapped.
        reading.frame = reload.frame.offsetBy(dx: -reload.frame.width, dy: 0)
        placeExtensions(trailingX: trailingX, pinsEnd: trailingX - readingRun, y: boxY, chip: NSSize(width: chip, height: box))

        let margin = margins
        let run = max(bounds.width - margin.leading - margin.trailing, 0)
        guard !centresText else {
            // One line, centred between them. Symmetric margins, so it is
            // centred in the pill rather than in the space one glyph leaves:
            // an off-centre domain in a centred capsule is worse than no
            // centring at all. What is centred is the address alone — or the
            // placeholder, measured the same way, which is the whole of what a
            // new tab shows.
            let text = min(ceil(textWidth), run)
            field.frame = NSRect(
                x: margin.leading + max((run - text) / 2, 0),
                y: textY,
                width: text,
                height: height
            ).integral
            return
        }
        // No glyph-sized places held open beside the sliders for actions that
        // are not built (§16.4 puts extensions in §4's action capsule). Two of
        // them cost 42 pt, and in a column barely 200 pt wide, with a real
        // control at each end, the placeholder itself truncated to `Search the…`.
        field.frame = NSRect(x: margin.leading, y: textY, width: run, height: height).integral
    }
}
