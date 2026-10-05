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

    /// A Luna Control folder's own icon, which it shows only for a client
    /// Luna has no icon for. Also how a folder from an earlier launch is told
    /// apart from one the user made and named the same.
    static let controlFolderSymbol = "sparkles"

    /// An agent session's folder in `space` (the active Space unless said):
    /// the one it had, else a Luna Control folder there already called by its
    /// name that is not in `excluding` (another session's), else a new one at
    /// the head of today's tabs. Never one in another Space — a tab moved into
    /// it would change Space with it.
    ///
    /// No undo entry and no name field, unlike `createGroup`: nothing the user
    /// did made it, so there is nothing for `⌘Z` to take back and no name to
    /// ask for. The same goes for renaming and filling it, below.
    func controlFolder(named name: String, previously id: UUID?, excluding: Set<UUID> = [], in space: UUID? = nil) -> TabGroup {
        let space = space ?? activeSpaceID
        if let id, let group = list.group(id), group.spaceID == space { return group }
        if let group = (list.groupsBySpace[space] ?? []).first(where: {
            $0.name == name && $0.symbolName == Self.controlFolderSymbol && !excluding.contains($0.id)
        }) { return group }
        let group = TabGroup(spaceID: space, name: name, symbolName: Self.controlFolderSymbol, kind: .today)
        persistAll(list.insertGroup(group, at: openIndex(for: .today)))
        notifyChange()
        return group
    }

    func renameControlFolder(_ id: UUID, to name: String) {
        undoManager.disableUndoRegistration()
        renameGroup(id, to: name)
        undoManager.enableUndoRegistration()
    }

    func moveControlledTab(_ id: UUID, into group: UUID) {
        undoManager.disableUndoRegistration()
        moveTab(id, toGroup: group)
        undoManager.enableUndoRegistration()
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

    func setControlled(_ controlled: Bool, tab id: UUID, face: ControlFace) {
        let old = controlledTabs[id]
        controlledTabs[id] = controlled ? face : nil
        if controlledTabs[id] != old { notifyChange() }
    }

    /// The icon a Luna Control folder wears instead of its own while it is
    /// waiting for the user, paused or stopped.
    func setControlBadges(_ badges: [UUID: String]) {
        guard badges != controlBadges else { return }
        controlBadges = badges
        notifyChange()
    }

    func setControlNeedsYou(_ tabs: Set<UUID>) {
        guard tabs != controlNeedsYouTabs else { return }
        controlNeedsYouTabs = tabs
        notifyChange()
    }

    func setControlFaces(_ faces: [UUID: ControlFace]) {
        guard faces != controlFaces else { return }
        controlFaces = faces
        notifyChange()
    }
}

/// What a Luna Control folder shows of the app it belongs to: that app's
/// icon in place of its own, and an outline in the app's colour
/// (`Tokens.Agent`) that glows while the app is working in the folder.
struct ControlFace: Equatable {
    /// `ControlApp.id`, or nil for a client Luna knows nothing about, which
    /// keeps the folder's own icon and a neutral outline.
    var appID: String?
}
