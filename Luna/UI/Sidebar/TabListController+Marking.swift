//
//  TabListController+Marking.swift
//  Luna
//
//  Several tabs chosen at once (§3.4): ⌘-click adds a tab to the selection or
//  takes it out, ⇧-click takes the run from the last one marked. The marked
//  tabs then move together — §6.6's lift carries them all — and the menu on
//  any of them acts on all of them.
//
//  The selected tab is always one of them, as in Safari: marking starts from
//  it, and going to a tab that is not marked lets the marks go. Each marked
//  tab but that one wears a pill of its own; the selected one has §3.4's.
//

import AppKit

extension TabListController {

    /// The marked tabs in row order, which is the order they move in.
    var markedInOrder: [UUID] {
        list.listed.map(\.id).filter(markedTabIDs.contains)
    }

    /// ⌘- and ⇧-click on tab `id`. Returns false for a plain press, which is
    /// the list's own business.
    func mark(_ id: UUID, for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            toggleMark(id)
        } else if modifiers.contains(.shift) {
            markRun(to: id)
        } else {
            return false
        }
        movePills()
        return true
    }

    /// A plain press on a tab row. Selected on the press, exactly as a table
    /// selects: the page is up before the gesture is over. The lift takes the
    /// rest of it — every marked tab, when this is one of them — and a press
    /// that was only a click lets the marks go.
    func press(tab id: UUID, row: Int, event: NSEvent) {
        if !markedTabIDs.contains(id) { clearMarks() }
        table.selectRowIndexes([row], byExtendingSelection: false)
        if onTabPress?(row, event) != true { clearMarks() }
    }

    /// Delete on the list: the selected tab, or every marked one.
    func closeSelected() -> Bool {
        guard case let .tab(id)? = list[table.selectedRow] else { return false }
        if markedTabIDs.count > 1 {
            manyMenuActions?(markedInOrder)?.close()
        } else {
            onCloseTab?(id)
        }
        return true
    }

    /// Escape lets the marks go, and is not the list's to take when there are none.
    func clearMarksFromKeyboard() -> Bool {
        guard !markedTabIDs.isEmpty else { return false }
        clearMarks()
        return true
    }

    func clearMarks() {
        guard !markedTabIDs.isEmpty else { return }
        markedTabIDs = []
        movePills()
    }

    /// Drops marks on tabs the list no longer shows — closed, or in a folder
    /// that folded. Not while a lift is up: the tabs it carries are out of the
    /// list for the length of the gesture and are still marked.
    func pruneMarks() {
        guard carriedIDs.isEmpty, !markedTabIDs.isEmpty else { return }
        markedTabIDs.formIntersection(list.listed.map(\.id))
        if markedTabIDs.count < 2 { markedTabIDs = [] }
    }

    private var selectedListedTab: UUID? {
        activeTabID.flatMap { list.row(of: $0) != nil ? $0 : nil }
    }

    /// The selected tab cannot be unmarked: it is the one on screen.
    private func toggleMark(_ id: UUID) {
        if markedTabIDs.isEmpty, let selected = selectedListedTab { markedTabIDs = [selected] }
        if markedTabIDs.contains(id) {
            guard id != selectedListedTab else { return }
            markedTabIDs.remove(id)
        } else {
            markedTabIDs.insert(id)
        }
        if markedTabIDs.count < 2 { markedTabIDs = [] }
    }

    /// Every tab between the selected one and `id`, both included.
    private func markRun(to id: UUID) {
        let ids = list.listed.map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        let start = selectedListedTab.flatMap { ids.firstIndex(of: $0) } ?? end
        markedTabIDs = Set(ids[min(start, end) ... max(start, end)])
        if markedTabIDs.count < 2 { markedTabIDs = [] }
    }

    // MARK: - Pills

    /// One selected pill per marked tab but the selected one, which has §3.4's.
    /// Made and retired with the marks, like `tabGlows`.
    func placeMarkPills(animated: Bool) {
        let selected = table.selectedRow >= 0 ? list.tab(at: table.selectedRow)?.id : nil
        for (id, pill) in markPills where !markedTabIDs.contains(id) || id == selected || list.row(of: id) == nil {
            markPills[id] = nil
            Tokens.Motion.animate(Tokens.Motion.rowHover) { _ in
                pill.animator().alphaValue = 0
            } completion: {
                MainActor.assumeIsolated { pill.removeFromSuperview() }
            }
        }
        for id in markedTabIDs where id != selected {
            guard let row = list.row(of: id), row < table.numberOfRows else { continue }
            let pill = markPills[id] ?? {
                let made = RowPillView(role: .selected)
                made.alphaValue = 0
                table.addSubview(made)
                markPills[id] = made
                sendPillsToBack()
                return made
            }()
            let box = pillBox(ofRow: row)
            guard pill.frame != box || pill.alphaValue != 1 else { continue }
            pill.move(to: box, spec: animated ? Tokens.Motion.rowHover : nil)
        }
    }
}
