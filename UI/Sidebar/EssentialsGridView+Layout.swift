//
//  EssentialsGridView+Layout.swift
//  Luna
//
//  §3.3's grid arithmetic: how many rows and columns a given number of pinned
//  tiles makes, where each slot is, and which slot a point falls in.
//
//  Split out of `EssentialsGridView.swift` for that file's length limit. This
//  is the half that is only arithmetic: it reads the grid's state and touches
//  none of it, so it can be checked against §3.3 without a window
//  (`shape(for:)` is asserted in `EssentialsGridTests`).
//
//  `maxColumns`, `order` and `settled` are internal rather than private only
//  because they are read from here.
//

import AppKit

extension EssentialsGridView {

    /// The tiles that are on the grid right now — everything but the one in
    /// the air.
    var settled: [UUID] {
        order.filter { $0 != draggedID }
    }

    /// How many slots the grid is laying out: the settled tiles, plus the one a
    /// live drag is holding open.
    private var slotCount: Int {
        let open = dropIndex == nil ? 0 : 1
        return max(settled.count + open, isAwaitingDrop ? 1 : 0)
    }

    /// As few rows as will hold them, then as evenly as they divide.
    ///
    /// Rows first: four across is the ceiling, so five tiles need two rows and
    /// nine need three. Then the columns are whatever spreads that many tiles
    /// over that many rows — 5 over 2 is 3 and not 4, which is what makes five
    /// tiles read as 3 + 2 rather than as 4 + 1. A short last row is left-
    /// aligned, because the grid fills in reading order and a centred orphan
    /// would break the column the tiles above it stand in.
    ///
    /// Static and pure, for the same reason `ChromeState.cardInsets` is: §3.3's
    /// shape is arithmetic, and arithmetic can be asserted without a window.
    static func shape(for count: Int) -> (rows: Int, columns: Int) {
        guard count > 0 else { return (0, 1) }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return (rows, max(Int((Double(count) / Double(rows)).rounded(.up)), 1))
    }

    private var columns: Int { Self.shape(for: slotCount).columns }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height(forTiles: slotCount, hinting: isHinting))
    }

    /// How tall a grid holding `count` tiles stands.
    ///
    /// Static as well as an instance answer because §30.9's page turn has to
    /// draw the neighbouring Space's grid — `SpacePreviewView` — and a still
    /// that guessed its own height would hand the swipe a picture the real
    /// column then corrects.
    static func height(forTiles count: Int, hinting: Bool = false) -> CGFloat {
        // §3.3a's well is one empty tile, so a grid giving advice is exactly as
        // tall as it will be the moment the first tab is pinned — and it stays
        // that tall for the length of a drag, which is why the well and not
        // `isAwaitingDrop` answers first. Nothing moves when a lift comes up,
        // and nothing moves when it lands either.
        guard !hinting else { return height(forTiles: 1) }
        let rows = shape(for: count).rows
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * Tokens.Metric.essentialsTile.height
            + CGFloat(rows - 1) * Tokens.Metric.essentialsRowGap
            + 2 * Tokens.Metric.essentialsVerticalInset
    }

    /// One slot's frame, in reading order. The single piece of grid arithmetic:
    /// the tiles, the drop outline, the drag lift and §30.9's still all place
    /// themselves with it, so they cannot disagree about where a slot is.
    func slotRect(at index: Int) -> NSRect {
        Self.slotRect(at: index, of: slotCount, in: bounds)
    }

    /// `slotRect(at:)` for a grid that is not this one — the same arithmetic,
    /// told how many tiles and what bounds instead of reading its own.
    static func slotRect(at index: Int, of count: Int, in bounds: NSRect) -> NSRect {
        let inset = Tokens.Metric.essentialsInset
        let margin = Tokens.Metric.essentialsVerticalInset
        let gutter = Tokens.Metric.essentialsTileGap
        let rowGap = Tokens.Metric.essentialsRowGap
        let height = Tokens.Metric.essentialsTile.height
        let across = shape(for: count).columns
        let width = (bounds.width - 2 * inset - CGFloat(across - 1) * gutter) / CGFloat(across)
        let column = index % across
        let row = index / across
        // Top-down in an unflipped view: the first row sits highest.
        return NSRect(
            x: inset + CGFloat(column) * (width + gutter),
            y: bounds.maxY - margin - CGFloat(row + 1) * height - CGFloat(row) * rowGap,
            width: max(width, 0),
            height: height
        ).pixelAligned
    }

    /// Which slot the pointer is over, in reading order — and the index the
    /// tab would land at, which is why it counts the settled tiles rather
    /// than all of them: the one in the air is already out of the way.
    func insertionIndex(at point: NSPoint) -> Int {
        let inset = Tokens.Metric.essentialsInset
        let gap = Tokens.Metric.essentialsTileGap
        let across = columns
        let tileWidth = (bounds.width - 2 * inset - CGFloat(across - 1) * gap) / CGFloat(across)
        let column = min(max(Int((point.x - inset) / max(tileWidth + gap, 1)), 0), across - 1)
        let fromTop = bounds.maxY - Tokens.Metric.essentialsVerticalInset - point.y
        let pitch = Tokens.Metric.essentialsTile.height + Tokens.Metric.essentialsRowGap
        let row = max(Int(fromTop / max(pitch, 1)), 0)
        return min(row * across + column, settled.count)
    }
}
