//
//  TopBarTabStrip+Layout.swift
//  Luna
//
//  Where §4's run lands on the bar: what each block is worth in points, and the
//  one pass that places every tile, row, spine and mark from it.
//
//  Split out of `TopBarTabStrip` when that file crossed SwiftLint's type body
//  limit, along the seam the file already had — everything there is the session
//  and the views it builds, everything here is arithmetic on frames. The stored
//  properties the two halves share are internal for that reason and no other.
//
//  The spacing is the column's, per kind: the grid's gutter between two kept
//  tiles, §3.4's gap between two row pills. A bar that spaced everything alike
//  would put the tiles further apart than the column does, and they would stop
//  reading as the same grid.
//

import AppKit
import BrowserKit

extension TopBarTabStrip {

    // MARK: - Geometry

    /// Bounds-derived frames never animate — see `Motion.immediately` — with
    /// one exception: a run already on screen changing, which moves every tab
    /// after the change along the bar, and that move is exactly the thing that
    /// should be seen.
    func layOutRun() {
        let animated = animatesNextPlacement && !Tokens.Motion.reduceMotion
        animatesNextPlacement = false
        guard animated else {
            Tokens.Motion.immediately { placeContents() }
            movePills(animated: false)
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            placeContents()
        }
        movePills()
    }

    /// Where the bar's centre falls inside the strip. Not `bounds.midX`:
    /// the strip is inset by a different amount on either side, and that
    /// difference is exactly what a centred run must not inherit.
    private var barCentre: CGFloat {
        guard let bar = superview else { return bounds.midX }
        return convert(NSPoint(x: bar.bounds.midX, y: 0), from: bar).x
    }

    /// The traffic lights' line, not the bar's middle: the strip is pinned
    /// top and bottom, so it takes the offset itself rather than through a
    /// centre-line constraint the way the capsules beside it do.
    var centreLine: CGFloat { bounds.height / 2 - TopBarMetrics.lightsCentreOffset }

    /// What one block takes along the bar.
    private func width(of block: TopBarStripBlock) -> CGFloat {
        switch block {
        case .tab(_, .tile):
            TopBarMetrics.keptTile.width
        case let .tab(tab, .row):
            TopBarTabRow.pillWidth(for: rows[tab.id]?.content ?? rowContent(for: tab))
        case let .group(group, _):
            TopBarTabRow.pillWidth(for: rows[group.id]?.content ?? SidebarRowContent(
                title: group.name,
                symbolName: group.symbolName,
                disclosure: .collapsed
            ))
        case .rule:
            ruleWidth
        }
    }

    /// The hairline, with a cluster's worth of air either side of it: it
    /// divides two runs, and a divider spaced like the things it divides reads
    /// as one more of them.
    private var ruleWidth: CGFloat {
        Tokens.Metric.hairline + (TopBarMetrics.clusterGap - TopBarMetrics.gap) * 2
    }

    /// The space after a block: the grid's gutter after a kept tile, §3.4's
    /// pill gap after a row.
    private func spacing(after block: TopBarStripBlock?) -> CGFloat {
        guard case .tab(_, .tile)? = block else { return TopBarMetrics.rowGap }
        return TopBarMetrics.keptGap
    }

    /// One thing the layout pass lays down, in order.
    private enum Piece {
        case block(Int)
        /// §6.6's gap: the room the lift will take when it lands.
        case gap(CGFloat)
        /// The end of a folder: what separates "the last place inside it"
        /// from "the first place after it", which are the same index.
        case endOfFolder(UUID)
    }

    /// The run, with the gap put in. The gap is placed by what it means rather
    /// than by its index alone: the end of a folder and the start of whatever
    /// follows are the same index, and only the destination says which side of
    /// the folder's end the room belongs on.
    private func pieces(gap drop: DropGap?) -> [Piece] {
        var out: [Piece] = []
        var placed = drop == nil
        func put(_ condition: Bool) {
            guard !placed, condition, let drop else { return }
            out.append(.gap(drop.width))
            placed = true
        }
        // A drop into the empty kept run lands in the vacancy, which is not
        // part of the run — see `vacancyWidth`.
        if isVacant, drop?.destination.kind != .today { placed = true }
        for index in run.blocks.indices {
            put(drop?.block == index)
            out.append(.block(index))
            let header = run.owner(of: index)
            if case let .group(group, _) = run.blocks[header], run.lastBlock(ofFolderAt: header) == index {
                put(drop?.destination.groupID == group.id && drop?.block == index + 1)
                out.append(.endOfFolder(group.id))
            }
        }
        put(true)
        return out
    }

