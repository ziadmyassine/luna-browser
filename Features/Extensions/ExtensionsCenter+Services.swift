//
//  ExtensionsCenter+Services.swift
//  Luna
//
//  The shim's calls that only the app can answer (`ExtensionServices`): the
//  search engine, downloads, and moving, sleeping and grouping tabs. The rest
//  of the shim's answers are BrowserKit's own, in `ExtensionShimAnswers`.
//
//  Here rather than on the session because downloads are the app's, not a
//  session's: one manager and one list for every window.
//

import AppKit
import BrowserKit
import WebKit

extension ExtensionsCenter: ExtensionServices {

    private var downloads: DownloadManager? { (NSApp.delegate as? AppDelegate)?.downloads }

    func extensionSearchURL(for text: String) -> URL? {
        CommandBarURL.search(for: text)
    }

    // MARK: - Downloads

    /// Through a live page in the Space, as a link the user clicked would be:
    /// the same manager, the same list, the same questions about risky files.
    func extensionDownload(_ url: URL, filename: String?, inSpace spaceID: UUID) async throws -> ExtensionDownload {
        guard let session, let downloads else { throw ExtensionError.notAvailable("Downloading") }
        let pages = session.extensionTabs(inSpace: spaceID).compactMap { session.controller(for: $0.id)?.webView }
        guard let page = pages.first else { throw ExtensionError.notAvailable("Downloading with no page open") }
        let download = await page.startDownload(using: URLRequest(url: url))
        let item = downloads.begin(download, pageURL: url, inSpace: spaceID, session: session, filename: filename)
        return Self.describe(item)
    }

    func extensionDownloads(inSpace spaceID: UUID) -> [ExtensionDownload] {
        (downloads?.items(inSpace: spaceID) ?? []).reversed().map(Self.describe)
    }

    func extensionRevealDownload(_ id: UUID) {
        guard let downloads, let item = downloads.items.first(where: { $0.id == id }) else { return }
        downloads.reveal(item)
    }

    func extensionOpenDownload(_ id: UUID) {
        guard let downloads, let item = downloads.items.first(where: { $0.id == id }) else { return }
        downloads.open(item)
    }

    func extensionShowDownloadsFolder() {
        NSWorkspace.shared.open(URL.downloadsDirectory)
    }

    private static func describe(_ item: DownloadItem) -> ExtensionDownload {
        let state: ExtensionDownload.State = switch item.state {
        case .inProgress: .inProgress
        case .finished: .complete
        case .failed, .cancelled: .interrupted
        }
        return ExtensionDownload(
            id: item.id,
            url: item.request?.url ?? item.pageURL ?? URL(filePath: "/"),
            path: item.destination?.path ?? item.filename,
            state: state,
            exists: item.isOnDisk,
            startTime: item.startedAt,
            bytesReceived: item.progress?.completedUnitCount ?? size(of: item),
            totalBytes: item.progress?.totalUnitCount ?? size(of: item)
        )
    }

    private static func size(of item: DownloadItem) -> Int64 {
        guard item.isOnDisk, let path = item.destination?.path,
              let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    // MARK: - Tabs

    /// To the place of the tab now at `index` among the Space's tabs, when that
    /// tab is in the same section: an extension cannot move a tab between
    /// Favorites, saved tabs and today's, which are different things in Luna.
    func extensionMoveTab(_ id: UUID, to index: Int) {
        guard let session, let tab = session.tab(id) else { return }
        let row = session.extensionTabs(inSpace: tab.spaceID)
        guard row.indices.contains(index) else { return }
        let target = row[index]
        guard target.id != id, target.kind == tab.kind, let place = session.list.indexInSection(of: target.id) else { return }
        session.reorderTab(id, to: place, kind: tab.kind, group: target.groupID)
    }

    /// As §19.2's lifecycle puts a tab to sleep, except a tab holding unsaved
    /// input, which it would lose.
    func extensionDiscardTab(_ id: UUID) {
        guard let session, !TabLifecycle.hasUnsavedInput(id, in: session), let controller = session.controller(for: id) else { return }
        controller.hibernate()
        session.cacheSession(of: controller)
    }

    // MARK: - Groups

    func extensionGroupID(ofTab id: UUID) -> UUID? {
        session?.tab(id)?.groupID
    }

    func extensionGroups(inSpace spaceID: UUID) -> [TabGroup] {
        session?.list.groups(inSpace: spaceID) ?? []
    }

    /// A new group is named as the Folder menu names one, and its field is not
    /// opened: nobody is at the sidebar to type into it.
    func extensionGroup(_ tabs: [UUID], into group: UUID?, inSpace spaceID: UUID) -> UUID? {
        guard let session else { return nil }
        guard let group else {
            return session.createGroup(name: String(localized: "New Folder"), containing: tabs)
        }
        for tab in tabs { session.moveTab(tab, toGroup: group) }
        return group
    }

    func extensionUngroup(_ tabs: [UUID]) {
        for tab in tabs { session?.moveTab(tab, toGroup: nil) }
    }

    func extensionUpdateGroup(_ id: UUID, title: String?, collapsed: Bool?) {
        guard let session else { return }
        if let title { session.renameGroup(id, to: title) }
        if let collapsed { session.setGroupCollapsed(collapsed, forGroup: id) }
    }

    // MARK: - Closed tabs

    func extensionRestoreClosed(_ id: UUID?, inSpace spaceID: UUID) -> ExtensionClosedTab? {
        guard let session else { return nil }
        let closed = session.archived.filter { $0.spaceID == spaceID }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        guard let tab = id.flatMap({ id in closed.first { $0.id == id } }) ?? closed.first else { return nil }
        session.unarchiveTab(tab.id)
        return ExtensionClosedTab(id: tab.id, url: tab.url, title: tab.title, closedAt: tab.archivedAt ?? Date())
    }
}
