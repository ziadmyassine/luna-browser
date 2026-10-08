//
//  WindowDrop.swift
//  Luna
//
//  Files and web links dropped on a window anywhere but the page, opened as
//  new tabs: the sidebar, the top bar, the page bar, and a card with no page
//  on it. The page takes its own drops. WebKit gives a file to a page that
//  listens for one and otherwise opens it in that tab, as Safari does —
//  measured with a synthetic drag on a web view built from Luna's own
//  configuration — so the web view is left alone.
//
//  What is taken is what Finder's Open With takes (`AppDelegate.pages`), so a
//  drop and an open cannot disagree about a file — or, for dragged text, the
//  links in it, read as a paste reads them (`LunaServices.links`). A text
//  field still takes text dropped on it: its field editor is the deeper view.
//

import AppKit

/// The half of `NSDraggingDestination` a view that opens drops shares with
/// the other: `ChromeHostView` and `ContentCardView` forward to it.
@MainActor
enum WindowDrop {

    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]

    /// The pages on a dragged pasteboard, in the order they were dragged.
    ///
    /// None on a tab torn out of a list (`TabTearOff`): it carries its link for
    /// other apps, and opening that link here would be a second copy of a tab
    /// the drag is moving. Where it lands is the tear-off's to decide.
    static func pages(on pasteboard: NSPasteboard) -> [URL] {
        guard pasteboard.types?.contains(TabTearOff.tabType) != true else { return [] }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let pages = AppDelegate.pages(in: urls)
        return pages.isEmpty ? LunaServices.links(on: pasteboard) : pages
    }

    /// Nothing while the drag holds nothing Luna opens, so the pointer shows
    /// no badge over a folder or an app.
    static func operation(for info: any NSDraggingInfo) -> NSDragOperation {
        guard !pages(on: info.draggingPasteboard).isEmpty else { return [] }
        let offered = info.draggingSourceOperationMask
        return [NSDragOperation.copy, .link, .generic].first { offered.contains($0) } ?? []
    }

    /// `operation(for:)`, telling `report` where a drag Luna would open is —
    /// or nil, for one it would not.
    static func hover(_ info: any NSDraggingInfo, report: ((NSPoint?) -> Void)?) -> NSDragOperation {
        let operation = operation(for: info)
        report?(operation.isEmpty ? nil : info.draggingLocation)
        return operation
    }

    /// - Returns: whether the drop was taken.
    static func perform(_ info: any NSDraggingInfo, open: (([URL]) -> Void)?) -> Bool {
        let pages = pages(on: info.draggingPasteboard)
        guard let open, !pages.isEmpty else { return false }
        open(pages)
        return true
    }
}

/// A window's list, which can show where pages dropped on the window will
/// open: the sidebar's rows or §4's run (§6.6).
@MainActor
protocol DropMarking: AnyObject {
    /// Shows where pages dropped at `point` would open, and answers it.
    /// - Parameter point: in the window's coordinates, or nil for anywhere
    ///   off the list — the empty card, the page bar.
    /// - Returns: the landing, or nil for where a new tab opens anyway.
    func markDrop(at point: NSPoint?) -> SidebarDestination?
    func clearDropMark()
}
