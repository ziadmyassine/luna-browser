//
//  BrowserCommands+Bookmarks.swift
//  Luna — §11.4, §23.2, §23.4
//
//  File ▸ Import Bookmarks… and Export Bookmarks…: `NetscapeBookmarks`, the
//  format every browser reads and writes, from the menu bar. Each action is
//  the panel and nothing else; the work past it takes a URL, so a test runs
//  it without a panel on screen.
//
//  Both act on the front window's store, and both dim in a private window
//  (`validateMenuItem`), whose store is deleted when it closes.
//

import AppKit
import BrowserKit
import UniformTypeIdentifiers

extension BrowserCommand {

    static let importBookmarks = BrowserCommand(
        "importBookmarks", "Import Bookmarks…", #selector(AppDelegate.importBookmarks(_:)),
        symbol: "square.and.arrow.down", keywords: ["import", "bookmarks", "html", "favorites", "safari", "chrome"]
    )
    static let exportBookmarks = BrowserCommand(
        "exportBookmarks", "Export Bookmarks…", #selector(AppDelegate.exportBookmarks(_:)),
        symbol: "square.and.arrow.up", keywords: ["export", "bookmarks", "html", "backup"]
    )
}

extension AppDelegate {

    @objc func importBookmarks(_ sender: Any?) {
        guard let session else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await importBookmarks(from: url, into: session).show(in: session.hostWindow)
        }
    }

    @objc func exportBookmarks(_ sender: Any?) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = String(localized: "Luna Bookmarks.html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await exportBookmarks(to: url, from: session).show(in: session.hostWindow)
        }
    }

    /// Into a Space named after the file, which a second import of the same
    /// file finds again rather than duplicating (`resolveTargetSpace`).
    func importBookmarks(from url: URL, into session: BrowserSession) async -> PageToast {
        do {
            let summary = try await BrowserImporter(store: session.store).importBookmarks(htmlAt: url)
            // The importer writes straight to the store, behind the session.
            try await session.adoptSpacesWrittenElsewhere()
            let space = session.spaces.first { $0.id == summary.targetSpaceID }?.name ?? ""
            return .bookmarksImported(summary.bookmarksAdded, into: space)
        } catch {
            return .bookmarksNotImported(url.lastPathComponent)
        }
    }

    /// Every Space, each as a folder.
    func exportBookmarks(to url: URL, from session: BrowserSession) async -> PageToast {
        do {
            let html = try await BrowserImporter(store: session.store).exportBookmarksHTML()
            try html.write(to: url, atomically: true, encoding: .utf8)
            return .bookmarksExported(url.lastPathComponent)
        } catch {
            return .bookmarksNotExported(url.lastPathComponent)
        }
    }
}
