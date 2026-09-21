//
//  SidebarViewController+Layout.swift
//  Luna
//
//  The other half of `SidebarViewController`: where everything in §3's column
//  goes. Split off when the controller crossed SwiftLint's 400-line limit —
//  the rest of that file wires closures and re-reads the session, and neither
//  of those is arithmetic.
//
//  Nothing moved on the way across.
//

import AppKit
import BrowserKit

extension SidebarViewController {

    override func viewDidLayout() {
        super.viewDidLayout()
        // Every frame below is computed from `bounds`, so none of them may
        // animate — see `Motion.immediately`. Without this the §4.1 layout
        // switch's own transaction swallowed the whole pass.
        //
        // The one exception is the pass where the Essentials grid changed
        // height: the list and the scroll view below it have to travel, and
        // snapping them is what made pinning a tab look like a redraw rather
        // than a movement.
        let gridHeight = essentials.intrinsicContentSize.height
        let moved = lastGridHeight.map { $0 != gridHeight } ?? false
        lastGridHeight = gridHeight
        guard moved, !Tokens.Motion.reduceMotion else {
            Tokens.Motion.immediately { layoutSubviews() }
            return
        }
        Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
            context.allowsImplicitAnimation = true
            layoutSubviews()
        }
    }

    /// Every position is computed, and none is read back.
    ///
    /// This used to walk down the column asking each view where the one above
    /// it had ended up — `pill.frame.minY`, `essentials.frame.minY`. Inside an
    /// animated pass that read is a frame behind: setting a frame under
    /// `allowsImplicitAnimation` routes it through the animator, and the getter
    /// hands back the value the view still has. So on the pass where the grid
    /// shrank, the scroll view under it was sized against the grid's old
    /// bottom edge and stayed a tile-row short — an unpinned tab left a 47 pt
    /// hole between the tiles and the list that only a window resize cleared.
    /// The column's geometry is arithmetic; it is done here, once, in locals.
    private func layoutSubviews() {
        let bounds = view.bounds
        wash.frame = bounds
        let inset = Tokens.Metric.rowInset
        let bar = Tokens.Metric.topBarHeight
        // §3.2b: the pill is on the page, so the column closes up over its row
        // — and the control row above it shrinks to what the lights need.
        let pillHeight = pill.isHidden ? 0 : Tokens.Metric.urlPill.height
        let head = pill.isHidden ? Tokens.Metric.sidebarHeadlessRow : bar
        let gridHeight = essentials.intrinsicContentSize.height
        let controlTop = bounds.maxY - head
        let pillTop = controlTop - pillHeight
        let gridTop = pillTop - gridHeight

        controlRow.frame = NSRect(x: 0, y: controlTop, width: bounds.width, height: head)
        // The row places its buttons against the traffic lights, which move
        // and disappear without its own bounds changing — entering fullscreen
        // takes them away and leaves the row exactly 52 pt tall and exactly as
        // wide. Nothing would mark it dirty, so the row kept a hole at its head
        // where three lights used to be.
        controlRow.needsLayout = true
        // Flush under the control row, not §3.2's 12 pt below it: the row is
        // 52 pt and its buttons are only 35, so the row already carries ~8 pt
        // of clear space below them — which is exactly the gap the reference
        // measures between the reload button and the top of the pill. Adding a
        // second gap on top of it doubles a space that is already right.
        pill.frame = NSRect(
            x: inset,
            y: pillTop,
            width: max(bounds.width - 2 * inset, 0),
            height: pillHeight
        ).integral

        essentials.frame = NSRect(x: 0, y: gridTop, width: bounds.width, height: gridHeight).integral

        utility.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bar)
        // §3.5's profile line stands on the Space strip, not on the bar.
        //
        // The bar is 52 pt and its three clusters are centred on its midline,
        // which leaves 15 pt of empty air above the 22 pt Space pill — so a
        // caption parked above the bar sat that 15 pt clear of the dots it
        // belongs to, and read as the last line of the tab list instead of as
        // the label on the strip. It is placed against the strip's own top edge
        // instead and is allowed to overlap the bar's dead air to get there;
        // the pill does not move, so the dots stay in line with the avatar and
        // the cylinder either side of them.
        let profileRow = profile.isHidden ? 0 : Tokens.Metric.sidebarProfileRow
        profile.frame = NSRect(
            x: 0,
            y: SidebarUtilityBar.spaceStripTop + Tokens.Metric.sidebarProfileGap,
            width: bounds.width,
            height: profileRow
        ).integral
        let foot = profile.isHidden ? bar : profile.frame.maxY
        list.scrollView.frame = NSRect(
            x: 0,
            y: foot,
            width: bounds.width,
            height: max(gridTop - foot, 0)
        ).integral

        // §30.9's three borrowed views — the still, the `+` and the editor —
        // are framed against the page the column has just computed.
        spaces?.layoutPages()

        // Placed so its 8 pt hit strip is the sidebar's own inner 8 pt: hit
        // testing stops at a superview's bounds, so a handle centred on the
        // divider would have half a dead hit area. The drawn glyph still
        // overhangs into the §3.6 gap, which is where §3.7 wants it. Which edge
        // is "inner" is the one the page is on, so it follows the column.
        let handleWidth = Tokens.Metric.resizeHandle.width
        let hit = Tokens.Metric.resizeHandleHitWidth
        handle.frame = NSRect(
            x: sidebarEdge == .trailing
                ? bounds.minX - (handleWidth - hit) / 2
                : bounds.maxX - (handleWidth + hit) / 2,
            y: 0,
            width: handleWidth,
            height: bounds.height
        ).integral
    }
}
