//
//  SidebarRowView+Group.swift
//  Luna
//
//  What §3.4b added to a sidebar row: the chevron that folds a group, the
//  hairline down the leading edge of its tabs, and the outline a lift aimed
//  into a folded one draws.
//
//  A row is still one class — a group header and a tab are the same 38 pt of
//  pitch with the same pill behind them, and §30.6's argument for `New Tab`
//  being a first-class row applies here too. This is only the part of it that
//  is about groups, split off because `SidebarRowView.swift` passed SwiftLint's
//  length limit and this is the piece with one subject.
//

import AppKit

extension SidebarRowView {

    /// §3.4b's chevron. It points down when the group is open and into the
    /// column when it is shut — rotated rather than swapped for a second symbol,
    /// so the two states are one shape that turns.
    ///
    /// A mark, not a control. What folds the group is the header, so this only
    /// says which way it is folded; it takes no press and is not in the row's
    /// hit test.
    func applyDisclosure(_ state: SidebarRowContent.Disclosure?) {
        guard let state else {
            chevron.isHidden = true
            return
        }
        chevron.isHidden = false
        chevron.image = NSImage(
            systemSymbolName: state == .expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.groupChevron,
            weight: .regular
        )
    }

    /// §3.4b's chevron, at the end of the folder's own name.
    ///
    /// After the name rather than before the icon, because the chevron belongs
    /// to the name and not to the column: leading it, it stood where every
    /// other row draws a favicon and pushed the folder's own icon out of that
    /// column, so a list of folders and tabs had two icon columns instead of
    /// one.
    ///
    /// Clamped, for the folder whose name is longer than the row: the name is
    /// already dissolving into `rowTitleFade` by then, and a chevron carried
    /// out past the pill's inner edge would be a glyph half off the column.
    func placeChevron(afterTitleEnding x: CGFloat) {
        let slot = Tokens.Metric.groupChevronSlot
        let limit = bounds.width - 2 * Tokens.Metric.rowInset - slot.width
        chevron.frame = NSRect(
            x: min(x + Tokens.Metric.groupChevronGap, max(limit, 0)),
            y: (bounds.height - slot.height) / 2,
            width: slot.width,
            height: slot.height
        ).pixelAligned
    }

    func applyDropTarget() {
        outline.isHidden = !isDropTarget
        outline.layer?.borderColor = Tokens.Line.border.cgColor
        needsLayout = true
    }
}
