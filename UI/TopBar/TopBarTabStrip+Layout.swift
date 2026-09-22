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

    /// What one block takes along the bar. A folder's is its plate: the header,
    /// its open tabs, and the inset the plate stands proud of them by.
    private func width(of block: TopBarStripBlock) -> CGFloat {
        switch block {
        case let .tab(tab, _):
            chips[tab.id]?.intrinsicContentSize.width ?? TopBarMetrics.tile.width
        case let .group(group, members, _):
            members.reduce(chips[group.id]?.intrinsicContentSize.width ?? TopBarMetrics.chipFloor) {
                $0 + TopBarMetrics.gap + (chips[$1.id]?.intrinsicContentSize.width ?? TopBarMetrics.tile.width)
            } + TopBarMetrics.groupPlateInset * 2
        case .rule:
            // The hairline, with a cluster's worth of air either side of it
            // rather than the gap the rest of the run is spaced on: it divides
            // two runs, and a divider spaced like the things it divides reads
            // as one more of them.
            Tokens.Metric.hairline + (TopBarMetrics.clusterGap - TopBarMetrics.gap) * 2
        }
    }

    func placeContents() {
        let widths = run.blocks.map(width(of:))
        let pad = run.kept > 0 ? TopBarMetrics.groupPlateInset * 2 : 0
        let total = max(widths.reduce(pad) { $0 + $1 + TopBarMetrics.gap } - TopBarMetrics.gap, 0)
        // The traffic lights' line, not the bar's middle: the strip is pinned
        // top and bottom, so it takes the offset itself rather than through a
        // centre-line constraint the way the capsules beside it do.
        let centre = bounds.height / 2 - TopBarMetrics.lightsCentreOffset
        let start = TopBarTabRun.leadingPad(
            position: tabsPosition,
            run: total,
            span: bounds.width,
            barCentre: barCentre
        )
        var originX = start + (run.kept > 0 ? TopBarMetrics.groupPlateInset : 0)

        for (index, (block, width)) in zip(run.blocks, widths).enumerated() {
            place(block, at: originX, width: width, centre: centre)
            originX += width
            // The cylinder closes after the last kept block, before the gap
            // that leads to the hairline.
            if index == run.kept - 1 {
                cylinder.frame = plate(from: start, to: originX + TopBarMetrics.groupPlateInset, centre: centre)
                originX += TopBarMetrics.groupPlateInset
            }
            originX += TopBarMetrics.gap
        }

        content.frame = NSRect(
            x: 0,
            y: 0,
            width: max(originX - TopBarMetrics.gap, 0),
            height: bounds.height
        )
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
        case let .group(group, members, _):
            plates[group.id]?.frame = plate(from: originX, to: originX + width, centre: centre)
            var x = originX + TopBarMetrics.groupPlateInset
            for id in [group.id] + members.map(\.id) {
                place(chips[id], at: x, centre: centre)
                x += (chips[id]?.intrinsicContentSize.width ?? 0) + TopBarMetrics.gap
            }
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
