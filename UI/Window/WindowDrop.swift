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
//  drop and an open cannot disagree about a file.
//

import AppKit

/// The half of `NSDraggingDestination` a view that opens drops shares with
/// the other: `ChromeHostView` and `ContentCardView` forward to it.
@MainActor
enum WindowDrop {

    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL]

    /// The pages on a dragged pasteboard, in the order they were dragged.
    static func pages(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return AppDelegate.pages(in: urls)
    }

    /// Nothing while the drag holds nothing Luna opens, so the pointer shows
    /// no badge over a folder or an app.
    static func operation(for info: any NSDraggingInfo) -> NSDragOperation {
        guard !pages(on: info.draggingPasteboard).isEmpty else { return [] }
        let offered = info.draggingSourceOperationMask
        return [NSDragOperation.copy, .link, .generic].first { offered.contains($0) } ?? []
    }

    /// - Returns: whether the drop was taken.
    static func perform(_ info: any NSDraggingInfo, open: (([URL]) -> Void)?) -> Bool {
        let pages = pages(on: info.draggingPasteboard)
        guard let open, !pages.isEmpty else { return false }
        open(pages)
        return true
    }
}
