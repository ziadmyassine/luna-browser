//
//  TopBarTabStrip+Layout.swift
//  Luna
//
//  Where §4's run lands on the bar: what each block is worth in points, and the
//  one pass that places every chip, plate and hairline from it.
//
//  Split out of `TopBarTabStrip` when that file crossed SwiftLint's type body
//  limit, along the seam the file already had — everything there is the session
//  and the views it builds, everything here is arithmetic on frames. The stored
//  properties the two halves share are internal for that reason and no other.
//

import AppKit
import BrowserKit

extension TopBarTabStrip {

    // MARK: - Geometry

    /// Where the bar's centre falls inside the strip. Not `bounds.midX`:
    /// the strip is inset by a different amount on either side, and that
    /// difference is exactly what a centred run must not inherit.
    private var barCentre: CGFloat {
        guard let bar = superview else { return bounds.midX }
        return convert(NSPoint(x: bar.bounds.midX, y: 0), from: bar).x
    }

    /// What one block takes along the bar. A folder's plate and the kept
    /// run's cylinder are not in it: they are drawn around blocks, and their
    /// padding is added where they open and close — see `pieces`.
    private func width(of block: TopBarStripBlock) -> CGFloat {
        switch block {
        case let .tab(tab, _):
            chips[tab.id]?.intrinsicContentSize.width ?? TopBarMetrics.tile.width
        case let .group(group, _):
            chips[group.id]?.intrinsicContentSize.width ?? TopBarMetrics.chipFloor
        case .rule:
            // The hairline, with a cluster's worth of air either side of it
            // rather than the gap the rest of the run is spaced on: it divides
            // two runs, and a divider spaced like the things it divides reads
            // as one more of them.
            Tokens.Metric.hairline + (TopBarMetrics.clusterGap - TopBarMetrics.gap) * 2
        }
    }

    /// One thing the layout pass lays down, in order.
    private enum Piece {
        case block(Int)
        /// §6.6's gap: the room the lift will take when it lands.
        case gap(CGFloat)
        /// The empty kept run a drag reveals, so there is somewhere to pin to
        /// before anything is pinned — §3.4b's rule coming out, on a bar.
        case vacancy
        case openCylinder, closeCylinder
        case openPlate(UUID), closePlate(UUID)
    }

    /// The run, with its surfaces opened and closed around it and the gap put
    /// in. The gap is placed by what it means rather than by its index alone:
    /// the end of a folder and the start of whatever follows it are the same
    /// index, and only the destination says which side of the plate's edge the
    /// room belongs on. The same is true of the kept run's cylinder.
    private func pieces(gap drop: DropGap?) -> [Piece] {
        var out: [Piece] = []
        var placed = drop == nil
        func put(_ condition: Bool) {
            guard !placed, condition, let drop else { return }
            out.append(.gap(drop.width))
            placed = true
        }
        let revealed = run.kept == 0 && revealsKept
        if run.kept > 0 || revealed { out.append(.openCylinder) }
        if revealed {
            put(drop?.destination.kind != .today)
            if !placed || drop?.destination.kind == .today { out.append(.vacancy) }
            out.append(.closeCylinder)
        }
        for index in run.blocks.indices {
            put(drop?.block == index)
            if case let .group(group, _) = run.blocks[index] { out.append(.openPlate(group.id)) }
            out.append(.block(index))
            let header = run.owner(of: index)
            if case let .group(group, _) = run.blocks[header], run.lastBlock(ofFolderAt: header) == index {
                put(drop?.destination.groupID == group.id && drop?.block == index + 1)
                out.append(.closePlate(group.id))
            }
            if index == run.kept - 1 {
                put(drop?.destination.kind != .today && drop?.block == run.kept)
                out.append(.closeCylinder)
            }
        }
        put(true)
        return out
    }

    /// Where the layout pass has got to: the pen, and the edges of whatever
    /// surfaces are open under it.
    private struct Cursor {
        var originX: CGFloat
        /// Whether the next item needs the run's gap in front of it — false
        /// straight after a surface opens, whose padding stands in for it.
        var spaced = false
        var cylinderStart: CGFloat = 0
        var plateStart: [UUID: CGFloat] = [:]
    }

    /// Lays the pieces down from `start` and says how far they reached. With
    /// `placing` false nothing moves: that is the measuring pass, and the pass
    /// that works out where the run would be with no gap in it.
    @discardableResult
    private func lay(
        _ pieces: [Piece],
        from start: CGFloat,
        centre: CGFloat,
        placing: Bool,
        frames: inout [NSRect]
    ) -> CGFloat {
        var cursor = Cursor(originX: start, cylinderStart: start)
        // `surface` lays a cylinder or a plate down and says so; whatever it
        // did not take is something that takes room in the run.
        for piece in pieces where !surface(piece, cursor: &cursor, centre: centre, placing: placing) {
            item(piece, cursor: &cursor, centre: centre, placing: placing, frames: &frames)
        }
        return cursor.originX - start
    }

    /// A cylinder or a plate opening or closing. False for anything else.
    private func surface(_ piece: Piece, cursor: inout Cursor, centre: CGFloat, placing: Bool) -> Bool {
        let inset = TopBarMetrics.groupPlateInset
        switch piece {
        case .openCylinder:
            cursor.cylinderStart = cursor.originX
            cursor.originX += inset
            cursor.spaced = false
        case .closeCylinder:
            cursor.originX += inset
            if placing { cylinder.frame = plate(from: cursor.cylinderStart, to: cursor.originX, centre: centre) }
            cursor.spaced = true
        case let .openPlate(id):
            if cursor.spaced { cursor.originX += TopBarMetrics.gap }
            cursor.plateStart[id] = cursor.originX
            cursor.originX += inset
            cursor.spaced = false
        case let .closePlate(id):
            cursor.originX += inset
            let from = cursor.plateStart[id] ?? cursor.originX
            if placing { plates[id]?.frame = plate(from: from, to: cursor.originX, centre: centre) }
            cursor.spaced = true
        case .block, .gap, .vacancy:
            return false
        }
        return true
    }

