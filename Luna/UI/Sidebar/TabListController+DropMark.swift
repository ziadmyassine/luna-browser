//
//  TabListController+DropMark.swift
//  Luna
//
//  §6.6's mark for a file or a link dragged over the window: the list opens
//  a gap where it will open, as it does for a lifted tab, and draws the
//  dashed box Luna draws wherever a thing is about to go. Over the rows the
//  gap follows the pointer and the page lands there; anywhere else it stands
//  at the head of today's tabs, where a new tab opens anyway (§3.4).
//

import AppKit
import BrowserKit

extension TabListController {

    /// Shows where pages dropped now would open, and answers it.
    /// - Parameter y: the pointer, in `space`'s coordinates, while it is over
    ///   the rows; nil anywhere else.
    /// - Returns: the landing, or nil for the head of today's tabs — where a
    ///   new tab opens without being told.
    @discardableResult
    func markDrop(atY y: CGFloat?, in space: NSView) -> SidebarDestination? {
        // A lift is up, and the gap is the lift's.
        guard !isDragging || isMarkingDrop else { return nil }
        // Not `y.map { landing(atY:) }`: Xcode 26 reads the name as the
        // variable being declared and fails to type the closure.
        var landing: (row: Int, destination: SidebarDestination)?
        if let y { landing = self.landing(atY: y, in: space) }
        // §5.6 keeps nothing, so the saved tier is no landing in a private window.
        if !allowsPinning, landing?.destination.kind != .today { landing = nil }
        let row = landing?.row ?? openingGapRow()
        let folder = landing?.destination.groupID
        // AppKit asks again every few milliseconds with the pointer still; the
        // box is only re-placed when the answer changes, or its fade would be
        // started over on every one.
        let moved = !isMarkingDrop || row != gapRow || folder != groupDropID
        if !isMarkingDrop {
            isMarkingDrop = true
            beginIncomingDrag()
        }
        setGap(row: row)
        setGroupDrop(inside: folder)
        if moved { dropMark.show(gapPillRect(forGapRow: row, inside: folder, in: table)) }
        return landing?.destination
    }

    /// Takes the mark and its gap away.
    func clearDropMark() {
        guard isMarkingDrop else { return }
        isMarkingDrop = false
        dropMark.show(nil)
        endDrag()
    }

    /// The gap at the head of today's tabs.
    private func openingGapRow() -> Int {
        let head = SidebarDestination(kind: .today, groupID: nil, index: 0)
        for row in 0 ..< list.rows.count {
            for below in [false, true] where list.destination(forRow: row, isBelowMidpoint: below) == head {
                return list.gapRow(forRow: row, isBelowMidpoint: below)
            }
        }
        return list.rows.count
    }
}
