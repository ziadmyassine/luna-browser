//
//  TabListController+Pills.swift
//  Luna
//
//  §3.4's two row fills — the selected one and the hovered one — and where they
//  stand.
//
//  There are two of them for the whole list, not one per row. A fill that
//  belonged to its row would have to appear and disappear as the selection
//  moved; two that belong to the list can travel, which is what §6's
//  `selectedRowMove` spring is for and what makes the selection read as one
//  thing moving rather than two things blinking. It is also what lets §6.6's
//  lift borrow the selected pill: there is one of it, so it can be somewhere
//  else for a while.
//
//  Split out of `TabListController.swift` when that file crossed SwiftLint's
//  400-line limit, and this is the half that came out because it is the half
//  with one subject. `selectionPill` and `hoverPill` are internal rather than
//  private only because Swift's `private` is file-scoped; nothing outside this
//  pair of files touches either.
//

import AppKit

extension TabListController {

    /// The two shared pills follow the rows instead of each row owning a fill.
    /// `animated: false` where the move is not the pill's own — a spring
    /// chasing a live resize drag, or a §6 Space switch that has replaced every
    /// row under them, arrives after the row it belongs to.
    func movePills(animated: Bool = true) {
        // §6.6: while a lift is up the list's two fills stay parked, because
        // the lift is carrying §3.4's selected pill itself, and a second one
        // lying in the row the tab came from is a ghost that follows the drag
        // down the column and back up again.
        //
        // Guarded here rather than at the call sites, and that is the whole
        // fix. `setPillsHidden(true)` parks the fills once; every later request
        // to move one brings them back, because `move(to:spec:)` ends by fading
        // to 1. A drag is when the list is re-laid most — the §3.3 grid opens
        // to a tile's height, §3.4b's rule comes out, the gap steps — and each
        // of those passes reaches `table.onLayout`, which lands here.
        guard !isDragging else { return }
        selectionPill.isFocused = table.window?.firstResponder === table
        let selected = table.selectedRow >= 0 ? table.selectedRow : nil
        place(selectionPill, at: selected, spec: animated ? Tokens.Motion.selectedRowMove : nil)
        // No folder header takes the hover pill, open or folded: §3.4b's plate
        // is its whole answer to the pointer, and a header lit on top of it
        // was two.
        let hovered = hoveredRow.flatMap {
            list.isSelectable($0) && $0 != selected && list.group(at: $0) == nil ? $0 : nil
        }
        place(hoverPill, at: hovered, spec: animated ? Tokens.Motion.rowHover : nil)
        placeGroupPlate(animated: animated)
    }

    /// §3.4b's plate round the folder the pointer is in — over its header, any
    /// of its tabs or the room under them. It stands where the pills it holds
    /// stand, so a folded folder's plate is exactly a tab's hover pill, and
    /// folding moves only the bottom edge.
    func groupPlateBox() -> NSRect? {
        guard let row = hoveredRow, row < table.numberOfRows else { return nil }
        var folder = list.group(at: row) ?? list.tab(at: row).flatMap { list.group(ofTab: $0.id) }
        if case let .groupEnd(id)? = list[row] { folder = list.group(id) }
        guard let folder else { return nil }
        return groupExtent(ofGroup: folder.id)
    }

    /// How far the selected tab's page has been read. Only the selected pill
    /// carries it; the hover pill is under a row the reader is not on.
    func setScrollProgress(_ progress: Double?) {
        selectionPill.progress = progress.map { CGFloat($0) }
    }

    /// Parks both row fills, or brings them back. §6.6's lift carries §3.4's
    /// selected pill itself, so while one is up the list's own would be a
    /// second highlight lying in the row's old place.
    ///
    /// Parking is only half of it: `movePills` is what keeps them parked, and
    /// it has to, because a dozen things ask for a pill move during a drag.
    func setPillsHidden(_ hidden: Bool) {
        guard hidden else {
            movePills()
            return
        }
        for pill in [selectionPill, hoverPill, groupPlate] { pill.fade(to: 0) }
    }

    /// Keeps the shared fills behind the row views AppKit keeps adding — the
    /// two pills, §3.4b's folder plate under them, and §6.6's box round a
    /// folder taking a drop.
    func sendPillsToBack() {
        for fill in [selectionPill, hoverPill, groupPlate, groupDrop] where fill.superview === table {
            table.addSubview(fill, positioned: .below, relativeTo: nil)
        }
    }

    /// The same folder growing or shrinking under the pointer — a fold, a tab
    /// closing — stretches its bottom edge in step with the rows sliding, on
    /// the clock `apply` gives them. Anything else, including a width change,
    /// is an ordinary move.
    ///
    /// The rows' layout pass lands here unanimated while they are still
    /// sliding; the plate is already standing where it is going by then, and
    /// placing it again would snap the stretch to its end.
    private func placeGroupPlate(animated: Bool) {
        let box = groupPlateBox(), shown = groupPlate.frame
        guard let box, groupPlate.alphaValue == 1,
              box.minX == shown.minX, box.minY == shown.minY, box.width == shown.width else {
            return place(groupPlate, in: box, spec: animated ? Tokens.Motion.rowHover : nil)
        }
        guard box.height != shown.height else { return }
        groupPlate.stretch(to: box, spec: Tokens.Motion.tabInsert)
    }

    private func place(_ pill: RowPillView, at row: Int?, spec: MotionSpec?) {
        place(pill, in: row.flatMap { $0 < table.numberOfRows ? pillBox(ofRow: $0) : nil }, spec: spec)
    }

    private func place(_ pill: RowPillView, in box: NSRect?, spec: MotionSpec?) {
        guard let box else {
            // Parked on the same terms it is moved on. A Space switch
            // reaches here twice with no spec — once as `reloadData` drops the
            // selection, once as the new one is applied — and a fill left
            // fading through both of them is the Space you came from showing
            // through the Space you went to: an empty glass pill, lying in a
            // list that no longer has that row in it.
            pill.fade(to: 0, animated: spec != nil)
            return
        }
        pill.move(to: box, spec: spec)
    }

    /// The fill's box for one row.
    ///
    /// `rowHeight` is pitch and `rowPillHeight` is paint, so the vertical inset
    /// is what stops two adjacent selected pills fusing into one slab.
    ///
    /// The leading edge follows §3.4b's indent. A tab inside a folder steps in
    /// by `groupIndent` and everything it draws steps in with it — a pill that
    /// stayed at the column's edge reached out past the folder's own header and
    /// made the row look like it belonged to the list rather than to the folder.
    func pillBox(ofRow row: Int) -> NSRect {
        var box = table.rect(ofRow: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset)
        // Read the same way `tabContent` reads it, not from `content(for:)` —
        // this runs on every pill move and that builds a whole row's worth of
        // state to answer one question.
        guard let tab = list.tab(at: row), list.group(ofTab: tab.id) != nil else { return box }
        box.origin.x += Tokens.Metric.groupIndent
        box.size.width -= Tokens.Metric.groupIndent + Tokens.Metric.groupMemberTrailingInset
        return box
    }
}
