//
//  SidebarTabDrag.swift
//  Luna
//
//  §6.6's reorder, as a gesture rather than as a system drag. `NSTableView`'s
//  drag session hands the pointer a snapshot that floats free in two
//  dimensions, can leave the window, and leaves the list static but for a 2 pt
//  rule; a sidebar tab has to be locked horizontally, carry its highlight, and
//  show its landing place the moment it moves.
//
//  The row is replaced by a lift — §3.4's selected pill, favicon and title —
//  pinned to the sidebar's x and following the pointer's y, while the list opens
//  a gap under it. Carried into the §3.3 grid it becomes a tile. A §3.4b group
//  travels as its header, folded for the length of the gesture so it cannot be
//  dropped among its own tabs; several marked tabs travel as the one pressed,
//  with the others out of the list and their count on the lift. The saved
//  tier's rule comes out for every drag.
//
//  Nothing is committed until the mouse comes up: a live `reorderTab` per row
//  crossed would be a dozen SQLite writes and undo entries for one gesture.
//
//  Pulled clear of the column, a tab leaves the list after all — as AppKit's
//  drag, from that point on, to another window or app (`TabTearOff`).
//

import AppKit
import BrowserKit

/// Where a lift would land if it were dropped now.
enum SidebarDropTarget: Equatable, Sendable {
    /// A place in §3.4's list: the row its gap opens at, and the run and index a
    /// drop there means (§3.4b — a tier, a group or nil for loose, an index).
    case list(row: Int, destination: SidebarDestination)
    /// A slot in §3.3's grid, in reading order.
    case essentials(index: Int)
    /// A Space dot in the §3.5 bar: the tab leaves this Space for that one.
    case space(id: UUID)
}

/// What the lift is carrying.
private enum SidebarCargo: Equatable {
    case tab(id: UUID, kind: TabKind)
    case group(TabGroup)
    /// Marked tabs (`TabListController+Marking.swift`), in row order, carried
    /// as `lead`, the one pressed.
    case tabs(lead: UUID, all: [UUID])

    var id: UUID {
        switch self {
        case let .tab(id, _): id
        case let .group(group): group.id
        case let .tabs(lead, _): lead
        }
    }

    /// What leaves the list for the gesture besides the lifted row.
    var carried: Set<UUID> {
        switch self {
        case .tab: []
        case let .group(group): [group.id]
        case let .tabs(lead, all): Set(all).subtracting([lead])
        }
    }

    var isTile: Bool {
        guard case let .tab(_, kind) = self else { return false }
        return kind == .essential
    }

    /// §3.3's grid is one tile per tab, so a group has nowhere to land there,
    /// and §3.5's dots move a tab between Spaces, which a group does not do —
    /// its name stays with the rest of its tabs. Both regions are simply not
    /// offered while a group is in the air: a target that lights up and then
    /// refuses the drop is worse than one that never lights up.
    var mayLeaveTheList: Bool {
        guard case .group = self else { return true }
        return false
    }
}

@MainActor
final class SidebarTabDragController {

    /// Dropped in the list: the §6.6 reorder, committed once. `wasPinned` says
    /// the tab came down out of the grid, which is the half of §3.3's boundary
    /// the list sees — the other half is `onDropInEssentials`.
    var onDropInList: ((_ id: UUID, _ landing: SidebarDestination, _ wasPinned: Bool) -> Void)?
    /// A §3.4b group dropped in the list: a slot in one of the two tiers.
    var onDropGroup: ((_ id: UUID, _ kind: TabKind, _ index: Int) -> Void)?
    /// Dropped in the grid, at that slot. `wasPinned` separates the two things
    /// that look identical from here: moving a tile between slots, and pinning
    /// a row that was not a tile a moment ago.
    var onDropInEssentials: ((_ id: UUID, _ index: Int, _ wasPinned: Bool) -> Void)?
    /// Dropped on a §3.5 Space dot.
    var onDropOnSpace: ((UUID, UUID) -> Void)?
    /// Several marked tabs dropped, in row order, wherever they landed. A list
    /// landing's index counts the run without any of them.
    var onDropTabs: ((_ ids: [UUID], _ landing: SidebarDropTarget) -> Void)?
    /// A tab pulled clear of the column (`TabTearOff`): the lift is already
    /// down, and the tab leaves as AppKit's drag. Nil keeps every tab in the
    /// list, as a §5.6 window does — its session goes with its one window.
    var onTearOff: ((TabTearOff.Request) -> Void)?
    /// False in a §5.6 private window — see `BrowserSession.allowsPinning`.
    /// §3.3's grid is then not a landing place at all, which is the honest
    /// answer: a zone that lights up and refuses the drop is worse than one
    /// that never lights up.
    var allowsPinning = true

