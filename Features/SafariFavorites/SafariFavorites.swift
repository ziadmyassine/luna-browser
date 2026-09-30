//
//  SafariFavorites.swift
//  Luna
//
//  The user's Favorites tiles and pinned tabs, kept as bookmarks in Safari's
//  Favorites, so they are on the iPhone's Safari start page as well
//  (docs/SAFARI-FAVORITES.md).
//
//  Off until the user turns it on in Settings ▸ iCloud. It writes Safari's own
//  bookmarks file, which needs Full Disk Access; without that it says so on
//  the page and tries again when Luna is next brought to the front, which is
//  where the user lands after granting it in System Settings.
//

import AppKit
import BrowserKit

@MainActor
final class SafariFavorites {

    static let shared = SafariFavorites()

    static let enabledKey = "safari.pinnedTabsInFavorites"
    /// The `WebBookmarkUUID`s of the bookmarks Luna put in Favorites: the only
    /// ones it changes or removes.
    static let ownedKey = "safari.lunaBookmarkIDs"
    /// The "Luna" folder earlier builds kept them in, taken out on the next run.
    static let legacyFolderKey = "safari.lunaFolderID"
    /// Posted whenever `status` changes.
    static let didChange = Notification.Name("luna.safariFavorites.didChange")

    enum Status: Equatable {
        case off
        /// Full Disk Access is off for Luna.
        case needsAccess
        case upToDate
        /// Something went wrong that trying again later may fix.
        case failed
    }

    private(set) var status = Status.off {
        didSet { if status != oldValue { NotificationCenter.default.post(name: Self.didChange, object: self) } }
    }

    var isOn: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            written = nil
            schedule(after: .zero)
        }
    }

    private let defaults: UserDefaults
    private weak var session: BrowserSession?
    private var observation: ObservationToken?
    private var activation: NSObjectProtocol?
    /// What Luna's bookmarks were last made to hold, so an unrelated change to the
    /// session writes nothing.
    private var written: [SafariFavorite]?
    private var pending: Task<Void, Never>?
    /// A run is writing or waiting on Safari; a change meanwhile runs again after.
    private var running = false
    private var runAgain = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func attach(to session: BrowserSession) {
        self.session = session
        observation = session.addChangeObserver { [weak self] in self?.schedule(after: Self.settle) }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .needsAccess || self.status == .failed else { return }
                self.written = nil
                self.schedule(after: .zero)
            }
        }
        schedule(after: .zero)
    }

    /// Long enough that pinning several tabs in a row is one write, short
    /// enough that the iPhone has it by the time the user picks it up.
    static let settle: Duration = .seconds(2)

    /// The Favorites tiles, then the pinned tabs Space by Space in sidebar
    /// order, each once. A pinned tab's page is the one it was pinned at, not
    /// wherever it has wandered. A tile shows no title in Luna, and its page's
    /// title changes with every visit ("(3) Inbox"), so it goes by its host
    /// unless the user named it.
    static func pages(in tabs: [Tab]) -> [SafariFavorite] {
        var seen = Set<String>()
        let kept = tabs.filter { $0.kind != .today && $0.archivedAt == nil }
        return (kept.filter { $0.kind == .essential } + kept.filter { $0.kind == .pinned }).compactMap { tab in
            let url = tab.pinnedURL ?? tab.url
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  seen.insert(url.absoluteString).inserted else { return nil }
            let host = url.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            let names = tab.kind == .essential ? [tab.customTitle] : [tab.customTitle, tab.title]
            let title = names.compactMap { $0 }.first { !$0.isEmpty } ?? host ?? url.absoluteString
            return SafariFavorite(title: title, url: url)
        }
    }

    // MARK: - Writing

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private func run() async {
        guard !running else {
            runAgain = true
            return
        }
        running = true
        defer {
            running = false
            if runAgain {
                runAgain = false
                schedule(after: .zero)
            }
        }
        guard let session else { return }
        let on = isOn
        let pages = on ? Self.pages(in: session.allTabs(includeArchived: false)) : []
        guard !on || pages != written || status != .upToDate else { return }
        let owned = Set(defaults.stringArray(forKey: Self.ownedKey) ?? [])
        let legacy = defaults.string(forKey: Self.legacyFolderKey)
        guard on || !owned.isEmpty || legacy != nil else {
            status = .off
            return
        }
        let result = await Task.detached { try await Self.write(pages, keeping: on, owned: owned, legacyFolder: legacy) }.result
        switch result {
        case .success(let outcome):
            defaults.set(outcome.owned.sorted(), forKey: Self.ownedKey)
            defaults.removeObject(forKey: Self.legacyFolderKey)
            written = on ? pages : nil
            status = on ? .upToDate : .off
            if outcome.queued { await SafariSyncNudge.run() }
        case .failure(SafariBookmarksFile.Failure.noAccess):
            status = .needsAccess
        case .failure:
            status = .failed
        }
    }

    /// One read-edit-replace, again from the top when Safari or its agent got
    /// there first.
    /// Also takes out a Reading List item `SafariSyncNudge` could not remove
    /// last time, so it goes up with this upload.
    /// - Returns: the IDs of Luna's bookmarks afterwards, and whether entries
    ///   were queued for iCloud, which is when Safari has to be nudged.
    private nonisolated static func write(
        _ pages: [SafariFavorite], keeping: Bool, owned: Set<String>, legacyFolder: String?
    ) async throws -> (owned: Set<String>, queued: Bool) {
        for _ in 0..<5 {
            let data = try SafariBookmarksFile.read()
            var document = try SafariBookmarksDocument(data: data)
            var changed = legacyFolder.map { document.removeFolder($0) } ?? false
            var now = owned
            if keeping {
                guard let result = document.mirror(pages, owned: owned) else { return ([], false) }
                changed = result.changed || changed
                now = result.owned
            } else {
                changed = document.removeBookmarks(owned) || changed
                now = []
            }
            guard changed else { return (now, false) }
            _ = document.removeReadingListItems(at: SafariSyncNudge.marker)
            do {
                try SafariBookmarksFile.replace(data, with: document.data())
                SafariBookmarksFile.announceChange()
                return (now, document.usesICloud && !document.pendingChanges.isEmpty)
            } catch SafariBookmarksFile.Failure.busy {
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw SafariBookmarksFile.Failure.busy
    }
}
