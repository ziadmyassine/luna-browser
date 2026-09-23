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
//  The lift is the column's own — `SidebarDragLiftView`, carrying §3.4's
//  selected pill, the favicon and the title — and it morphs between a row and
//  §3.3's tile as it moves onto the plate, exactly as it does crossing the
//  column's grid boundary. Same view, same shadow, same settle.
//
//  Three things can be done to a tab by carrying it, and they are the three the
//  column offers:
//
//    · Along the run — a reorder inside its own tier.
//    · Into a folder, or out of one — past a folder's header is inside it, the
//      column's rule, and the column's box closes round the folder to say so.
//    · Onto the plate or off it — onto it is keeping it, off it is not. Among
//      §3.3's tiles it becomes one of them; inside a kept folder it joins
//      that. A lift brought to the plate opens two landings on it, the
//      column's two wells (§3.3a): an empty tile when nothing is pinned, and a
//      dashed row at the end of §3.4b's tier where a tab dropped starts a new
//      kept folder. Only brought to it: opened the moment a tab left the
//      ground, they pushed every tab after the plate a hundred points along,
//      out from under the hand that had just picked one of them up.
//
//  And a fourth, the column's dots: held over the Space's name, the dots come
//  out, and a tab held on one goes to that Space.
//
//  Nothing is committed until the mouse comes up — one `reorderTab` for the
//  gesture, one undo entry, not one per tab crossed.
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
    /// A tab dropped on one of the Space's dots.
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
    private unowned let spaces: TopBarSpaceName
    private var lift: SidebarDragLiftView?
    private var content = SidebarRowContent()
    /// The lift is a folder's header, which is never a tile.
    private var carriesFolder = false
    private var target: Target?
    /// Which gesture this is, for `SidebarTabDragController.gesture`'s reason:
    /// the lift settles for a third of a second after the mouse comes up, and a
    /// quick second drag must not have its run torn down by the first's.
    private var gesture = 0

    init(host: NSView, strip: TopBarTabStrip, spaces: TopBarSpaceName) {
        self.host = host
        self.strip = strip
        self.spaces = spaces
    }

    /// Runs the whole gesture, from the press the tile or row handed over to
    /// the mouse-up that ends it. Escape cancels, which is the one thing every
    /// drag on macOS can do.
    func track(_ lifted: TopBarLifted, from source: NSView, event press: NSEvent) {
        guard let window = host.window else { return }
        let origin = host.convert(source.bounds, from: source)
        let start = host.convert(press.locationInWindow, from: nil)
        let grab = start.x - origin.minX
        begin(lifted, at: origin, from: source)
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

    private func begin(_ lifted: TopBarLifted, at origin: NSRect, from source: NSView) {
        gesture += 1
        content = liftContent(for: lifted)
        if case .group = lifted { carriesFolder = true } else { carriesFolder = false }
        let view = SidebarDragLiftView(content: content)
        view.shape = source is GlassButton ? .tile : .row
        view.frame = origin
        host.addSubview(view, positioned: .above, relativeTo: nil)
        lift = view
        // Out of the run for the length of the gesture: its place closes up
        // behind it, so the index under the pointer is the index it lands at.
        strip.liftedID = lifted.id
        target = nil
        view.lift()
    }

    /// What the lift draws: the row the column would draw for it, with
    /// nothing trailing — a close glyph in the air is a control nobody can
    /// reach.
    private func liftContent(for lifted: TopBarLifted) -> SidebarRowContent {
        switch lifted {
        case let .tab(id):
            guard let tab = strip.session.tab(id) else { return SidebarRowContent() }
            var content = strip.rowContent(for: tab)
            content.trailing = .none
            return content
        case let .group(id):
            guard let group = strip.session.group(id) else { return SidebarRowContent() }
            return SidebarRowContent(title: group.name, symbolName: group.symbolName)
        }
    }

    /// The lift's leading edge follows the hand; its `y` never does. The bar is
    /// one line, and the only vertical movement the lift ever makes is the
    /// morph between a row's height and a tile's.
    private func move(_ lifted: TopBarLifted, to minX: CGFloat, pointer: NSPoint) {
        guard let lift else { return }
        // The run is read at the lift's leading edge, not at the hand: a tab
        // passes its neighbour once its edge is past the neighbour's middle,
        // which is the same distance in either direction. Read at the hand,
        // a tab held by its right half and put straight back down found the
        // neighbour that had closed up under it and landed one place along;
        // read at the lift's middle, a neighbour of the same width tied.
        let edge = NSPoint(x: minX, y: pointer.y)
        let next = resolve(lifted, at: pointer, edge: edge)
        let shape = shape(of: next)
        let size = size(of: shape)
        let resolved = next.map { target in
            guard case var .run(gap) = target else { return target }
            gap.width = size.width
            return .run(gap)
        }
        var morphed = false
        if resolved != target {
            // One tick per step, as the column does — and not for the first
            // target, which is the lift leaving the ground rather than passing
            // anything.
            if target != nil { Tokens.Haptics.step() }
            morphed = target.map { self.shape(of: $0) != shape } ?? false
            target = resolved
            apply(resolved)
        }
        lift.apply(frame: frame(minX: minX, size: size), shape: shape, animated: morphed)
    }

    private func frame(minX: CGFloat, size: NSSize) -> NSRect {
        let line = strip.convert(NSPoint(x: 0, y: strip.centreLine), to: host)
        return NSRect(x: minX, y: (line.y - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// A tab about to become one of §3.3's tiles is a tile, anywhere else
    /// §3.4's row — including over the new-folder landing, where what lands is
    /// a folder's header. A folder is always its header.
    private func shape(of target: Target?) -> SidebarDragLiftView.Shape {
        guard case let .run(gap)? = target, strip.landsAsTile(gap.destination), !carriesFolder else {
            return target == nil ? (lift?.shape ?? .row) : .row
        }
        return .tile
    }

    private func size(of shape: SidebarDragLiftView.Shape) -> NSSize {
        switch shape {
        case .tile: TopBarMetrics.keptTile.size
        case .row: NSSize(
            width: TopBarTabRow.pillWidth(for: content, isFolder: carriesFolder),
            height: TopBarMetrics.lineHeight
        )
        }
    }

    /// - Parameters:
    ///   - point: the hand, which is what the Space's dots answer to.
    ///   - edge: the lift's leading edge, which is what the run answers to.
    private func resolve(_ lifted: TopBarLifted, at point: NSPoint, edge: NSPoint) -> Target? {
        // Over the Space's name the dots come out, and a tab held on one goes
        // there. The rest of the name is no landing: it is the label on the
        // plate, not a place on it.
        if case .tab = lifted {
            spaces.isAimedAt = spaces.contains(point, from: host)
            if spaces.isAimedAt {
                return spaces.space(at: point, from: host).map(Target.space)
            }
        }
        // The frames have to be of the run as it is now: the lift has just
        // taken a tab out of it, and a pointer resolved against the frames from
        // before would be counting a tab that is no longer there.
        strip.layoutSubtreeIfNeeded()
        var local = strip.content.convert(edge, from: host)
        let landings = landings(for: lifted, at: local.x)
        if landings != strip.landings {
            strip.landings = landings
            strip.layoutSubtreeIfNeeded()
            local = strip.content.convert(edge, from: host)
        }
        let run = strip.run
        let (block, past) = block(at: local.x)
        if run.blocks.indices.contains(block), case .landing = run.blocks[block] {
            let destination = run.destination(forBlock: block, isPastMidpoint: past)
            return .run(DropGap(block: block, width: 0, destination: destination, fills: true))
        }
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
            // tiles lands at the head of the kept tier instead.
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

    /// The plate's landings, out while the lift is on the plate or within a
    /// tile's reach of it. Measured against the plate as it stands, so once
    /// they are out the plate is wider and holds them out — the pointer does
    /// not flicker them at the edge. A folder cannot be a tile, so it is
    /// offered only the folder tier.
    private func landings(for lifted: TopBarLifted, at x: CGFloat) -> Set<TabKind> {
        guard allowsPinning, x < strip.plateFrame.maxX + TopBarMetrics.keptTile.width else { return [] }
        if case .tab = lifted { return [.essential, .pinned] }
        return [.pinned]
    }

    /// The block under `x`, and which half of it. Past the last block is the
    /// end of the run; before the first is the first block's leading half.
    private func block(at x: CGFloat) -> (Int, Bool) {
        for (index, frame) in strip.blockFrames.enumerated() where x < frame.maxX {
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
        spaces.isAimedAt = false

        // Commit, then reveal — the column's order, for the column's reason:
        // the tab the lift stands in for is out of the run until the model has
        // moved it, so it is never seen back where it came from.
        let mine = gesture
        let landed: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            commit(lifted, landing: landing)
            guard mine == gesture else { return }
            strip.dropGap = nil
            strip.dropFolder = nil
            strip.landings = []
            strip.liftedID = nil
        }
        guard let lift, case .run? = landing, let rest = strip.gapFrame else {
            landed()
            lift?.drop()
            return
        }
        let settled = host.convert(rest, from: strip.content)
        lift.settle(into: frame(minX: settled.minX, size: lift.frame.size), then: landed)
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
