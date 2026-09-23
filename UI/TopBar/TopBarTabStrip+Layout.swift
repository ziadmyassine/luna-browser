//
//  TopBarTabStrip+Layout.swift
//  Luna
//
//  Where §4's run lands on the bar: what each block is worth in points, and the
//  one pass that places every tile, row, plate and mark from it.
//
//  Split out of `TopBarTabStrip` when that file crossed SwiftLint's type body
//  limit, along the seam the file already had — everything there is the session
//  and the views it builds, everything here is arithmetic on frames. The stored
//  properties the two halves share are internal for that reason and no other.
//
//  One gap between any two things on the bar, and the plate's own padding
//  between any two things on the plate — the capsule's two numbers, so the
//  plate at one end of the bar and the capsule at the other are spaced alike.
//

import AppKit
import BrowserKit

/// Which part of the run a piece stands in, for the gap in front of it.
private enum Side {
    /// The Space's name, at the head of the plate.
    case name
    /// On the plate, after the name.
    case kept
    /// The plate's closing edge.
    case rule
    /// Today's tabs, after the plate.
    case open
}

/// Where a piece stands: its side, the folder it is in (its own, for a
/// header), and whether it is that folder's header.
private struct Place {
    var side: Side
    var folder: UUID?
    var isHeader = false
    /// On the Space's plate: §3.3's tiles and the empty tile a lift opens.
    /// §3.4b's kept folders stand beside it on plates of their own.
    var onSpacePlate = false
}

