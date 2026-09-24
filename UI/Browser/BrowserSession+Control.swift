//
//  BrowserSession+Control.swift
//  Luna
//
//  The session's side of Luna Control (docs/LUNA-CONTROL.md): the folder a
//  client's tabs go into, opening a tab there without selecting it, and
//  waking a tab to act on without showing it. `ControlService` decides what
//  to do; this is the part that has to touch the tab list.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// The client's folder in the active Space: the one it had, else one
    /// already called by its name, else a new one at the head of today's tabs.
    ///
    /// No undo entry and no name field, unlike `createGroup`: nothing the user
    /// did made it, so there is nothing for `⌘Z` to take back and no name to
    /// ask for.
    func controlFolder(named name: String, previously id: UUID?) -> TabGroup {
        if let id, let group = list.group(id), group.spaceID == activeSpaceID { return group }
        if let group = groups.first(where: { $0.name == name }) { return group }
        let group = TabGroup(spaceID: activeSpaceID, name: name, symbolName: "sparkles", kind: .today)
        persistAll(list.insertGroup(group, at: openIndex(for: .today)))
        notifyChange()
        return group
    }

    /// A tab at the end of `group`, loading `url`, with a web view but not
    /// selected: the user's window keeps showing what it was showing.
    @discardableResult
    func openControlledTab(url: URL?, in group: TabGroup) -> UUID {
        let tab = Tab(
            spaceID: group.spaceID,
            kind: group.kind,
            url: url ?? Self.blankPage,
            order: list.nextOrder(kind: group.kind, in: group.spaceID),
            groupID: group.id
        )
        persistAll(list.insert(Self.keepingWhatItIsFor(tab, wasKept: false)))
        ensureController(for: tab).activate()
        notifyChange()
        return tab.id
    }

    /// The tab's controller with a live web view, waking it if §19.2 put it to
    /// sleep. Marks it used now, which is what keeps the lifecycle sweep off a
    /// tab an agent is working in; it is not promoted, so the user's own
    /// recent tabs keep their places in the live budget.
    func wakeForControl(_ id: UUID) -> TabController? {
        guard var tab = list.tab(id) else { return nil }
        tab.lastActiveAt = Date()
        tab.isDormant = false
        write(tab)
        let controller = ensureController(for: tab)
        controller.activate()
        return controller
    }

    /// Closes a tab an agent opened, off the user's undo stack for the reason
    /// the auto-archive sweep keeps off it: the stack is what the user did.
    func closeControlledTab(_ id: UUID) {
        undoManager.disableUndoRegistration()
        closeTab(id)
        undoManager.enableUndoRegistration()
    }

    func setControlled(_ controlled: Bool, group id: UUID) {
        let changed = controlled ? controlledGroupIDs.insert(id).inserted : controlledGroupIDs.remove(id) != nil
        if changed { notifyChange() }
    }
}
