//
//  TopBarView+Drag.swift
//  Luna
//
//  §6.6's lift on §4's bar, wired: the gesture is `TopBarTabDragController`'s,
//  and the session calls each landing makes are here — the same calls the
//  column's `SidebarViewController+Drag` makes for the same landings, so a tab
//  moved on the bar and a tab moved in the column end up in the same place.
//
//  Its own file because `TopBarView` is at SwiftLint's length limit, and this
//  is a self-contained part of it.
//

import AppKit
import BrowserKit

extension TopBarView {

    func wireDrag() {
        let controller = TopBarTabDragController(host: self, strip: strip, spaces: spacePill)
        controller.allowsPinning = session.allowsPinning
        controller.onDropTab = { [weak self] id, landing in
            guard let self, let tab = session.tab(id) else { return }
            // A tab filed into a shut folder opens it: the drop is the one
            // moment the user is asking where the tab went, and a folder that
            // swallows it and stays shut answers by making it disappear.
            if let folder = landing.groupID { session.setGroupCollapsed(false, forGroup: folder) }
            if landing.kind == .essential, tab.kind != .essential {
                // Arriving among §3.3's tiles is a pin, which also puts the
                // page away (§19.2) and refuses past the Favorites cap.
                // Selecting on the way in keeps the page on screen.
                session.pinTab(id, at: landing.index, selecting: true)
                return
            }
            session.reorderTab(id, to: landing.index, kind: landing.kind, group: landing.groupID)
            // Picking a tab up is choosing it, wherever it is put down — the
            // column's rule. It is also what wakes a tab that came down out
            // of the kept run cold (§19.2).
            activateTab(id)
        }
        // §3.4b: a folder carried across the hairline takes its tabs with it,
        // which is `moveGroup`'s whole job.
        controller.onDropGroup = { [weak self] id, kind, index in
            self?.session.moveGroup(id, to: index, kind: kind)
        }
        controller.onDropOnSpace = { [weak self] id, space in
            self?.session.moveTab(id, toSpace: space)
        }
        strip.onDrag = { [weak controller] lifted, source, press in
            controller?.track(lifted, from: source, event: press)
        }
        drag = controller
    }
}
