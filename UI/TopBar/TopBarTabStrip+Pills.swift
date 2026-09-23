//
//  TopBarTabStrip+Pills.swift
//  Luna
//
//  §3.4's two row fills on §4's bar, and the pointer that moves them.
//
//  Two for the whole bar, never one per row, for the column's reason: a fill
//  that belongs to the bar can travel, and a selection that slides from one tab
//  to the next on §6's `selectedRowMove` spring reads as one thing moving
//  rather than two things blinking. They move exactly as the column's do —
//  `RowPillView.move(to:spec:)` is shared, so the two cannot drift apart.
//
//  Split out of `TopBarTabStrip` for its type body length, along the seam the
//  column already has (`TabListController+Pills`).
//

import AppKit

extension TopBarTabStrip {

    /// The two fills follow the rows. `animated: false` where the move is not
    /// the pill's own — a Space switch has replaced every row under them.
    func movePills(animated: Bool = true) {
        // §6.6: while a lift is up both stay parked. The lift carries §3.4's
        // selected pill itself, and a second one lying where the tab used to
        // be is a ghost that follows the drag along the bar.
        guard liftedID == nil else {
            for pill in [selectionPill, hoverPill] { pill.fade(to: 0) }
            return
        }
        let selected = activeID.flatMap { rows[$0] == nil ? nil : targets[$0] }
        place(selectionPill, at: selected, spec: animated ? Tokens.Motion.selectedRowMove : nil)
        let hovered = hoveredID.flatMap { $0 == activeID || rows[$0] == nil ? nil : targets[$0] }
        place(hoverPill, at: hovered, spec: animated ? Tokens.Motion.rowHover : nil)
    }

    /// How far the selected tab's page has been read — §3.4's band, on the
    /// selected pill, exactly as the column draws it. The hover pill never
    /// carries it: it is under a tab the reader is not on.
    func setScrollProgress(_ progress: Double?) {
        selectionPill.progress = progress.map { CGFloat($0) }
    }

    private func place(_ pill: RowPillView, at frame: NSRect?, spec: MotionSpec?) {
        guard let frame else {
            pill.fade(to: 0, animated: spec != nil)
            return
        }
        pill.move(to: frame, spec: spec)
    }

    /// The pointer arrived on a row or left it. The row's content changes with
    /// it — §3.4's close glyph is the pointer's, on the row it is on and no
    /// other — and the hover pill follows.
    func hover(_ id: UUID, inside: Bool) {
        let next = inside ? id : (hoveredID == id ? nil : hoveredID)
        guard next != hoveredID else { return }
        let previous = hoveredID
        hoveredID = next
        for changed in [previous, next].compactMap({ $0 }) {
            guard let row = rows[changed] else { continue }
            row.row.isHovered = changed == next
            if let tab = session.tab(changed) { row.configure(rowContent(for: tab)) }
        }
        movePills()
    }

    /// A press on a row, waiting to say what it is: a drag past §6.6's
    /// threshold hands the original press on, and a mouse-up before that is a
    /// click. The column's `TabListController.press`, on its side.
    func track(
        _ press: NSEvent,
        on view: NSView,
        onClick: (() -> Void)? = nil,
        onDrag: @escaping () -> Void
    ) {
        guard let window else { return }
        let start = view.convert(press.locationInWindow, from: nil)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = view.convert(next.locationInWindow, from: nil)
            guard next.type == .leftMouseDragged else {
                if view.bounds.contains(point) { onClick?() }
                return
            }
            guard abs(point.x - start.x) >= Tokens.Metric.dragThreshold
                || abs(point.y - start.y) >= Tokens.Metric.dragThreshold
            else { continue }
            onDrag()
            return
        }
    }
}
