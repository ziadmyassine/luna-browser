//
//  TabListController+Pills.swift
//  Luna
//
//  §3.4's two row fills — the selected one and the hovered one — and where they
//  stand. Two for the whole list, not one per row: fills that belong to the list
//  can travel on §6's `selectedRowMove` spring, so the selection reads as one
//  thing moving rather than two blinking, and §6.6's lift can borrow the one
//  selected pill for a while.
//
//  Split out of `TabListController.swift` for SwiftLint's 400-line limit, as the
//  half with one subject. `selectionPill` and `hoverPill` are internal only
//  because Swift's `private` is file-scoped; nothing outside the pair touches them.
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
        // lying in the row the tab came from is a ghost that follows the drag.
        //
        // Guarded here rather than at the call sites: `move(to:spec:)` ends by
        // fading to 1, so any later move un-parks them, and a drag is when the
        // list is re-laid most — the §3.3 grid opens, §3.4b's rule comes out,
        // the gap steps — each pass reaching `table.onLayout`, which lands here.
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
        placePlate(groupPlate, in: groupPlateBox(), animated: animated)
        placeControlPlates(animated: animated)
        placeTabGlows(animated: animated)
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
        for pill in [selectionPill, hoverPill, groupPlate] + controlPlates.values + tabGlows.values { pill.fade(to: 0) }
    }

    /// Keeps the shared fills behind the row views AppKit keeps adding — the
    /// two pills, a connected Luna Control folder's outline, §3.4b's folder
    /// plate under them, and §6.6's box round a folder taking a drop. The
    /// outline lies over the hover plate so its colour is not drawn over, and
    /// a working tab's outline over the pills, whose fill would cover its rim.
    func sendPillsToBack() {
        let fills = Array(tabGlows.values) + [selectionPill, hoverPill] + Array(controlPlates.values)
            + [groupPlate, groupDrop, dropMark]
        for fill in fills where fill.superview === table {
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
    private func placePlate(_ plate: RowPillView, in box: NSRect?, animated: Bool) {
        let shown = plate.frame
        guard let box, plate.alphaValue == 1,
              box.minX == shown.minX, box.minY == shown.minY, box.width == shown.width else {
            return place(plate, in: box, spec: animated ? Tokens.Motion.rowHover : nil)
        }
        guard box.height != shown.height else { return }
        plate.stretch(to: box, spec: Tokens.Motion.tabInsert)
    }

    /// The folder plate, kept up round every Luna Control folder in its app's
    /// colour, so the folder says whose it is without the pointer over it.
    private func placeControlPlates(animated: Bool) {
        // Gone, not parked: a folder that was closed, or is in another Space,
        // has nothing for an outline to stand round, and a parked one left
        // lying in the table was one stray pass away from showing again.
        for (id, plate) in controlPlates where controlFaces[id] == nil || list.row(ofGroup: id) == nil {
            controlPlates[id] = nil
            retire(plate)
        }
        // A tinted plate no folder or tab owns any more goes as well. One was
        // left in the column after Close Folder and Tabs, which no test here
        // reproduced; whatever let it go astray, it cannot outlast this pass.
        let owned = Set((Array(controlPlates.values) + Array(tabGlows.values)).map(ObjectIdentifier.init))
        for case let stray as RowPillView in table.subviews
            where stray.tint != nil && stray.alphaValue > 0 && !owned.contains(ObjectIdentifier(stray)) {
            retire(stray)
        }
        for (id, face) in controlFaces {
            guard let box = groupExtent(ofGroup: id) else { continue }
            let plate = controlPlates[id] ?? makeControlPlate(id)
            plate.tint = Tokens.Agent.tint(forApp: face.appID)
            plate.isWorking = controlledGroupIDs.contains(id)
            placePlate(plate, in: box, animated: animated)
        }
    }

    /// The folder's rim and spark round each tab an agent is acting on, so
    /// the tab it is using is as plain as the folder it is working in. A tab
    /// in a folded folder has no row, and the folder's own spark stands for it.
    private func placeTabGlows(animated: Bool) {
        for (id, glow) in tabGlows where workingTabs[id] == nil || list.row(of: id) == nil {
            tabGlows[id] = nil
            glow.isWorking = false
            Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
                glow.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { glow.removeFromSuperview() }
            }
        }
        for (id, face) in workingTabs {
            guard let row = list.row(of: id), row < table.numberOfRows else { continue }
            let glow = tabGlows[id] ?? {
                let made = RowPillView(role: .working)
                made.alphaValue = 0
                table.addSubview(made)
                tabGlows[id] = made
                sendPillsToBack()
                return made
            }()
            glow.tint = Tokens.Agent.tint(forApp: face.appID)
            glow.isWorking = true
            place(glow, in: pillBox(ofRow: row), spec: animated ? Tokens.Motion.rowHover : nil)
        }
    }

    /// Fades a plate out of the column, spark first, and takes it off.
    private func retire(_ plate: RowPillView) {
        plate.isWorking = false
        Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
            plate.animator().alphaValue = 0
        } completion: {
            MainActor.assumeIsolated { plate.removeFromSuperview() }
        }
    }

    private func makeControlPlate(_ id: UUID) -> RowPillView {
        let plate = RowPillView(role: .folder)
        plate.alphaValue = 0
        table.addSubview(plate)
        controlPlates[id] = plate
        sendPillsToBack()
        return plate
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
    /// `tabRowHeight` is pitch and `rowPillHeight` is paint, so the vertical inset
    /// is what stops two adjacent selected pills fusing into one slab.
    ///
    /// The leading edge follows §3.4b's indent. A tab inside a folder steps in
    /// by `groupIndent` and everything it draws steps in with it — a pill that
    /// stayed at the column's edge reached out past the folder's own header and
    /// made the row look like it belonged to the list rather than to the folder.
    func pillBox(ofRow row: Int) -> NSRect {
        var box = table.rect(ofRow: row)
            .insetBy(dx: Tokens.Metric.rowInset, dy: Tokens.Metric.tabRowPillInset)
        // Read the same way `tabContent` reads it, not from `content(for:)` —
        // this runs on every pill move and that builds a whole row's worth of
        // state to answer one question.
        guard let tab = list.tab(at: row), list.group(ofTab: tab.id) != nil else { return box }
        box.origin.x += Tokens.Metric.groupIndent
        box.size.width -= Tokens.Metric.groupIndent + Tokens.Metric.groupMemberTrailingInset
        return box
    }
}
