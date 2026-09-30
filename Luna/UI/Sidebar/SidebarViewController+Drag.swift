//
//  SidebarViewController+Drag.swift
//  Luna
//
//  §6.6's lift, wired. The third piece of `SidebarViewController`, split off
//  for the reason `+Layout` was: the controller crossed SwiftLint's 400-line
//  limit, and this is a self-contained part of it — one gesture, three landing
//  places, and the session calls each landing makes.
//
//  Nothing moved on the way across.
//

import AppKit
import BrowserKit

extension SidebarViewController {

    /// §6.6's lift. Both ends of the sidebar hand their press over to it — a
    /// list row and a grid tile are the same gesture wearing two shapes — and
    /// exactly one of these three fires on release.
    func wireDrag() {
        let controller = SidebarTabDragController(host: view, grid: essentials, list: list, utility: utility)
        // §5.6 keeps nothing, so §3.3's grid is not one of the three landings
        // this gesture has — see `BrowserSession.allowsPinning`.
        controller.allowsPinning = session.allowsPinning
        // Picking a tab up is choosing it, wherever it is put down: a drop
        // that left the previous page on screen made the thing under the hand
        // look like it belonged to something else. A row does this without
        // being asked — the press selects before the lift is off the ground
        // (`TabListController.press`) — but a tile's press goes straight to the
        // lift and its `onActivate` never fires, so the drops say it instead.
        // Escape and a §3.5 Space dot are the two that are not a landing.
        controller.onDropInList = { [weak self] id, landing, wasPinned in
            guard let self else { return }
            // A tab filed into a shut folder opens it. The drop is the one
            // moment the user is asking where that tab has gone, and a folder
            // that swallows it and stays shut answers by making the row
            // disappear. Before the reorder, so the list arrives at its new
            // shape once rather than opening a step after the row lands.
            if let folder = landing.groupID { session.setGroupCollapsed(false, forGroup: folder) }
            session.reorderTab(id, to: landing.index, kind: landing.kind, group: landing.groupID)
            // Unpinning does not wake a page on its own (§19.2), so this is
            // also what loads it.
            if wasPinned { activateTab(id) }
        }
        // §3.4b: a group carried across the rule takes its tabs with it, which
        // is `moveGroup`'s whole job — nothing here has to say so twice.
        controller.onDropGroup = { [weak self] id, kind, index in
            self?.session.moveGroup(id, to: index, kind: kind)
        }
        controller.onDropInEssentials = { [weak self] id, index, wasPinned in
            guard let self else { return }
            // Two different verbs for one landing place. A tile moving
            // between slots is a reorder inside the Essentials section; a row
            // arriving is a pin, which also puts its page away (§19.2), and
            // `pinTab` refuses a tab that is already pinned.
            if wasPinned {
                // Selected first, for `pinTab(selecting:)`'s reason: §19.2
                // keeps a pinned tab's page put away, and this is what loads it.
                activateTab(id)
                session.reorderTab(id, to: index, kind: .essential)
            } else {
                session.pinTab(id, at: index, selecting: true)
            }
        }
        controller.onDropOnSpace = { [weak self] id, space in
            self?.session.moveTab(id, toSpace: space)
        }
        list.onTabPress = { [weak controller] row, event in controller?.track(row: row, event: event) ?? false }
        essentials.onDragTile = { [weak controller] id, tile, event in
            controller?.track(essential: id, from: tile, event: event)
        }
        drag = controller
    }
}
