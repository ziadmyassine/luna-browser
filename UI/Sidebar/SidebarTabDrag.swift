//
//  SidebarTabDrag.swift
//  Luna
//
//  §6.6's reorder, as a gesture rather than as a system drag.
//
//  Why this is not `NSTableView`'s drag and drop. AppKit's session hands
//  the pointer a translucent snapshot that floats free in two dimensions, can
//  be carried out of the window entirely, and leaves the list behind it static
//  apart from a 2 pt insertion rule. A sidebar tab has exactly one degree of
//  freedom — it is somewhere in a column — and Martin's ask is the column's:
//  *lock it horizontally, move the whole row including its highlight, and show
//  its landing place the moment it starts moving.* None of those three are
//  things a dragging session exposes.
//
//  So the gesture is tracked here. The row is replaced by a lift — one view
//  carrying §3.4's selected pill, the favicon and the title — which is pinned to
//  the sidebar's own x and follows the pointer's y, while the list opens a gap
//  under it. Carry it up into the §3.3 grid and the lift becomes a tile:
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
enum SidebarDropTarget: Equatable, Sendable {
    /// An insertion index in §3.4's row space.
    case list(row: Int)
    /// A slot in §3.3's grid, in reading order.
    case essentials(index: Int)
    /// A Space dot in the §3.5 bar: the tab leaves this Space for that one.
    case space(id: UUID)
}

@MainActor
final class SidebarTabDragController {

    /// Dropped in the list: the §6.6 reorder, committed once. `wasPinned` says
    /// the tab came down out of the grid, which is the half of §3.3's boundary
    /// the list sees — the other half is `onDropInEssentials`.
    var onDropInList: ((_ id: UUID, _ kind: TabKind, _ index: Int, _ wasPinned: Bool) -> Void)?
    /// Dropped in the grid, at that slot. `wasPinned` separates the two things
    /// that look identical from here: moving a tile between slots, and pinning
    /// a row that was not a tile a moment ago.
    var onDropInEssentials: ((_ id: UUID, _ index: Int, _ wasPinned: Bool) -> Void)?
    /// Dropped on a §3.5 Space dot.
    var onDropOnSpace: ((UUID, UUID) -> Void)?

    private unowned let host: NSView
    private unowned let grid: EssentialsGridView
    private unowned let list: TabListController
    private unowned let utility: SidebarUtilityBar

    private var lift: SidebarDragLiftView?
    private var target: SidebarDropTarget?
    /// Where the lift came from. A tile that started in the grid is taken out
    /// of it for the length of the gesture, and put back by the drop.
    private var isPinned = false

    init(host: NSView, grid: EssentialsGridView, list: TabListController, utility: SidebarUtilityBar) {
        self.host = host
        self.grid = grid
        self.list = list
        self.utility = utility
    }

    /// Runs the whole gesture, from the press that started it to the mouse-up
    /// that ends it. Returns immediately for anything that is not a tab row.
    ///
    /// The loop is AppKit's own idiom for a tracked drag: pull the events we
    /// care about out of the queue rather than letting them go through the
    /// responder chain. Escape cancels, which is the one thing every drag on
    /// macOS can do and the one thing a hand-rolled one usually cannot.
    func track(row: Int, event: NSEvent) {
        guard case let .tab(id)? = list.list[row], let tab = list.list.tab(at: row) else { return }
        track(id: id, kind: tab.kind, content: list.content(for: row), origin: list.pillRect(ofRow: row, in: host), event: event)
    }

    /// The same gesture, started on a §3.3 tile. It lifts as a tile, can be
    /// moved between the grid's slots, and becomes a row on the way down —
    /// which is the whole point of there being one gesture rather than two.
    func track(essential id: UUID, from tile: NSView, event: NSEvent) {
        guard let content = grid.content(for: id) else { return }
        track(
            id: id,
            kind: .essential,
            content: content,
            origin: host.convert(tile.bounds, from: tile),
            event: event
        )
    }

