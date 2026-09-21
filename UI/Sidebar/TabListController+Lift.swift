//
//  TabListController+Lift.swift
//  Luna
//
//  The list's half of §6.6's drag: where a lift starts, where it would land,
//  and the gap that follows it down the column. The gesture itself is in
//  `SidebarTabDrag.swift`; this file is only the geometry and the row-view
//  offsets it asks for.
//

import AppKit
import BrowserKit

extension TabListController {

    // MARK: - §6.6's lift

    /// The pill a row draws, in `space`'s coordinates — where the lift starts.
    func pillRect(ofRow row: Int, in space: NSView) -> NSRect {
        let rect = table.rect(ofRow: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        return space.convert(rect, from: table)
    }

    /// The insertion index a lift centred at `centreY` would drop into. Rows
    /// are split at their midpoint, and nothing may land in the leading command
    /// group (§6.6 reorders, it does not nest).
    func insertionRow(atY centreY: CGFloat, in space: NSView) -> Int {
        let point = table.convert(NSPoint(x: table.bounds.midX, y: centreY), from: space)
        let row = table.row(at: point)
        guard row >= 0 else {
            // Above the first row or below the last: the two ends of the list.
            return point.y < 0 ? SidebarList.leading.count : table.numberOfRows
        }
        let rect = table.rect(ofRow: row)
        return SidebarList.insertionRow(forRow: row, isBelowMidpoint: point.y > rect.midY)
    }

    /// A tab's index within its own section, which is what `reorderTab` counts.
    func sectionIndex(of id: UUID) -> Int? {
        guard let index = list.listed.firstIndex(where: { $0.id == id }) else { return nil }
        let kind = list.listed[index].kind
        return list.listed[..<index].filter { $0.kind == kind }.count
    }

    func beginDrag(atRow row: Int) {
        isDragging = true
        draggedRow = row
        gapRow = row
        setPillsHidden(true)
        table.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = 0
        applyGap(animated: false)
    }

    /// The same lift, arriving from the §3.3 grid rather than from this list.
    ///
    /// There is no row to take out, only one to make room for. An
    /// Essentials tab is not in `SidebarList` at all, so the list had no
    /// `draggedRow` to measure a gap from and `applyGap` returned without
    /// moving anything: a tile carried down over the tabs floated over a list
    /// that never reacted. The gap for an incoming lift is the simpler of the
    /// two — everything from the landing row down moves one row out of the way
    /// — and the pills are parked either way, because the lift is carrying
    /// §3.4's pill itself.
    func beginIncomingDrag() {
        isDragging = true
        draggedRow = nil
        gapRow = nil
        setPillsHidden(true)
    }

    /// Opens the gap at `row`, or closes it entirely when the lift has left the
    /// list for the grid.
    func setGap(row: Int?) {
        guard row != gapRow else { return }
        gapRow = row
        applyGap(animated: true)
    }

    /// Puts the gap back after the table has re-placed its own row views —
    /// see `SidebarTableView.onLayout`. A no-op when no lift is up, which is
    /// every layout pass but the handful during a drag.
    func restoreGap() {
        guard isDragging else { return }
        applyGap(animated: false)
        guard let dragged = draggedRow else { return }
        table.rowView(atRow: dragged, makeIfNecessary: false)?.alphaValue = 0
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        draggedRow = nil
        gapRow = nil
        // Every row, by frame and by alpha. `applyGap` is no use here: it
        // needs the lift to still be up, and it has just been taken down.
        // The rows are wherever the gap left them, and the one the lift stood
        // in for is still invisible — both are put back from the table's own
        // arithmetic, which is what they should have been all along.
        for row in 0 ..< table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: false) else { continue }
            view.frame = table.rect(ofRow: row)
            view.alphaValue = 1
        }
        movePills()
    }

    /// Slides the rows between the tab's old slot and its new one by exactly one
    /// row, which is the gap. The row views are moved, not the model: a
    /// reorder committed per row crossed would be a SQLite write and an undo
    /// entry each time, and the whole arrangement is thrown away and rebuilt by
    /// the reload that follows the drop.
    private func applyGap(animated: Bool) {
        guard isDragging else { return }
        let dragged = draggedRow
        let target = gapRow ?? table.numberOfRows
        let height = Tokens.Metric.rowHeight
        let body = { [self] in
            for row in 0 ..< table.numberOfRows where row != dragged {
                guard let view = table.rowView(atRow: row, makeIfNecessary: false) else { continue }
                // The table is flipped, so "up one row" is a negative offset.
                // With no `dragged` row there is nothing to close up behind,
                // so the gap is one-sided: the landing row and everything
                // under it step down, and a nil `gapRow` puts them all back.
                let shift: CGFloat = if let dragged {
                    if row > dragged, row < target {
                        -height
                    } else if row >= target, row < dragged {
                        height
                    } else {
                        0
                    }
                } else {
                    row >= target ? height : 0
                }
                var frame = table.rect(ofRow: row)
                frame.origin.y += shift
                if animated { view.animator().frame = frame } else { view.frame = frame }
            }
        }
        guard animated, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately { body() }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            body()
        }
    }
}
