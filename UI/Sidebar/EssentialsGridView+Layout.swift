//
//  EssentialsGridView+Layout.swift
//  Luna
//
//  §3.3's grid arithmetic: how many rows and columns a given number of pinned
//  tiles makes, where each slot is, and which slot a point falls in.
//
//  Split out of `EssentialsGridView.swift` when it crossed SwiftLint's 400-line
//  file limit, and this is the half that came out because it is the half that
//  is *only* arithmetic — it reads the grid's state and touches none of it, so
//  it can be checked against §3.3 without a window (`shape(for:)` is asserted
//  directly in `EssentialsGridTests`).
//
//  `maxColumns`, `order` and `settled` are internal rather than private for one
//  reason: they are read from here. Nothing outside this pair of files has any
//  business with any of them.
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

    /// **As few rows as will hold them, then as evenly as they divide.**
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

    private var rowCount: Int { Self.shape(for: slotCount).rows }

    private var columns: Int { Self.shape(for: slotCount).columns }

    override var intrinsicContentSize: NSSize {
        let margin = Tokens.Metric.essentialsVerticalInset
        guard rowCount > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let height = CGFloat(rowCount) * Tokens.Metric.essentialsTile.height
            + CGFloat(rowCount - 1) * Tokens.Metric.essentialsRowGap + 2 * margin
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    /// One slot's frame, in reading order. The single piece of grid arithmetic:
    /// the tiles, the drop outline and the drag lift all place themselves with
    /// it, so they cannot disagree about where a slot is.
    func slotRect(at index: Int) -> NSRect {
        let inset = Tokens.Metric.essentialsInset
        let margin = Tokens.Metric.essentialsVerticalInset
        let gutter = Tokens.Metric.essentialsTileGap
        let rowGap = Tokens.Metric.essentialsRowGap
        let height = Tokens.Metric.essentialsTile.height
        let across = columns
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

    /// Which slot the pointer is over, in reading order — and **the index the
    /// tab would land at**, which is why it counts the settled tiles rather
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