    private func track(id: UUID, kind: TabKind, content: SidebarRowContent, origin: NSRect, event: NSEvent) {
        guard let window = host.window else { return }
        isPinned = kind == .essential
        let start = host.convert(event.locationInWindow, from: nil)
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
                    guard abs(point.y - start.y) >= Tokens.Metric.dragThreshold
                        || abs(point.x - start.x) >= Tokens.Metric.dragThreshold
                    else { continue }
                    lifted = true
                    grabOffset = start.y - origin.midY
                    begin(id: id, content: content, from: origin)
                }
                move(to: NSPoint(x: point.x, y: point.y - grabOffset))
            }
        }

        guard lifted else { return }
        finish(id: id, kind: kind, cancelled: cancelled)
    }

    // MARK: - The gesture

    private func begin(id: UUID, content: SidebarRowContent, from origin: NSRect) {
        let view = SidebarDragLiftView(content: content)
        view.frame = origin
        view.shape = isPinned ? .tile : .row
        host.addSubview(view, positioned: .above, relativeTo: nil)
        lift = view
        // The grid is zero points tall until something is pinned, so it has to
        // be opened before the lift can be carried into it.
        grid.isAwaitingDrop = true
        if isPinned {
            // Out of the grid for the length of the gesture: its slot closes up
            // behind it, so the index under the pointer is the index it lands at.
            grid.draggedID = id
            // And the list is told a lift is up even though none of its rows
            // is the one being carried — otherwise a tile brought down over
            // the tabs floats above a list that never opens for it.
            list.beginIncomingDrag()
        } else if let row = list.list.row(of: id) {
            list.beginDrag(atRow: row)
        }
        target = nil
        view.lift()
    }

    /// The lift's centre, in the sidebar's coordinates. `x` is never taken from
    /// the pointer: the column is the gesture, and the only horizontal
    /// movement the lift ever makes is the morph between a row's width and a
    /// tile's.
    private func move(to point: NSPoint) {
        guard let lift else { return }
        let next = resolveTarget(at: point)
        let morphed = target.map { shape(of: next) != shape(of: $0) } ?? false
        if next != target {
            // One tick per step, in the grid and in the list alike. The
            // pointer moves continuously and the list does not — it steps, as
            // the lift changes places with one neighbour — and this is the only
            // line that knows a step just happened. The very first target of a
            // gesture is not one: nothing has been passed yet, the lift has
            // only just left the ground.
            if target != nil { Tokens.Haptics.step() }
            target = next
            apply(next)
        }
        lift.apply(frame: frame(for: next, at: point), shape: shape(of: next), animated: morphed)
    }

    /// Three regions, read from the foot of the sidebar up: a Space dot, the
    /// list, the grid. The grid is held open to a tile's height for the whole
    /// gesture, so there is a boundary to cross even with nothing pinned yet.
    private func resolveTarget(at point: NSPoint) -> SidebarDropTarget {
        if let space = utility.spaceID(at: point, from: host) { return .space(id: space) }
        guard point.y < grid.frame.minY else {
            // The one place the lift moves sideways. Two columns of tiles
            // are two positions, and which of them the lift is over is a
            // question only the pointer's `x` can answer; everywhere else the
            // column is the whole gesture.
            return .essentials(index: grid.insertionIndex(at: grid.convert(point, from: host)))
        }
        return .list(row: list.insertionRow(atY: point.y, in: host))
    }

    /// Where the lift sits for a target: a row's pill, or a tile under the hand.
    /// Both keep the pointer's `y`, so the lift never leaves it.
    ///
    /// A tile is not snapped to its slot while it is in the air. Jumping
    /// between two positions as the pointer crosses the gutter reads as the
    /// tile being taken off you and put somewhere; the grid's own outline is
    /// already saying where it will land, so the tile itself can simply go
    /// where the hand goes, bounded by the area it belongs to. Letting go is
    /// what puts it in the slot — see `SidebarDragLiftView.settle`.
    private func frame(for target: SidebarDropTarget, at point: NSPoint) -> NSRect {
        switch target {
        case let .essentials(index):
            let slot = host.convert(grid.slotRect(at: index), from: grid)
            let area = host.convert(grid.bounds, from: grid).insetBy(dx: Tokens.Metric.essentialsInset, dy: 0)
            let free = point.x - slot.width / 2
            return NSRect(
                x: min(max(free, area.minX), max(area.maxX - slot.width, area.minX)),
                y: point.y - slot.height / 2,
                width: slot.width,
                height: slot.height
            )
        case .list, .space:
            let inset = Tokens.Metric.rowInset
            let height = Tokens.Metric.rowPillHeight
            return NSRect(
                x: host.bounds.minX + inset,
                y: point.y - height / 2,
                width: max(host.bounds.width - 2 * inset, 0),
                height: height
            )
        }
    }

    private func apply(_ target: SidebarDropTarget) {
        grid.dropIndex = nil
        utility.highlightedSpaceID = nil
        switch target {
        case let .list(row):
            list.setGap(row: row)
        case let .essentials(index):
            grid.dropIndex = index
            // Out of the list entirely: its gap closes up behind it.
            list.setGap(row: nil)
        case let .space(id):
            utility.highlightedSpaceID = id
            list.setGap(row: nil)
        }
    }

    private func shape(of target: SidebarDropTarget) -> SidebarDragLiftView.Shape {
        switch target {
        case .essentials: .tile
        case .list, .space: .row
        }
    }

    private func finish(id: UUID, kind: TabKind, cancelled: Bool) {
        let landing = cancelled ? nil : target
        let lift = lift
        self.lift = nil
        utility.highlightedSpaceID = nil
        target = nil
        isPinned = false

        // The move is committed before anything is revealed.
        //
        // The row and the tile the lift is standing in for are hidden, not
        // gone, and they are hidden at the place the tab came from. Putting
        // them back before the model has moved therefore shows the tab in the
        // place it just left — for one frame in the grid, where it read as the
        // tile darting off and then sliding back, and for the whole length of
        // the settle when a row was carried up into the grid. Commit, then
        // reveal: the tile is un-hidden where it now belongs, and there is
        // nothing to slide.
        let landed: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            switch landing {
            case let .list(row):
                var destination = list.list.dropTarget(insertingAt: row)
                // `reorderTab` takes the index the tab ends up at, so a move
                // down within its own section has to account for its own
                // removal.
                if kind == destination.kind, let from = list.sectionIndex(of: id), from < destination.index {
                    destination.index -= 1
                }
                onDropInList?(id, destination.kind, destination.index, kind == .essential)
            case let .essentials(index):
                // The grid laid its slots out with the dragged tile taken out
                // of them, so that index is already the one the tab lands at.
                onDropInEssentials?(id, index, kind == .essential)
            case let .space(space):
                onDropOnSpace?(id, space)
            case nil:
                break
            }
            clearGrid()
            list.endDrag()
        }

        // A tile landing in the grid keeps its slot open until it is standing
        // in it; everything else is done with the grid the moment it is let go.
        guard case let .essentials(index)? = landing, let lift else {
            landed()
            lift?.drop()
            return
        }
        lift.settle(into: host.convert(grid.slotRect(at: index), from: grid), then: landed)
    }

    /// Puts the grid back to its resting shape: no slot held open, no tile in
    /// the air, no room reserved for one.
    private func clearGrid() {
        grid.dropIndex = nil
        grid.draggedID = nil
        grid.isAwaitingDrop = false
    }
}
