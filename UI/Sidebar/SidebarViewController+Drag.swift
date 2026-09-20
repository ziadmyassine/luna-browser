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
        // **Picking a tab up is choosing it**, wherever it is put down: a drop
        // that left the previous page on screen made the thing under the hand
        // look like it belonged to something else. A row does this without
        // being asked — the press selects before the lift is off the ground
        // (`TabListController.press`) — but a tile's press goes straight to the
        // lift and its `onActivate` never fires, so the drops say it instead.
        // Escape and a §3.5 Space dot are the two that are not a landing.
        controller.onDropInList = { [weak self] id, kind, index, wasPinned in
            guard let self else { return }
            session.reorderTab(id, to: index, kind: kind)
            // Unpinning does not wake a page on its own (§19.2), so this is
            // also what loads it.
            if wasPinned { session.activateTab(id) }
        }
        controller.onDropInEssentials = { [weak self] id, index, wasPinned in
            guard let self else { return }
            // **Two different verbs for one landing place.** A tile moving
            // between slots is a reorder inside the Essentials section; a row
            // arriving is a *pin*, which also puts its page away (§19.2), and
            // `pinTab` refuses a tab that is already pinned.
            if wasPinned {
                // Selected first, for `pinTab(selecting:)`'s reason: §19.2
                // keeps a pinned tab's page put away, and this is what loads it.
                session.activateTab(id)
                session.reorderTab(id, to: index, kind: .essential)
            } else {
                session.pinTab(id, at: index, selecting: true)
            }
        }
        controller.onDropOnSpace = { [weak self] id, space in
            self?.session.moveTab(id, toSpace: space)
        }
        list.onTabPress = { [weak controller] row, event in controller?.track(row: row, event: event) }
        essentials.onDragTile = { [weak controller] id, tile, event in
            controller?.track(essential: id, from: tile, event: event)
        }
        drag = controller
    }
}
