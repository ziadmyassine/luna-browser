//
//  SidebarDrag.swift
//  Luna
//
//  §6.6's payload, in one place: a tab moves between the Essentials grid, the
//  list's sections and a Space dot, and all three ends have to agree on what is
//  on the pasteboard. A UUID string is the whole payload — the sidebar reads
//  everything else from `BrowserSession`, so carrying a copy of the title and
//  URL (as the reference browsers do) would only let the two disagree.
//

import AppKit
import Foundation

enum SidebarDrag {

    /// Luna's own type. Private to the app: a tab dragged to the Finder is a
    /// different feature with a different payload.
    static let tabType = NSPasteboard.PasteboardType("dk.novapps.luna.tab")

    static func item(for id: UUID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: tabType)
        return item
    }

    /// The dragged tab, or nil when the drag came from outside Luna.
    @MainActor
    static func tabID(in info: any NSDraggingInfo) -> UUID? {
        guard let raw = info.draggingPasteboard.string(forType: tabType) else { return nil }
        return UUID(uuidString: raw)
    }
}
