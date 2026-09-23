//
//  TopBarTabDrag.swift
//  Luna
//
//  §6.6's reorder on §4's bar: pick a tab or a folder up, carry it along the
//  run, put it down somewhere else.
//
//  The column's gesture turned on its side. `SidebarTabDrag` tracks the press
//  itself rather than handing it to AppKit's drag session, because a session's
//  snapshot floats free in two dimensions and the list stays still under it;
//  the same is true here with the axes swapped. The lift is locked to the bar's
//  line and follows the pointer's `x`, and the run opens a gap under it the
//  moment it starts moving.
//
//  Three things can be done to a tab by carrying it, and they are the three the
//  column offers:
//
//    · Along the run — a reorder inside its own tier.
//    · Into a folder, or out of one — past a folder's header is inside it, the
//      column's rule, and the folder's plate lights up to say so.
//    · Across the hairline — into the kept run is keeping it, out of it is not.
//      Among §3.3's circles it becomes one of them; beside §3.4b's kept tabs it
//      joins those. The kept run is one cylinder on the bar and two tiers
//      underneath, and the rule that tells them apart is the one a hand can
//      see: a tab becomes the same kind of thing as what it lands beside.
//
//  And a fourth the bar has instead of the column's dots: held over one of the
//  Space cylinder's arrows, a tab goes to the Space next door.
//
//  Nothing is committed until the mouse comes up — one `reorderTab` for the
//  gesture, one undo entry, not one per chip crossed.
//

import AppKit
import BrowserKit

@MainActor
final class TopBarTabDragController {

    /// A tab dropped in the run: `reorderTab`'s three arguments, already
    /// counted with the tab taken out of the run.
    var onDropTab: ((_ id: UUID, _ landing: SidebarDestination) -> Void)?
    /// A §3.4b folder dropped in the run: a slot in one of the two tiers.
    var onDropGroup: ((_ id: UUID, _ kind: TabKind, _ index: Int) -> Void)?
    /// A tab dropped on one of the Space cylinder's arrows.
    var onDropOnSpace: ((_ id: UUID, _ space: UUID) -> Void)?
    /// False in a §5.6 private window, where nothing can be kept, so the kept
    /// run is not a landing place at all — see `BrowserSession.allowsPinning`.
    var allowsPinning = true

    private enum Target: Equatable {
        case run(DropGap)
        case space(UUID)
    }

    private unowned let host: NSView
    private unowned let strip: TopBarTabStrip
    private unowned let spaces: TopBarSpacePill
    private var lift: TopBarDragLift?
    private var target: Target?
    /// Which gesture this is, for `SidebarTabDragController.gesture`'s reason:
    /// the lift settles for a third of a second after the mouse comes up, and a
    /// quick second drag must not have its run torn down by the first's.
    private var gesture = 0

    init(host: NSView, strip: TopBarTabStrip, spaces: TopBarSpacePill) {
        self.host = host
        self.strip = strip
        self.spaces = spaces
    }

