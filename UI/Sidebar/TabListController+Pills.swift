//
//  TabListController+Pills.swift
//  Luna
//
//  §3.4's two row fills — the selected one and the hovered one — and where they
//  stand.
//
//  **There are two of them for the whole list, not one per row.** A fill that
//  belonged to its row would have to appear and disappear as the selection
//  moved; two that belong to the list can *travel*, which is what §6's
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
        selectionPill.isFocused = table.window?.firstResponder === table
        let selected = table.selectedRow >= 0 ? table.selectedRow : nil
        place(selectionPill, at: selected, spec: animated ? Tokens.Motion.selectedRowMove : nil)
        let hovered = hoveredRow.flatMap { list.isSelectable($0) && $0 != selected ? $0 : nil }
        place(hoverPill, at: hovered, spec: animated ? Tokens.Motion.rowHover : nil)
    }

    /// Parks both row fills, or brings them back. §6.6's lift carries §3.4's
    /// selected pill itself, so while one is up the list's own would be a
    /// second highlight lying in the row's old place.
    func setPillsHidden(_ hidden: Bool) {
        guard hidden else {
            movePills()
            return
        }
        for pill in [selectionPill, hoverPill] { pill.fade(to: 0) }
    }

    /// Keeps the two shared pills behind the row views AppKit keeps adding.
    func sendPillsToBack() {
        for pill in [selectionPill, hoverPill] where pill.superview === table {
            table.addSubview(pill, positioned: .below, relativeTo: nil)
        }
    }

    private func place(_ pill: RowPillView, at row: Int?, spec: MotionSpec?) {
        guard let row, row < table.numberOfRows else {
            // **Parked on the same terms it is moved on.** A Space switch
            // reaches here twice with no spec — once as `reloadData` drops the
            // selection, once as the new one is applied — and a fill left
            // fading through both of them is the Space you came from showing
            // through the Space you went to: an empty glass pill, lying in a
            // list that no longer has that row in it.
            pill.fade(to: 0, animated: spec != nil)
            return
        }
        // `rowHeight` is pitch; `rowPillHeight` is paint. Insetting vertically
        // is what stops two adjacent selected pills fusing into one slab.
        pill.move(
            to: table.rect(ofRow: row).insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.rowPillInset),
            spec: spec
        )
    }
}