    /// Something that takes room in the run: a block, the gap, or the empty
    /// kept run's one slot.
    private func item(
        _ piece: Piece,
        cursor: inout Cursor,
        centre: CGFloat,
        placing: Bool,
        frames: inout [NSRect]
    ) {
        if cursor.spaced { cursor.originX += TopBarMetrics.gap }
        let originX = cursor.originX
        switch piece {
        case let .block(index):
            let width = width(of: run.blocks[index])
            if frames.indices.contains(index) {
                frames[index] = NSRect(x: originX, y: 0, width: width, height: bounds.height)
            }
            if placing { place(run.blocks[index], at: originX, width: width, centre: centre) }
            cursor.originX += width
        case let .gap(width):
            if placing { gapFrame = NSRect(x: originX, y: 0, width: width, height: bounds.height) }
            cursor.originX += width
        default:
            cursor.originX += TopBarMetrics.tile.width
        }
        cursor.spaced = true
    }

    func placeContents() {
        // The traffic lights' line, not the bar's middle: the strip is pinned
        // top and bottom, so it takes the offset itself rather than through a
        // centre-line constraint the way the capsules beside it do.
        let centre = bounds.height / 2 - TopBarMetrics.lightsCentreOffset
        let laid = pieces(gap: dropGap)
        var frames = Array(repeating: NSRect.zero, count: run.blocks.count)
        let total = lay(laid, from: 0, centre: centre, placing: false, frames: &frames)
        let start = TopBarTabRun.leadingPad(
            position: tabsPosition,
            run: total,
            span: bounds.width,
            barCentre: barCentre
        )
        gapFrame = nil
        cylinder.isHidden = run.kept == 0 && !revealsKept
        lay(laid, from: start, centre: centre, placing: true, frames: &frames)
        // Where each block would be with no gap open, which is what a pointer
        // is resolved against. Resolving against the frames the gap has already
        // pushed would move the target the moment it was found, and the gap
        // would chase the pointer back and forth across one boundary.
        var resting = frames
        lay(pieces(gap: nil), from: start, centre: centre, placing: false, frames: &resting)
        blockFrames = resting

        content.frame = NSRect(x: 0, y: 0, width: start + total, height: bounds.height)
        placeGlow()
        scrollActiveTabIntoView()
    }

    /// A plate or a cylinder: the run it holds, with its padding, on the chips'
    /// own centre line.
    private func plate(from minX: CGFloat, to maxX: CGFloat, centre: CGFloat) -> NSRect {
        NSRect(
            x: minX,
            y: (centre - TopBarMetrics.plate.height / 2).rounded(),
            width: max(maxX - minX, 0),
            height: TopBarMetrics.plate.height
        )
    }

    /// §3.3's light, on the kept chip it belongs to — or nowhere.
    ///
    /// Placed from here as well as from `relight`, because the frame it stands
    /// on is not known until the run has been laid out, and the appear starts
    /// before that.
    func placeGlow() {
        guard let litID, let chip = chips[litID] else { return }
        glow.frame = chip.frame
    }

    private func place(_ block: TopBarStripBlock, at originX: CGFloat, width: CGFloat, centre: CGFloat) {
        switch block {
        case let .tab(tab, _):
            place(chips[tab.id], at: originX, centre: centre)
        case let .group(group, _):
            place(chips[group.id], at: originX, centre: centre)
        case .rule:
            let size = rule.intrinsicContentSize
            rule.frame = NSRect(
                x: (originX + (width - size.width) / 2).rounded(),
                y: (centre - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            )
        }
    }

    private func place(_ chip: TopBarButton?, at originX: CGFloat, centre: CGFloat) {
        guard let chip else { return }
        let size = chip.intrinsicContentSize
        chip.frame = NSRect(
            x: originX,
            y: (centre - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func scrollActiveTabIntoView() {
        guard let activeID, activeID != scrolledTo, let chip = chips[activeID] else { return }
        scrolledTo = activeID
        // A gap of slack on each side, so the active tab never lands flush
        // against a clipped neighbour.
        content.scrollToVisible(chip.frame.insetBy(dx: -TopBarMetrics.gap, dy: 0))
    }
}

/// §4's alignment as arithmetic: where the run of tabs starts inside the strip.
/// Pure, so "centred means centred in the bar" is a test rather than a
/// screenshot — the thing it got wrong was a quarter of an inch of window, and
/// nothing about the old code looked wrong.
enum TopBarTabRun {

    /// - Parameters:
    ///   - run: the tabs' total width.
    ///   - span: the strip's own width.
    ///   - barCentre: the bar's centre, in the strip's coordinates.
    /// - Returns: the clear space in front of the first tab.
    static func leadingPad(
        position: TabsPosition,
        run: CGFloat,
        span: CGFloat,
        barCentre: CGFloat
    ) -> CGFloat {
        guard run < span else { return 0 }
        return switch position {
        case .left: 0
        // Clamped into the strip, so a run too wide to reach the middle starts
        // as close to it as it can rather than under the neighbouring cluster.
        case .centre: min(max(barCentre - run / 2, 0), span - run).rounded()
        case .right: span - run
        }
    }
}

/// The scroll view's document view. Dragging the empty part of the strip drags
/// the window (§4) — the chips and the plates opt out for themselves.
final class StripContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
