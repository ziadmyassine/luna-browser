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
    func applyDisclosure(_ state: SidebarRowContent.Disclosure?) {
        guard let state else {
            chevron.isHidden = true
            return
        }
        chevron.isHidden = false
        chevron.configure(
            symbolName: state == .expanded ? "chevron.down" : "chevron.right",
            label: state == .expanded ? "Collapse Group" : "Expand Group",
            pointSize: Tokens.Metric.groupChevron
        )
    }

    func applyDropTarget() {
        outline.isHidden = !isDropTarget
        outline.layer?.borderColor = Tokens.Line.border.cgColor
        needsLayout = true
    }
}
