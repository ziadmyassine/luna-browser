//
//  HistoryListView+Marks.swift
//  Luna
//
//  Marking several pages to delete together (§11.3): ⌘-click one, ⇧-click a
//  run, ⌘A for all of them. A plain click still opens the page, as it does in
//  the Command Bar; marking is what the modifiers are for.
//
//  A marked row wears the selected pill where it stands, and the pointer gets
//  the hover pill, so "marked" and "under the pointer" stay two different
//  things while both are on screen. With nothing marked the list is back to
//  its one sliding pill.
//

import AppKit

extension HistoryListView {

    func click(_ entry: HistoryEntry, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if markedIDs.remove(entry.id) == nil { markedIDs.insert(entry.id) }
            anchorID = entry.id
        } else if modifiers.contains(.shift) {
            markRun(to: entry.id)
        } else {
            onActivate?(entry)
            return
        }
        applySelection(animated: true)
    }

    /// Every page from the anchor to `id`, added to what is marked. With no
    /// anchor yet the run starts at the highlighted page, which is where the
    /// eye already is.
    private func markRun(to id: UUID) {
        let ids = entries.map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        let start = (anchorID ?? selectedID).flatMap { ids.firstIndex(of: $0) } ?? end
        markedIDs.formUnion(ids[min(start, end)...max(start, end)])
        anchorID = id
    }

    /// `⌘A`: every page the list holds — the whole list, or everything the
    /// search found.
    func markAll() {
        markedIDs = Set(entries.map(\.id))
        applySelection(animated: true)
    }

    /// What a right-click on `entry` acts on: everything marked when it is
    /// among the marked, otherwise that row alone.
    func pages(aimedAt entry: HistoryEntry) -> [HistoryEntry] {
        guard markedIDs.contains(entry.id) else { return [entry] }
        return entries.filter { markedIDs.contains($0.id) }
    }

    /// `⌫`, `⌦` and `⌘⌫` from the filter field. Returns false when the key is
    /// the field's to edit the query with.
    ///
    /// With rows marked every one of them deletes the marked pages. With none,
    /// only `⌘⌫` deletes, and it deletes the highlighted page: a plain `⌫` in
    /// a search field is a typo being fixed, and one too many must not cost a
    /// page of history.
    func deleteKey(command: Bool) -> Bool {
        if !markedIDs.isEmpty {
            onDelete?(entries.filter { markedIDs.contains($0.id) })
            return true
        }
        guard command, let entry = entries.first(where: { $0.id == selectedID }) else { return false }
        onDelete?([entry])
        return true
    }

    // MARK: - Pills

    /// One pill for the whole list, standing behind the rows inside the table's
    /// own document view — so it scrolls with the rows for free, and a scroll
    /// costs it nothing. While rows are marked, a pill per marked row and the
    /// hover pill under the pointer.
    func movePills(animated: Bool) {
        let marking = !markedIDs.isEmpty
        if marking {
            selection.fade(to: 0, animated: animated)
            let pointer = selectedID.flatMap { markedIDs.contains($0) ? nil : pillBox(of: $0) }
            place(hover, in: pointer, spec: animated ? Tokens.Motion.rowHover : nil)
        } else {
            hover.fade(to: 0, animated: animated)
            place(selection, in: pillBox(of: selectedID), spec: animated ? Tokens.Motion.selectedRowMove : nil)
        }
        placeMarkPills(animated: animated)
    }

    /// Each marked row's pill lands on its row rather than travelling to it:
    /// marking a second row is a second thing selected, not the first one
    /// moving.
    private func placeMarkPills(animated: Bool) {
        for (id, pill) in markPills where !markedIDs.contains(id) || rowOfEntry[id] == nil {
            markPills[id] = nil
            pill.removeFromSuperview()
        }
        for id in markedIDs {
            guard let box = pillBox(of: id) else { continue }
            if let pill = markPills[id] {
                pill.move(to: box, spec: nil)
                continue
            }
            // A new mark fades up on its row, on the hover wash's timing.
            let pill = RowPillView(role: .selected)
            pill.fade(to: 0, animated: false)
            table.addSubview(pill, positioned: .below, relativeTo: nil)
            markPills[id] = pill
            Tokens.Motion.immediately { pill.frame = box }
            pill.fade(to: 1, animated: animated)
        }
    }

    private func place(_ pill: RowPillView, in box: NSRect?, spec: MotionSpec?) {
        guard let box else { return pill.fade(to: 0, animated: spec != nil) }
        pill.move(to: box, spec: spec)
    }
}