    private unowned let host: NSView
    private unowned let grid: EssentialsGridView
    private unowned let list: TabListController
    private unowned let utility: SidebarUtilityBar

    private var lift: SidebarDragLiftView?
    private var target: SidebarDropTarget?
    /// What is in the air, and where it came from. A tile that started in the
    /// grid is taken out of it for the length of the gesture, and put back by
    /// the drop.
    private var cargo: SidebarCargo?
    /// Which gesture this is. The lift travels to its landing place before it
    /// hands over, so its completion runs a third of a second after the mouse
    /// came up — long enough for a quick second drag to already be in the air,
    /// and the teardown that follows a drop would pull the list out from under
    /// it.
    private var gesture = 0

    init(host: NSView, grid: EssentialsGridView, list: TabListController, utility: SidebarUtilityBar) {
        self.host = host
        self.grid = grid
        self.list = list
        self.utility = utility
    }

    /// Runs the whole gesture, from the press that started it to the mouse-up
    /// that ends it. Returns immediately for anything that is not a tab or a
    /// §3.4b group header.
    ///
    /// The loop is AppKit's own idiom for a tracked drag: pull the events we
    /// care about out of the queue rather than letting them go through the
    /// responder chain. Escape cancels, which is the one thing every drag on
    /// macOS can do and the one thing a hand-rolled one usually cannot.
    ///
    /// - Returns: whether the press became a lift. False is a click, and the
    ///   caller is what knows what a click on that row means — a folder's
    ///   header both folds and moves, and the two are told apart by whether the
    ///   hand went anywhere.
    @discardableResult
    func track(row: Int, event: NSEvent) -> Bool {
        let origin = list.pillRect(ofRow: row, in: host)
        let content = list.content(for: row)
        if let group = list.list.group(at: row) {
            return track(cargo: .group(group), content: content, origin: origin, event: event)
        } else if let tab = list.list.tab(at: row) {
            let marked = list.markedInOrder
            let cargo: SidebarCargo = marked.count > 1 && marked.contains(tab.id)
                ? .tabs(lead: tab.id, all: marked) : .tab(id: tab.id, kind: tab.kind)
            return track(cargo: cargo, content: content, origin: origin, event: event)
        }
        return false
    }

    /// The same gesture, started on a §3.3 tile. It lifts as a tile, can be
    /// moved between the grid's slots, and becomes a row on the way down —
    /// which is the whole point of there being one gesture rather than two.
    func track(essential id: UUID, from tile: NSView, event: NSEvent) {
        guard let content = grid.content(for: id) else { return }
        _ = track(
            cargo: .tab(id: id, kind: .essential),
            content: content,
            origin: host.convert(tile.bounds, from: tile),
            event: event
        )
    }

