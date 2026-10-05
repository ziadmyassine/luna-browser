//
//  BrowserSession+ManyTabs.swift
//  Luna
//
//  The verbs for several tabs at once — the ones marked in §3.4's list with ⌘-
//  and ⇧-click (`TabListController+Marking.swift`), dropped together or chosen
//  from the menu on any of them. Each is the one-tab verb applied in turn,
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
    func closeTabs(_ ids: [UUID]) {
        asOneUndo(String(localized: "Close Tabs")) {
            for id in ids.reversed() { closeTab(id) }
        }
    }

    /// §3.4a's menu for several marked tabs — the verbs above, bound to them.
    func tabMenuActions(for ids: [UUID]) -> TabMenu.ManyActions {
        TabMenu.ManyActions(
            pin: allowsPinning ? { [weak self] in
                guard let self else { return }
                let favorites = favorites(inSpace: activeSpaceID).count
                moveTabs(ids, to: SidebarDestination(kind: .essential, groupID: nil, index: favorites))
            } : nil,
            setGroup: { [weak self] group in self?.moveTabs(ids, toGroup: group) },
            newGroup: { [weak self] in
                self?.createGroup(name: BrowserSession.untitledGroupName, containing: ids)
            },
            close: { [weak self] in self?.closeTabs(ids) }
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