    /// Where each piece lands, from `start`. Pure arithmetic — `placeContents`
    /// is what puts views there — so it runs three times a pass for nothing:
    /// once to measure, once to place, once for the frames with no gap open.
    private func lay(_ pieces: [Piece], from start: CGFloat) -> (frames: [Int: NSRect], gap: NSRect?, end: CGFloat) {
        var originX = start
        var previous: TopBarStripBlock?
        var frames: [Int: NSRect] = [:]
        var gap: NSRect?
        var first = true
        for piece in pieces {
            switch piece {
            case .endOfFolder:
                continue
            case let .block(index):
                if !first { originX += spacing(after: previous) }
                let width = width(of: run.blocks[index])
                frames[index] = NSRect(x: originX, y: 0, width: width, height: bounds.height)
                originX += width
                previous = run.blocks[index]
            case let .gap(width):
                if !first { originX += spacing(after: previous) }
                gap = NSRect(x: originX, y: 0, width: width, height: bounds.height)
                originX += width
            }
            first = false
        }
        return (frames, gap, originX)
    }

    /// An empty kept run taking a drop: a drag is up, and nothing is kept.
    var isVacant: Bool { run.kept == 0 && revealsKept }

    /// What the vacancy takes in front of the run: §3.3's empty slot, and the
    /// hairline after it with a row's gap either side.
    ///
    /// It stands in the clear bar before the run rather than pushing the run
    /// along — a run that jumped a tile's width to the right the moment a tab
    /// was picked up would have moved every tab out from under the pointer. It
    /// only pushes when there is no clear bar to stand in.
    private var vacancyWidth: CGFloat {
        TopBarMetrics.keptTile.width + TopBarMetrics.rowGap * 2 + ruleWidth
    }

    func placeContents() {
        let laid = pieces(gap: dropGap)
        let total = lay(laid, from: 0).end
        let lead = isVacant ? vacancyWidth : 0
        let start = max(frozenStart ?? TopBarTabRun.leadingPad(
            position: tabsPosition,
            run: total,
            span: bounds.width,
            barCentre: barCentre
        ), lead)
        lastStart = start
        targets = [:]
        let placed = lay(laid, from: start)
        for (index, frame) in placed.frames {
            place(run.blocks[index], in: frame)
        }
        let vacancy = NSRect(x: start - lead, y: 0, width: TopBarMetrics.keptTile.width, height: bounds.height)
        let intoVacancy = isVacant && dropGap.map { $0.destination.kind != .today } == true
        gapFrame = intoVacancy ? vacancy : placed.gap
        vacancyFrame = isVacant ? vacancy : nil
        placeMarks(placed, vacancy: isVacant ? vacancy : nil)

        // Where each block would be with no gap open, which is what a pointer
        // is resolved against. Resolving against the frames the gap has already
        // pushed would move the target the moment it was found, and the gap
        // would chase the pointer back and forth across one boundary.
        let resting = lay(pieces(gap: nil), from: start).frames
        blockFrames = run.blocks.indices.map { resting[$0] ?? .zero }

        content.frame = NSRect(x: 0, y: 0, width: start + total, height: bounds.height)
        placeGlow()
        scrollActiveTabIntoView()
    }

    /// A kept tile or a row, standing on the bar's line at its own height.
    private func place(_ block: TopBarStripBlock, in slot: NSRect) {
        switch block {
        case let .tab(tab, .tile):
            put(tiles[tab.id], id: tab.id, at: box(slot, height: TopBarMetrics.keptTile.height))
        case let .tab(tab, .row):
            put(rows[tab.id], id: tab.id, at: box(slot, height: Tokens.Metric.rowPillHeight))
        case let .group(group, _):
            put(rows[group.id], id: group.id, at: box(slot, height: Tokens.Metric.rowPillHeight))
        case .rule:
            placeRule(in: slot)
        }
    }