    @discardableResult
    private func track(
        cargo: SidebarCargo,
        content: SidebarRowContent,
        origin: NSRect,
        event: NSEvent
    ) -> Bool {
        guard let window = host.window else { return false }
        self.cargo = cargo
        let start = host.convert(event.locationInWindow, from: nil)
        var grabOffset = start.y - origin.midY
        var lifted = false
        var cancelled = false
        var tornOff: NSEvent?

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
                    begin(cargo: cargo, content: content, from: origin)
                }
                if leavesTheList(cargo, at: next.locationInWindow, in: window) {
                    tornOff = next
                    break loop
                }
                move(to: NSPoint(x: point.x, y: point.y - grabOffset))
            }
        }

        guard lifted else {
            self.cargo = nil
            return false
        }
        // Read before `finish` takes the lift down.
        let grip = NSRect(origin: NSPoint(x: start.x - origin.minX, y: start.y - origin.minY), size: (lift?.frame ?? origin).size)
        finish(cargo: cargo, cancelled: cancelled || tornOff != nil)
        handOver(cargo, tornOff: tornOff, grip: grip, content: content, press: event)
        return true
    }

    // MARK: - The gesture

    private func begin(cargo: SidebarCargo, content: SidebarRowContent, from origin: NSRect) {
        gesture += 1
        let view = SidebarDragLiftView(content: content)
        if case let .tabs(_, all) = cargo { view.count = all.count }
        view.frame = origin
        view.shape = cargo.isTile ? .tile : .row
        host.addSubview(view, positioned: .above, relativeTo: nil)
        lift = view
        // The grid is zero points tall until something is pinned, so it has to
        // be opened before the lift can be carried into it. A group never goes
        // there, so it never asks for the room — and nor does anything in a
        // §5.6 window, which has no room to ask for: the grid stays shut, so
        // the dashed slot it would draw over an empty one never appears.
        grid.isAwaitingDrop = allowsPinning && cargo.mayLeaveTheList
        // The list is told a lift is up first, before anything re-lays it.
        // That is what parks §3.4's two row fills and keeps them parked: the
        // lift is carrying the selected pill itself, and every layout pass
        // between here and the drop would otherwise put a second one back in
        // the row the tab came from.
        list.beginIncomingDrag()
        // Then §3.4b's rule, and only then the row lookup: revealing the rule
        // inserts a row, so an index read a moment earlier would be one out.
        list.setRevealingSaved(true)
        list.setCarried(cargo.carried)
        if cargo.isTile {
            // Out of the grid for the length of the gesture: its slot closes up
            // behind it, so the index under the pointer is the index it lands at.
            grid.draggedID = cargo.id
        } else if let row = row(of: cargo) {
            list.beginDrag(atRow: row)
        }
        target = nil
        view.lift()
    }

    private func row(of cargo: SidebarCargo) -> Int? {
        switch cargo {
        case let .tab(id, _), let .tabs(id, _): list.list.row(of: id)
        case let .group(group): list.list.row(ofGroup: group.id)
        }
    }

    /// The lift's centre, in the sidebar's coordinates. `x` is never taken from
    /// the pointer: the column is the gesture, and the only horizontal
    /// movement the lift ever makes is the morph between a row's width and a
    /// tile's.
    private func move(to point: NSPoint) {
        guard let lift, let cargo else { return }
        let next = resolveTarget(at: point, carrying: cargo)
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
    /// gesture, so there is a boundary to cross even with nothing pinned yet —
    /// unless a §3.4b group is in the air, which belongs to the list alone.
    private func resolveTarget(at point: NSPoint, carrying cargo: SidebarCargo) -> SidebarDropTarget {
        if cargo.mayLeaveTheList {
            if let space = utility.spaceID(at: point, from: host) { return .space(id: space) }
            if allowsPinning, point.y >= grid.frame.minY {
                // The one place the lift moves sideways. Two columns of tiles
                // are two positions, and which of them the lift is over is a
                // question only the pointer's `x` can answer; everywhere else the
                // column is the whole gesture.
                return .essentials(index: grid.insertionIndex(at: grid.convert(point, from: host)))
            }
        }
        let landing = list.landing(atY: point.y, in: host)
        guard case .group = cargo else { return .list(row: landing.row, destination: landing.destination) }
        // A group holds tabs, not other groups, so one carried over a group
        // lands beside it rather than in it.
        return .list(row: landing.row, destination: list.list.topLevel(landing.destination))
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
        case let .list(_, destination):
            // A tab heading into a group carries the indent its row will have,
            // so the step in happens under the hand rather than on the drop.
            let indent = destination.groupID == nil ? 0 : Tokens.Metric.groupIndent
            let inset = Tokens.Metric.rowInset
            let height = Tokens.Metric.rowPillHeight
            return NSRect(
                x: host.bounds.minX + inset + indent,
                y: point.y - height / 2,
                width: max(host.bounds.width - 2 * inset - indent, 0),
                height: height
            )
        case .space:
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
        case let .list(row, destination):
            // One answer for a folder whether it is open or shut: a shut folder
            // opens on the drop, so the gap under its header is exactly where
            // the tab is about to be.
            list.setGap(row: row)
            list.setGroupDrop(inside: destination.groupID)
        case let .essentials(index):
            grid.dropIndex = index
            // Out of the list entirely: its gap closes up behind it.
            list.setGap(row: nil)
            list.setGroupDrop(inside: nil)
        case let .space(id):
            utility.highlightedSpaceID = id
            list.setGap(row: nil)
            list.setGroupDrop(inside: nil)
        }
    }

    private func shape(of target: SidebarDropTarget) -> SidebarDragLiftView.Shape {
        switch target {
        case .essentials: .tile
        case .list, .space: .row
        }
    }

    private func finish(cargo: SidebarCargo, cancelled: Bool) {
        let landing = cancelled ? nil : target
        let lift = lift
        self.lift = nil
        utility.highlightedSpaceID = nil
        target = nil
        self.cargo = nil

        // Commit, then reveal. The row and the tile the lift stands in for
        // are hidden at the place the tab came from, so putting them back
        // before the model moves shows the tab where it just left: a tile
        // darting off and sliding back, or a whole settle's worth when a row
        // was carried up into the grid.
        let mine = gesture
        let landed: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            commit(cargo: cargo, landing: landing)
            // The drop happened, whatever else has since. The teardown has not:
            // a second lift is already up and the list belongs to it now.
            guard mine == gesture else { return }
            clearGrid()
            list.setCarried([])
            list.setRevealingSaved(false)
            list.endDrag()
            if landing != nil, case .tabs = cargo { list.clearMarks() }
        }

        // Every landing the lift can reach is somewhere on screen, so it goes
        // there before it hands over. Faded out where the hand let go, a tab
        // dropped into a folder vanished in mid-air and the folder was simply
        // one row longer.
        guard let lift, let rest = restingPlace(for: landing) else {
            landed()
            lift?.drop()
            return
        }
        lift.settle(into: rest, then: landed)
    }

    /// Where the lift comes to rest before it hands the tab over — nil for a
    /// cancelled drag and for a Space dot, which is the one landing that is not
    /// a place in this sidebar.
    ///
    /// The gap the list has opened, in every landing the list takes, shut
    /// folder and open one alike. The box round the folder stays up underneath
    /// for the whole of it, because `landed` is what clears it and `landed`
    /// runs at the end.
    private func restingPlace(for landing: SidebarDropTarget?) -> NSRect? {
        switch landing {
        case let .essentials(index):
            return host.convert(grid.slotRect(at: index), from: grid)
        case let .list(row, destination):
            return list.gapPillRect(forGapRow: row, inside: destination.groupID, in: host)
        case .space, nil:
            return nil
        }
    }

    /// Puts the grid back to its resting shape: no slot held open, no tile in
    /// the air, no room reserved for one.
    private func clearGrid() {
        grid.dropIndex = nil
        grid.draggedID = nil
        grid.isAwaitingDrop = false
    }
}

