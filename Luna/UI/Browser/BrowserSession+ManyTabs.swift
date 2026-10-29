//
//  BrowserSession+ManyTabs.swift
//  Luna
//
//  The verbs for several tabs at once — the ones marked in §3.4's list with ⌘-
//  and ⇧-click (`TabListController+Marking.swift`), dropped together or chosen
//  from the menu on any of them — and §3.4a's two that close the day's tabs
//  around one or several. Each is the one-tab verb applied in turn,
//  inside one undo group, so ⌘Z puts them all back at once.
//

import BrowserKit
import Foundation

extension BrowserSession {

    /// §6.6's drop for several tabs: they land side by side at `landing`, in
    /// the order given, wherever each of them came from.
    ///
    /// `landing.index` counts the run without any of them — the list the drop
    /// was aimed at had them all out of it. Each tab is put in front of the
    /// first one of the others that stood at that index, so the ones already
    /// moved and the ones still to move never push the place along.
    func moveTabs(_ ids: [UUID], to landing: SidebarDestination) {
        let moving = ids.filter { list.tab($0) != nil }
        guard !moving.isEmpty else { return }
        asOneUndo(String(localized: "Move Tabs")) {
            if let folder = landing.groupID { setGroupCollapsed(false, forGroup: folder) }
            // The folder tier holds folders only (`reorderTab`), so tabs dropped
            // loose up there are one new folder, not one each.
            if landing.kind == .pinned, landing.groupID == nil {
                createGroup(name: Self.untitledGroupName, kind: .pinned, containing: moving, at: landing.index)
                return
            }
            let rest = run(of: landing).filter { !moving.contains($0) }
            let anchor = rest.indices.contains(landing.index) ? rest[landing.index] : nil
            for id in moving {
                let others = run(of: landing).filter { $0 != id }
                let index = anchor.flatMap { others.firstIndex(of: $0) } ?? others.count
                if landing.kind == .essential, list.tab(id)?.kind != .essential {
                    pinTab(id, at: index)
                } else {
                    reorderTab(id, to: index, kind: landing.kind, group: landing.groupID)
                }
            }
        }
    }

    /// Several tabs into a folder, at its end, or — with nil — out of the
    /// folders they are in.
    func moveTabs(_ ids: [UUID], toGroup groupID: UUID?) {
        guard let groupID, let group = list.group(groupID) else {
            asOneUndo(String(localized: "Remove from Folder")) {
                for id in ids { moveTab(id, toGroup: nil) }
            }
            return
        }
        let moving = ids.filter { list.tab($0).map { $0.kind != .essential && $0.groupID != groupID } ?? false }
        let staying = list.members(ofGroup: groupID).filter { !moving.contains($0.id) }.count
        moveTabs(moving, to: SidebarDestination(kind: group.kind, groupID: groupID, index: staying))
    }

    func moveTabs(_ ids: [UUID], toSpace spaceID: UUID) {
        asOneUndo(String(localized: "Move Tabs")) {
            for id in ids { moveTab(id, toSpace: spaceID) }
        }
    }

    /// Closed from the last up, so the selection that each close hands on
    /// moves toward the tabs above rather than onto the next one to go.
    func closeTabs(_ ids: [UUID], named name: String = String(localized: "Close Tabs")) {
        asOneUndo(name) {
            for id in ids.reversed() { closeTab(id) }
        }
    }

    // MARK: - Close Other Tabs, Close Tabs Below (§3.4a)

    /// The day's tabs in `ids`' Space other than `ids` — `closableTabs`' rule,
    /// so a tile or a saved row is never one of them.
    func otherTabs(than ids: [UUID]) -> [UUID] {
        closable(in: rows(around: ids), besides: ids)
    }

    /// The same, drawn below the last of `ids`.
    func tabsBelow(_ ids: [UUID]) -> [UUID] {
        let rows = rows(around: ids)
        guard let last = rows.lastIndex(where: { ids.contains($0.id) }) else { return [] }
        return closable(in: Array(rows[(last + 1)...]), besides: ids)
    }

    func closeOtherTabs(than ids: [UUID]) {
        close(otherTabs(than: ids), around: ids, named: String(localized: "Close Other Tabs"))
    }

    func closeTabsBelow(_ ids: [UUID]) {
        close(tabsBelow(ids), around: ids, named: String(localized: "Close Tabs Below"))
    }

    /// §3.4's rows: the one-tab menu with the two that close around it. A tile
    /// and §4's strip keep `tabMenuActions(for:)`: every tab of the day is
    /// drawn after a tile, so there the two would be one item twice, and the
    /// strip has no below.
    func listTabMenuActions(for id: UUID) -> TabMenu.Actions {
        var actions = tabMenuActions(for: id)
        (actions.closeOthers, actions.closeBelow) = closeAround([id])
        return actions
    }

    /// The menu was opened on `ids` to keep them, so the one on screen is one
    /// of them when the closing is done. Without this, each close hands the
    /// selection on (`rowBelow`) and it lands wherever the last one left it.
    private func close(_ doomed: [UUID], around ids: [UUID], named name: String) {
        guard !doomed.isEmpty else { return }
        if let active = activeTabID, doomed.contains(active), let first = ids.first { activateTab(first) }
        closeTabs(doomed, named: name)
        PageToast.archived(doomed.count).show(in: hostWindow)
    }

    /// Nil for an item that would close nothing, so the menu leaves it out.
    private func closeAround(_ ids: [UUID]) -> (others: (() -> Void)?, below: (() -> Void)?) {
        (
            otherTabs(than: ids).isEmpty ? nil : { [weak self] in self?.closeOtherTabs(than: ids) },
            tabsBelow(ids).isEmpty ? nil : { [weak self] in self?.closeTabsBelow(ids) }
        )
    }

    private func rows(around ids: [UUID]) -> [Tab] {
        ids.first.flatMap { list.tab($0)?.spaceID }.map { list[$0] } ?? []
    }

    private func closable(in rows: [Tab], besides ids: [UUID]) -> [UUID] {
        rows.filter { $0.kind == .today && !ids.contains($0.id) }.map(\.id)
    }

    /// §3.4a's menu for several marked tabs — the verbs above, bound to them.
    func tabMenuActions(for ids: [UUID]) -> TabMenu.ManyActions {
        let around = closeAround(ids)
        return TabMenu.ManyActions(
            pin: allowsPinning ? { [weak self] in
                guard let self else { return }
                let favorites = favorites(inSpace: activeSpaceID).count
                moveTabs(ids, to: SidebarDestination(kind: .essential, groupID: nil, index: favorites))
            } : nil,
            setGroup: { [weak self] group in self?.moveTabs(ids, toGroup: group) },
            newGroup: { [weak self] in
                self?.createGroup(name: BrowserSession.untitledGroupName, containing: ids)
            },
            close: { [weak self] in self?.closeTabs(ids) },
            closeOthers: around.others,
            closeBelow: around.below
        )
    }

    /// The ids in the run `landing` names — a folder's tabs, §3.3's tiles, or
    /// a tier's top-level slots — in order.
    private func run(of landing: SidebarDestination) -> [UUID] {
        if let group = landing.groupID { return list.members(ofGroup: group).map(\.id) }
        if landing.kind == .essential { return favorites(inSpace: activeSpaceID).map(\.id) }
        return list.slots(inSpace: activeSpaceID, kind: landing.kind).map(\.id)
    }

    private func asOneUndo(_ name: String, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
        undoManager.setActionName(name)
    }
}
