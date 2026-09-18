//
//  SidebarTabDrag.swift
//  Luna
//
//  §6.6's reorder, as a gesture rather than as a system drag.
//
//  **Why this is not `NSTableView`'s drag and drop.** AppKit's session hands
//  the pointer a translucent snapshot that floats free in two dimensions, can
//  be carried out of the window entirely, and leaves the list behind it static
//  apart from a 2 pt insertion rule. A sidebar tab has exactly one degree of
//  freedom — it is somewhere in a column — and Martin's ask is the column's:
//  *lock it horizontally, move the whole row including its highlight, and show
//  its landing place the moment it starts moving.* None of those three are
//  things a dragging session exposes.
//
//  So the gesture is tracked here. The row is replaced by a **lift** — one view
//  carrying §3.4's selected pill, the favicon and the title — which is pinned to
//  the sidebar's own x and follows the pointer's y, while the list opens a gap
//  under it. Carry it up into the §3.3 grid and the lift *becomes* a tile:
//  same view, new geometry, animated on §6's `tabInsert`, with the grid opening
//  a slot to receive it. Carry it back down and it becomes a row again.
//
//  Nothing is committed until the mouse comes up. A live `reorderTab` per row
//  crossed would be a dozen SQLite writes and a dozen undo entries for one
//  gesture; the gap is drawn by offsetting the row views, which costs nothing
//  and is discarded wholesale when the list reloads.
//

import AppKit
import BrowserKit

/// Where a lift would land if it were dropped now.
enum SidebarDropTarget: Equatable {
    /// An insertion index in §3.4's row space.
    case list(row: Int)
    /// A slot in §3.3's grid, in reading order.
    case essentials(index: Int)
}

@MainActor
final class SidebarTabDragController {

    /// Dropped in the list: the §6.6 reorder, committed once.
    var onDropInList: ((UUID, TabKind, Int) -> Void)?
    /// Dropped in the grid: pinned at that slot.
    var onDropInEssentials: ((UUID, Int) -> Void)?

    private unowned let host: NSView
    private unowned let grid: EssentialsGridView
    private unowned let list: TabListController

    private var lift: SidebarDragLiftView?
    private var target: SidebarDropTarget?

    init(host: NSView, grid: EssentialsGridView, list: TabListController) {
        self.host = host
        self.grid = grid
        self.list = list
    }

    /// Runs the whole gesture, from the press that started it to the mouse-up
    /// that ends it. Returns immediately for anything that is not a tab row.
    ///
    /// The loop is AppKit's own idiom for a tracked drag: pull the events we
    /// care about out of the queue rather than letting them go through the
    /// responder chain. Escape cancels, which is the one thing every drag on
    /// macOS can do and the one thing a hand-rolled one usually cannot.
    func track(row: Int, event: NSEvent) {
        guard case let .tab(id)? = list.list[row],
              let tab = list.list.tab(at: row),
              let window = host.window
        else { return }
        let content = list.content(for: row)
        let start = host.convert(event.locationInWindow, from: nil)
        let origin = list.pillRect(ofRow: row, in: host)
        var grabOffset = start.y - origin.midY
        var lifted = false
        var cancelled = false

        loop: while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            switch next.type {
            case .keyDown:
                guard next.keyCode == 53 else { continue }
                cancelled = true
                break loop
            case .leftMouseUp:
                break loop
            default:
                let point = host.convert(next.locationInWindow, from: nil)
                if !lifted {
                    guard abs(point.y - start.y) >= Tokens.Metric.dragThreshold else { continue }
                    lifted = true
                    grabOffset = start.y - origin.midY
                    begin(id: id, content: content, from: origin, row: row)
                }
                move(to: point.y - grabOffset)
            }
        }

        guard lifted else { return }
        finish(id: id, kind: tab.kind, cancelled: cancelled)
    }

    // MARK: - The gesture

    private func begin(id: UUID, content: SidebarRowContent, from origin: NSRect, row: Int) {
        let view = SidebarDragLiftView(content: content)
        view.frame = origin
        host.addSubview(view, positioned: .above, relativeTo: nil)
        lift = view
        // The grid is zero points tall until something is pinned, so it has to
        // be opened before the lift can be carried into it.
        grid.isAwaitingDrop = true
        list.beginDrag(atRow: row)
        target = .list(row: row)
        view.lift()
    }

    /// The lift's centre, in the sidebar's coordinates. `x` is never taken from
    /// the pointer: the column *is* the gesture, and the only horizontal
    /// movement the lift ever makes is the morph between a row's width and a
    /// tile's.
    private func move(to centreY: CGFloat) {
        guard let lift else { return }
        let next = resolveTarget(atY: centreY)
        let morphed = shape(of: next) != shape(of: target)
        if next != target {
            target = next
            apply(next)
        }
        lift.apply(frame: frame(for: next, centredAt: centreY), shape: shape(of: next), animated: morphed)
    }

    /// Anything at or above the grid's lower edge belongs to the grid; the rest
    /// is the list. The grid is open to a tile's height for the whole gesture,
    /// so there is always a boundary even with nothing pinned yet.
    private func resolveTarget(atY centreY: CGFloat) -> SidebarDropTarget {
        guard centreY < grid.frame.minY else {
            // The lift is locked to the column, so the slot it lands in is the
            // one under its own leading edge — always the leading column.
            let point = grid.convert(NSPoint(x: grid.bounds.minX + 1, y: centreY), from: host)
            return .essentials(index: grid.insertionIndex(at: point))
        }
        return .list(row: list.insertionRow(atY: centreY, in: host))
    }

    /// Where the lift sits for a target: a row's pill, or a tile in its slot.
    /// Both keep the pointer's `y`, so the lift never leaves the hand.
    private func frame(for target: SidebarDropTarget, centredAt centreY: CGFloat) -> NSRect {
        switch target {
        case .list:
            let inset = Tokens.Metric.rowInset
            let height = Tokens.Metric.rowPillHeight
            return NSRect(
                x: host.bounds.minX + inset,
                y: centreY - height / 2,
                width: max(host.bounds.width - 2 * inset, 0),
                height: height
            )
        case let .essentials(index):
            let slot = host.convert(grid.slotRect(at: index), from: grid)
            return NSRect(
                x: slot.minX,
                y: centreY - slot.height / 2,
                width: slot.width,
                height: slot.height
            )
        }
    }

    private func apply(_ target: SidebarDropTarget) {
        switch target {
        case let .list(row):
            grid.dropIndex = nil
            list.setGap(row: row)
        case let .essentials(index):
            grid.dropIndex = index
            // Out of the list entirely: the gap closes up behind it.
            list.setGap(row: nil)
        }
    }

    private func shape(of target: SidebarDropTarget?) -> SidebarDragLiftView.Shape {
        switch target {
        case .essentials: .tile
        case .list, nil: .row
        }
    }

    private func finish(id: UUID, kind: TabKind, cancelled: Bool) {
        let landing = cancelled ? nil : target
        grid.dropIndex = nil
        grid.isAwaitingDrop = false
        lift?.drop()
        lift = nil
        list.endDrag()
        target = nil
        guard let landing else { return }
        switch landing {
        case let .list(row):
            var destination = list.list.dropTarget(insertingAt: row)
            // `reorderTab` takes the index the tab ends up at, so a move *down*
            // within its own section has to account for its own removal.
            if kind == destination.kind, let from = list.sectionIndex(of: id), from < destination.index {
                destination.index -= 1
            }
            onDropInList?(id, destination.kind, destination.index)
        case let .essentials(index):
            onDropInEssentials?(id, index)
        }
    }
}