    /// Luna's recurring animation bug, avoided: a view that has never been
    /// placed has nowhere to animate from, and inside an animated pass it
    /// would fly in from the bar's corner. It lands where it belongs with the
    /// animation off, and its own fade is what arrives (`fadeIn`). Every view
    /// already standing somewhere travels.
    private func put(_ view: NSView?, id: UUID, at frame: NSRect) {
        targets[id] = frame
        guard let view else { return }
        guard view.frame != .zero else {
            return Tokens.Motion.immediately { view.frame = frame }
        }
        view.frame = frame
    }

    private func box(_ slot: NSRect, height: CGFloat) -> NSRect {
        NSRect(x: slot.minX, y: (centreLine - height / 2).rounded(), width: slot.width, height: height)
    }

    private func placeRule(in slot: NSRect) {
        let size = rule.intrinsicContentSize
        rule.frame = NSRect(
            x: (slot.midX - size.width / 2).rounded(),
            y: (centreLine - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// The spines under open folders, the box round a folder taking a drop,
    /// and §3.3's dashed slot where a kept tab is about to land.
    private func placeMarks(_ placed: (frames: [Int: NSRect], gap: NSRect?, end: CGFloat), vacancy: NSRect?) {
        let pill = Tokens.Metric.rowPillHeight
        var dropBox: NSRect?
        for (header, block) in run.blocks.enumerated() {
            guard case let .group(group, _) = block, let head = placed.frames[header] else { continue }
            let last = run.lastBlock(ofFolderAt: header)
            var extent = head
            if let tail = placed.frames[last] { extent = extent.union(tail) }
            if let gap = placed.gap, dropGap?.destination.groupID == group.id { extent = extent.union(gap) }
            // The spine runs under the folder's tabs, from the first to the
            // last, a hairline below the pills — §3.4b's mark, on its side.
            if let spine = spines[group.id] {
                let first = placed.frames[header + 1]
                spine.isHidden = last == header || first == nil
                if let first, let tail = placed.frames[last] {
                    spine.frame = NSRect(
                        x: first.minX + Tokens.Metric.rowInset,
                        y: (centreLine - pill / 2 - Tokens.Metric.rowGap).rounded() - Tokens.Metric.hairline,
                        width: max(tail.maxX - first.minX - Tokens.Metric.rowInset * 2, 0),
                        height: Tokens.Metric.hairline
                    )
                }
            }
            if dropFolder == group.id { dropBox = box(extent, height: pill) }
        }
        folderDrop.show(dropBox)

        // The hairline: between the runs, or after the vacancy while a drag
        // has one open.
        if let vacancy {
            reveal(rule) { placeRule(in: NSRect(x: vacancy.maxX + TopBarMetrics.rowGap, y: 0, width: ruleWidth, height: 0)) }
        } else {
            rule.isHidden = !run.blocks.contains(.rule)
        }

        // §3.3's dashed slot: the vacancy while it is open, or round the gap
        // when a kept tab is about to land there.
        let keptLanding = dropGap.map { $0.destination.kind != .today } ?? false
        if let target = vacancy ?? (keptLanding ? placed.gap : nil) {
            reveal(slot) { slot.frame = box(target, height: TopBarMetrics.keptTile.height) }
        } else {
            slot.isHidden = true
        }
    }

    /// A mark coming out of hiding lands where it belongs rather than
    /// travelling there from wherever it was last — the fresh-view rule
    /// (`put`), for a view that is not new but has not been seen.
    private func reveal(_ view: NSView, place: () -> Void) {
        guard view.isHidden else { return place() }
        Tokens.Motion.immediately(place)
        view.isHidden = false
    }

    /// §3.3's light, on the kept tile it belongs to — or nowhere.
    ///
    /// Placed from here as well as from `relight`, because the frame it stands
    /// on is not known until the run has been laid out, and the appear starts
    /// before that.
    ///
    /// Never animated: the light is one view moved between tiles, and an
    /// animated pass would slide it across the bar from the tile you left —
    /// the grid's rule, for the grid's reason.
    func placeGlow() {
        guard let litID, let frame = targets[litID] else { return }
        Tokens.Motion.immediately { glow.frame = frame }
    }

    private func scrollActiveTabIntoView() {
        guard let activeID, activeID != scrolledTo, let frame = targets[activeID] else { return }
        scrolledTo = activeID
        // A gap of slack on each side, so the active tab never lands flush
        // against a clipped neighbour.
        content.scrollToVisible(frame.insetBy(dx: -TopBarMetrics.gap, dy: 0))
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
/// the window (§4) — the tiles and rows opt out for themselves.
final class StripContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