/// One pass of `lay`: where each block, the gap, the name and the plate land.
struct TopBarLaidRun {
    var frames: [Int: NSRect] = [:]
    var gap: NSRect?
    var name: NSRect = .zero
    var plate: NSRect = .zero
    /// Where the pinned section ends: the Space's plate and any kept
    /// folders beside it.
    var keptEnd: CGFloat = 0
    var end: CGFloat = 0
}

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
    /// centre-line constraint the way the capsule beside it does.
    var centreLine: CGFloat { bounds.height / 2 - TopBarMetrics.lightsCentreOffset }

    /// What one block takes along the bar.
    private func width(ofBlock index: Int) -> CGFloat {
        switch run.blocks[index] {
        case .tab(_, .tile), .landing(.essential):
            TopBarMetrics.keptTile.width
        case let .tab(tab, .row):
            TopBarTabRow.pillWidth(for: rows[tab.id]?.content ?? rowContent(for: tab))
        case let .group(group, _):
            TopBarTabRow.pillWidth(
                for: rows[group.id]?.content ?? SidebarRowContent(title: group.name, symbolName: group.symbolName),
                isFolder: true
            )
        case .landing:
            TopBarMetrics.rowFloor
        case .rule:
            Tokens.Metric.hairline
        }
    }

    /// How tall a block stands: a capsule item's height on the plate, the
    /// capsule's own off it.
    func height(ofBlock index: Int) -> CGFloat {
        run.isKept(index) ? TopBarMetrics.keptTile.height : TopBarMetrics.lineHeight
    }

    private func place(of block: Int) -> Place {
        switch run.blocks[block] {
        case .rule: return Place(side: .rule)
        case .landing(.essential): return Place(side: .kept, onSpacePlate: true)
        case let .tab(tab, _) where tab.kind == .essential: return Place(side: .kept, onSpacePlate: true)
        default: break
        }
        let side: Side = run.isKept(block) ? .kept : .open
        let header = run.owner(of: block)
        guard case let .group(group, _) = run.blocks[header] else { return Place(side: side) }
        return Place(side: side, folder: group.id, isHeader: header == block)
    }

    /// The room in front of a piece. On a plate the tabs stand edge to edge —
    /// each has its own room round its icon — and a plate ends at its last
    /// one. After a folder's name, the divider with a gap either side. Off a
    /// plate, and either side of the hairline, the bar's one gap.
    private func spacing(from previous: Place, to next: Place) -> CGFloat {
        if next.side == .rule || previous.side == .rule { return TopBarMetrics.gap }
        if let folder = next.folder, previous.folder == folder, !next.isHeader {
            return previous.isHeader ? TopBarMetrics.dividerGap * 2 + Tokens.Metric.hairline : 0
        }
        if next.onSpacePlate, previous.side == .name || previous.onSpacePlate { return 0 }
        return TopBarMetrics.gap
    }

    /// One thing the layout pass lays down, in order.
    private enum Piece {
        case block(Int)
        /// §6.6's gap: the room the lift will take when it lands, and whether
        /// it opens on the plate.
        case gap(CGFloat, kept: Bool)
    }

    /// The run, with the gap put in. The gap is placed by what it means rather
    /// than by its index alone: the end of a folder and the start of whatever
    /// follows are the same index, and only the destination says which side of
    /// the folder's end the room belongs on. A drop into a landing opens no gap
    /// at all — the landing is the room.
    private func pieces(gap drop: DropGap?) -> [Piece] {
        var out: [Piece] = []
        var placed = drop == nil || drop?.fills == true
        func put(_ condition: Bool) {
            guard !placed, condition, let drop else { return }
            out.append(.gap(drop.width, kept: drop.destination.kind != .today))
            placed = true
        }
        for index in run.blocks.indices {
            put(drop?.block == index)
            out.append(.block(index))
            let header = run.owner(of: index)
            if case let .group(group, _) = run.blocks[header], run.lastBlock(ofFolderAt: header) == index {
                put(drop?.destination.groupID == group.id && drop?.block == index + 1)
            }
        }
        put(true)
        return out
    }

    /// Where each piece lands, from `start`. Pure arithmetic — `placeContents`
    /// is what puts views there — so it runs three times a pass for nothing:
    /// once to measure, once to place, once for the frames with no gap open.
    private func lay(_ pieces: [Piece], from start: CGFloat) -> TopBarLaidRun {
        var laid = TopBarLaidRun()
        laid.name = NSRect(
            x: start,
            y: 0,
            width: spaceName.intrinsicContentSize.width,
            height: bounds.height
        )
        var originX = laid.name.maxX
        var plateEnd = originX
        var previous = Place(side: .name)
        for piece in pieces {
            let next: Place
            let width: CGFloat
            switch piece {
            case let .block(index):
                next = place(of: index)
                width = self.width(ofBlock: index)
                originX += spacing(from: previous, to: next)
                laid.frames[index] = NSRect(x: originX, y: 0, width: width, height: bounds.height)
            case let .gap(gapWidth, kept):
                next = Place(
                    side: kept ? .kept : .open,
                    folder: dropGap?.destination.groupID,
                    onSpacePlate: dropGap?.destination.kind == .essential
                )
                width = gapWidth
                originX += spacing(from: previous, to: next)
                laid.gap = NSRect(x: originX, y: 0, width: width, height: bounds.height)
            }
            originX += width
            if next.onSpacePlate { plateEnd = originX }
            if next.side == .kept { laid.keptEnd = originX }
            previous = next
        }
        laid.plate = NSRect(x: start, y: 0, width: plateEnd - start, height: bounds.height)
        laid.keptEnd = max(laid.keptEnd, laid.plate.maxX)
        laid.end = max(originX, laid.plate.maxX)
        return laid
    }

    func placeContents() {
        let laid = pieces(gap: dropGap)
        let total = lay(laid, from: 0).end
        let start = frozenStart ?? TopBarTabRun.leadingPad(
            position: tabsPosition,
            run: total,
            span: bounds.width,
            barCentre: barCentre
        )
        lastStart = start
        targets = [:]
        let placed = lay(laid, from: start)
        for (index, frame) in placed.frames {
            place(index, in: frame)
        }
        plateFrame = box(placed.plate, height: TopBarMetrics.plate.height)
        keptEnd = placed.keptEnd
        put(plate, at: plateFrame)
        put(spaceName, at: box(placed.name, height: TopBarMetrics.lineHeight))
        if let dropGap, dropGap.fills {
            gapFrame = placed.frames[dropGap.block]
        } else {
            gapFrame = placed.gap
        }
        placeMarks(placed)

        // Where each block would be with no gap open, which is what a pointer
        // is resolved against. Resolving against the frames the gap has already
        // pushed would move the target the moment it was found, and the gap
        // would chase the pointer back and forth across one boundary.
        let resting = lay(pieces(gap: nil), from: start).frames
        blockFrames = run.blocks.indices.map { resting[$0] ?? .zero }

        // Never narrower than the strip: the empty bar past the last tab is
        // the document view's, which moves the window, and not the clip
        // view's, which would not say.
        content.frame = NSRect(x: 0, y: 0, width: max(start + total, bounds.width), height: bounds.height)
        // A run that fits is never left scrolled. The clip view keeps its
        // offset when the run shrinks under it — after a drag's landings
        // close, or a tab closes — and the whole run then stood a few points
        // to the left of where it belongs, the plate against the lights.
        if start + total <= bounds.width, scrollView.contentView.bounds.origin.x != 0 {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        placeGlow()
        scrollActiveTabIntoView()
    }

    /// A kept tile or a row, standing on the bar's line at its own height.
    private func place(_ index: Int, in slot: NSRect) {
        let frame = box(slot, height: height(ofBlock: index))
        switch run.blocks[index] {
        case let .tab(tab, .tile):
            put(tiles[tab.id], id: tab.id, at: frame)
        case let .tab(tab, .row):
            put(rows[tab.id], id: tab.id, at: frame)
        case let .group(group, _):
            put(rows[group.id], id: group.id, at: frame)
        case .rule:
            placeRule(in: frame)
        case .landing:
            break
        }
    }

    /// Luna's recurring animation bug, avoided: a view that has never been
    /// placed has nowhere to animate from, and inside an animated pass it
    /// would fly in from the bar's corner. It lands where it belongs with the
    /// animation off, and its own fade is what arrives (`fadeIn`). Every view
    /// already standing somewhere travels.
    private func put(_ view: NSView?, id: UUID? = nil, at frame: NSRect) {
        if let id { targets[id] = frame }
        guard let view else { return }
        guard view.frame != .zero else {
            return Tokens.Motion.immediately { view.frame = frame }
        }
        view.frame = frame
    }

    func box(_ slot: NSRect, height: CGFloat) -> NSRect {
        NSRect(x: slot.minX, y: (centreLine - height / 2).rounded(), width: slot.width, height: height)
    }

    /// The hairline between the pinned section and today's tabs — the bar's
    /// own separator, the one before the capsule.
    private func placeRule(in slot: NSRect) {
        let size = rule.intrinsicContentSize
        let frame = NSRect(
            x: (slot.midX - size.width / 2).rounded(),
            y: (centreLine - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        reveal(rule) { rule.frame = frame }
    }

    /// Each folder's divider and plate, and the two dashed landings.
    private func placeMarks(_ placed: TopBarLaidRun) {
        if !run.blocks.contains(.rule) { rule.isHidden = true }
        for (header, block) in run.blocks.enumerated() {
            guard case let .group(group, _) = block, let head = placed.frames[header] else { continue }
            let last = run.lastBlock(ofFolderAt: header)
            let gap = dropGap?.destination.groupID == group.id ? placed.gap : nil
            var extent = head
            if let tail = placed.frames[last] { extent = extent.union(tail) }
            if let gap { extent = extent.union(gap) }
            placeDivider(dividers[group.id], after: head, showing: last != header || gap != nil)
            // The folder's own plate grows round the room a lift is opening
            // in it and lights, so the drop reads as going in.
            if let folderPlate = folderPlates[group.id] {
                put(folderPlate, at: box(extent, height: TopBarMetrics.plate.height))
                folderPlate.isAimedAt = dropFolder == group.id
            }
        }

        // §3.3's dashed slot: the empty tile a drag offers when nothing is
        // pinned, or round the gap when a tab is about to become a tile.
        let tileLanding = run.blocks.firstIndex(of: .landing(.essential))
        let tileGap = dropGap.flatMap { gap in
            gap.fills || !landsAsTile(gap.destination) ? nil : placed.gap
        }
        mark(slot, at: tileLanding.flatMap { placed.frames[$0] } ?? tileGap, landing: tileLanding)
        mark(folderSlot, at: run.blocks.firstIndex(of: .landing(.pinned)).flatMap { placed.frames[$0] },
             landing: run.blocks.firstIndex(of: .landing(.pinned)))
    }

    /// The hairline after a folder's name, centred in the room `spacing`
    /// leaves for it — only when something follows the name.
    private func placeDivider(_ divider: TopBarSeparator?, after head: NSRect, showing: Bool) {
        guard let divider else { return }
        guard showing else {
            divider.isHidden = true
            return
        }
        let size = divider.intrinsicContentSize
        let frame = NSRect(
            x: head.maxX + TopBarMetrics.dividerGap,
            y: (centreLine - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        reveal(divider) { divider.frame = frame }
    }

    /// Whether a tab put down at `destination` is drawn as one of §3.3's
    /// tiles: among the grid's, or inside a kept folder.
    func landsAsTile(_ destination: SidebarDestination) -> Bool {
        destination.kind == .essential || (destination.kind == .pinned && destination.groupID != nil)
    }

    private func mark(_ outline: TopBarSlotOutline, at frame: NSRect?, landing: Int?) {
        guard let frame else {
            outline.isHidden = true
            outline.isAimedAt = false
            return
        }
        reveal(outline) { outline.frame = box(frame, height: TopBarMetrics.keptTile.height) }
        outline.isAimedAt = landing != nil && dropGap?.fills == true && dropGap?.block == landing
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
        Tokens.Motion.immediately { glow.frame = frame.insetBy(dx: -glowOutset, dy: -glowOutset) }
    }

    /// How far the light stands out from its tile, which is as tall as the
    /// plate: its ring is drawn a rim outside its own frame, so the frame
    /// stands a rim inside the tile and the ring lands on the plate's edge
    /// rather than a rim beyond it.
    var glowOutset: CGFloat { -Tokens.Metric.essentialsGlowRim }

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
/// the window (§4) — the plate, the tiles and the rows opt out for themselves
/// — and a right-click on it is the bar's own menu.
final class StripContentView: NSView {
    var menuBuilder: (() -> NSMenu?)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }
}