// MARK: - Landing

extension SidebarTabDragController {

    /// The one session call a landing means. `reorderTab` takes the index the
    /// thing ends up at, so a move further down inside the run it is already in
    /// has to account for the gap its own removal leaves.
    private func commit(cargo: SidebarCargo, landing: SidebarDropTarget?) {
        switch (cargo, landing) {
        case let (.tab(id, kind), .list(_, destination)?):
            var landed = destination
            if let from = list.list.currentIndex(of: id, in: destination), from < landed.index {
                landed.index -= 1
            }
            onDropInList?(id, landed, kind == .essential)
        case let (.tab(id, kind), .essentials(index)?):
            // The grid laid its slots out with the dragged tile taken out
            // of them, so that index is already the one the tab lands at.
            onDropInEssentials?(id, index, kind == .essential)
        case let (.tab(id, _), .space(space)?):
            onDropOnSpace?(id, space)
        case let (.group(group), .list(_, destination)?):
            var index = destination.index
            if let from = list.list.currentSlotIndex(ofGroup: group.id, in: destination.kind), from < index {
                index -= 1
            }
            onDropGroup?(group.id, destination.kind, index)
        case let (.tabs(lead, all), .list(row, destination)?):
            var landed = destination
            if let from = list.list.currentIndex(of: lead, in: destination), from < landed.index {
                landed.index -= 1
            }
            onDropTabs?(all, .list(row: row, destination: landed))
        case let (.tabs(_, all), landing?):
            onDropTabs?(all, landing)
        case (.group, .essentials?), (.group, .space?), (_, nil):
            break
        }
    }
}

// MARK: - Leaving the list

extension SidebarTabDragController {

    /// Whether the hand has pulled a tab out of the column — sideways, or out
    /// of the window — far enough that it is no longer reordering it. A §3.4b
    /// folder never leaves: its name stays with the rest of its tabs.
    private func leavesTheList(_ cargo: SidebarCargo, at point: NSPoint, in window: NSWindow) -> Bool {
        guard onTearOff != nil, case .tab = cargo, let content = window.contentView else { return false }
        return TabTearOff.hasTornOff(
            pointer: point,
            run: host.convert(host.bounds, to: nil),
            along: .vertical,
            window: content.convert(content.bounds, to: nil)
        )
    }

    /// Gives a torn-off tab to `onTearOff`, standing under the hand.
    /// - Parameter grip: where the press was inside the lift (`origin`), and
    ///   the lift's size. The lift stayed in the column; the tab leaving it
    ///   goes with the pointer, held where it was held.
    private func handOver(_ cargo: SidebarCargo, tornOff: NSEvent?, grip: NSRect, content: SidebarRowContent, press: NSEvent) {
        guard let tornOff, case let .tab(id, _) = cargo else { return }
        let point = host.convert(tornOff.locationInWindow, from: nil)
        let held = NSRect(origin: NSPoint(x: point.x - grip.minX, y: point.y - grip.minY), size: grip.size)
        onTearOff?(TabTearOff.Request(
            tabID: id, content: content, view: host, frame: held, axis: .vertical, press: press.locationInWindow, event: tornOff
        ))
    }
}