    /// Runs the whole gesture, from the press the chip handed over to the
    /// mouse-up that ends it. Escape cancels, which is the one thing every
    /// drag on macOS can do.
    func track(_ lifted: TopBarLifted, from chip: TopBarButton, event press: NSEvent) {
        guard let window = host.window else { return }
        let origin = host.convert(chip.bounds, from: chip)
        let start = host.convert(press.locationInWindow, from: nil)
        let grab = start.x - origin.minX
        begin(lifted, from: chip, at: origin)
        move(lifted, to: start.x - grab, pointer: start)

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
                move(lifted, to: point.x - grab, pointer: point)
            }
        }
        finish(lifted, cancelled: cancelled)
    }

    // MARK: - The gesture

    private func begin(_ lifted: TopBarLifted, from chip: TopBarButton, at origin: NSRect) {
        gesture += 1
        let view = TopBarDragLift(
            icon: chip.icon,
            title: chip.titleText ?? chip.accessibilityLabel() ?? ""
        )
        view.style = chip.titleText == nil ? .icon : .chip
        view.frame = origin
        host.addSubview(view, positioned: .above, relativeTo: nil)
        lift = view
        // Out of the run for the length of the gesture: its place closes up
        // behind it, so the index under the pointer is the index it lands at.
        strip.liftedID = lifted.id
        strip.revealsKept = allowsPinning
        target = nil
        view.lift()
    }

    /// The lift's leading edge follows the hand; its `y` never does. The bar is
    /// one line, and the only vertical movement the lift ever makes is the one
    /// it made leaving the surface.
    private func move(_ lifted: TopBarLifted, to minX: CGFloat, pointer: NSPoint) {
        guard let lift else { return }
        let next = resolve(lifted, at: pointer)
        let style = style(of: next, carrying: lifted)
        let width = lift.width(as: style)
        let resolved = next.map { target in
            guard case var .run(gap) = target else { return target }
            gap.width = width
            return .run(gap)
        }
        if resolved != target {
            // One tick per step, as the column does — and not for the first
            // target, which is the lift leaving the ground rather than passing
            // anything.
            if target != nil { Tokens.Haptics.step() }
            let morphed = target.map { self.style(of: $0, carrying: lifted) != style } ?? false
            target = resolved
            apply(resolved)
            lift.apply(frame: frame(minX: minX, width: width), style: style, animated: morphed)
        } else {
            lift.apply(frame: frame(minX: minX, width: width), style: style, animated: false)
        }
    }

    private func frame(minX: CGFloat, width: CGFloat) -> NSRect {
        let height = TopBarMetrics.chip.height
        let line = strip.convert(NSPoint(x: 0, y: strip.bounds.height / 2 - TopBarMetrics.lightsCentreOffset), to: host)
        return NSRect(x: minX, y: (line.y - height / 2).rounded(), width: width, height: height)
    }

    /// The shape the lift wears over a target: whatever the tier it would
    /// land in draws. A folder is always its header.
    private func style(of target: Target?, carrying lifted: TopBarLifted) -> TopBarTabStyle {
        guard case .tab = lifted, case let .run(gap)? = target else { return lift?.style ?? .chip }
        return gap.destination.kind == .today ? .chip : .icon
    }

    private func resolve(_ lifted: TopBarLifted, at point: NSPoint) -> Target? {
        if case .tab = lifted, let space = spaces.neighbourSpace(at: point, from: host) {
            return .space(space)
        }
        let local = strip.content.convert(point, from: host)
        let run = strip.run
        // The empty cylinder a drag reveals, before anything is kept.
        let vacancy = strip.cylinder.frame.insetBy(dx: -TopBarMetrics.gap, dy: -host.bounds.height)
        if run.kept == 0, strip.revealsKept, vacancy.contains(local) {
            // A tab carried there becomes one of §3.3's circles; a folder, which
            // cannot be a tile, starts §3.4b's kept tier instead.
            var kind = TabKind.pinned
            if case .tab = lifted { kind = .essential }
            return .run(DropGap(block: 0, width: 0, destination: SidebarDestination(kind: kind, groupID: nil, index: 0)))
        }
        let (block, past) = block(at: local.x)
        switch lifted {
        case .tab:
            var destination = run.destination(forBlock: block, isPastMidpoint: past)
            if !allowsPinning, destination.kind != .today {
                destination = SidebarDestination(kind: .today, groupID: nil, index: 0)
            }
            return .run(DropGap(block: run.gap(forBlock: block, isPastMidpoint: past), width: 0, destination: destination))
        case .group:
            var destination = run.folderDestination(forBlock: block, isPastMidpoint: past)
            // §3.3's grid is one tile per tab: a folder carried among the
            // circles lands at the head of the kept tier instead.
            if destination.kind == .essential { destination = SidebarDestination(kind: .pinned, groupID: nil, index: 0) }
            if !allowsPinning, destination.kind != .today {
                destination = SidebarDestination(kind: .today, groupID: nil, index: 0)
            }
            let owner = run.blocks.indices.contains(block) ? run.owner(of: block) : block
            let edge: Int
            if run.blocks.indices.contains(owner), case .group = run.blocks[owner] {
                edge = past ? run.lastBlock(ofFolderAt: owner) + 1 : owner
            } else {
                edge = run.gap(forBlock: owner, isPastMidpoint: past)
            }
            return .run(DropGap(block: edge, width: 0, destination: destination))
        }
    }

    /// The block under `x`, and which half of it. Past the last block is the
    /// end of the run; before the first is the first block's leading half.
    private func block(at x: CGFloat) -> (Int, Bool) {
        for (index, frame) in strip.blockFrames.enumerated() where x < frame.maxX + TopBarMetrics.gap / 2 {
            return (index, x > frame.midX)
        }
        return (strip.run.blocks.count, false)
    }

    private func apply(_ target: Target?) {
        switch target {
        case let .run(gap):
            strip.dropGap = gap
            strip.dropFolder = gap.destination.groupID
            spaces.dropTarget = nil
        case let .space(id):
            strip.dropGap = nil
            strip.dropFolder = nil
            spaces.dropTarget = id
        case nil:
            strip.dropGap = nil
            strip.dropFolder = nil
            spaces.dropTarget = nil
        }
    }

    private func finish(_ lifted: TopBarLifted, cancelled: Bool) {
        let landing = cancelled ? nil : target
        let lift = lift
        self.lift = nil
        target = nil
        spaces.dropTarget = nil

        // Commit, then reveal — the column's order, for the column's reason:
        // the chip the lift stands in for is out of the run until the model has
        // moved it, so it is never seen back where it came from.
        let mine = gesture
        let landed: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            commit(lifted, landing: landing)
            guard mine == gesture else { return }
            strip.dropGap = nil
            strip.dropFolder = nil
            strip.revealsKept = false
            strip.liftedID = nil
        }
        guard let lift, case .run? = landing, let rest = strip.gapFrame else {
            landed()
            lift?.drop()
            return
        }
        let line = frame(minX: 0, width: 0)
        let settled = host.convert(rest, from: strip.content)
        lift.settle(
            into: NSRect(x: settled.minX, y: line.minY, width: settled.width, height: TopBarMetrics.chip.height),
            then: landed
        )
    }

    private func commit(_ lifted: TopBarLifted, landing: Target?) {
        switch (lifted, landing) {
        case let (.tab(id), .run(gap)?):
            onDropTab?(id, gap.destination)
        case let (.group(id), .run(gap)?):
            onDropGroup?(id, gap.destination.kind, gap.destination.index)
        case let (.tab(id), .space(space)?):
            onDropOnSpace?(id, space)
        case (.group, .space?), (_, nil):
            break
        }
    }
}
