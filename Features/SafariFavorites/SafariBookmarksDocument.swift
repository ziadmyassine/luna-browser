//
//  SafariBookmarksDocument.swift
//  Luna
//
//  Safari's `Bookmarks.plist`, edited so that Safari's own iCloud sync carries
//  the edit to the user's other devices (docs/SAFARI-FAVORITES.md).
//
//  Safari's sync agent does not compare the file with iCloud. It uploads what
//  the top-level `Sync.Changes` array lists, clears the list, and fills in each
//  new item's `Data` (its CloudKit system fields). An item that is only in the
//  tree is shown on this Mac and never sent: measured, a bookmark written without
//  an entry sat there for days with a `ServerID` and no `Data`. So every edit here
//  records an entry, and only then does it reach the iPhone.
//
//  Edited as a property list rather than decoded into types, so every key this
//  does not know — CloudKit state, Reading List metadata — is written back as it
//  was read, and the file keeps its format.
//

import Foundation

/// A page Luna keeps in Safari's Favorites.
struct SafariFavorite: Equatable, Sendable {
    let title: String
    let url: URL
}

struct SafariBookmarksDocument {

    private var root: [String: Any]
    private let format: PropertyListSerialization.PropertyListFormat

    init(data: Data) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        self.root = root
        self.format = format
    }

    func data() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
    }

    /// Safari keeps its bookmarks in iCloud on this Mac: the CloudKit state is at
    /// the top of the file. Without it there is no sync to feed, and no entries
    /// are recorded; the bookmarks are still kept, for Safari on this Mac.
    var usesICloud: Bool {
        (root["Sync"] as? [String: Any])?["CloudKitMigrationState"] != nil
    }

    /// Entries the sync agent has not uploaded yet, Safari's own included.
    var pendingChanges: [[String: Any]] {
        get { ((root["Sync"] as? [String: Any])?["Changes"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [] }
        set {
            var sync = root["Sync"] as? [String: Any] ?? [:]
            sync["Changes"] = newValue.isEmpty ? nil : newValue
            root["Sync"] = sync
        }
    }

    // MARK: - Favorites

    /// Makes Luna's bookmarks in Favorites hold `pages`, and records a change
    /// entry for each edit.
    ///
    /// Luna's bookmarks are the ones it added, named in `owned`; everything
    /// else in Favorites is the user's and is never touched, and a page already
    /// among the user's own is not added a second time. Existing bookmarks keep
    /// their places and new ones go at the end — a reorder would be a move, and
    /// a move the other devices get wrong is worse than an order that lags.
    ///
    /// - Returns: whether anything changed, and the `WebBookmarkUUID`s of
    ///   Luna's bookmarks now. Nil when the file has no Favorites.
    mutating func mirror(_ pages: [SafariFavorite], owned: Set<String>) -> (changed: Bool, owned: Set<String>)? {
        guard let favorites else { return nil }
        let naming = usesICloud
        var result = Self.reconcile(favorites, with: pages, owned: owned, naming: naming)
        let prepared = naming && prepareUnsent(&result.children, owned: result.owned)
        guard !result.changes.isEmpty || !result.dropped.isEmpty || prepared else { return (false, result.owned) }
        self.favorites = result.children
        pendingChanges.removeAll { result.dropped.contains($0["BookmarkUUID"] as? String ?? "") }
        if naming { pendingChanges += result.changes }
        return (true, result.owned)
    }

    /// Takes Luna's bookmarks out of Favorites, recorded as `mirror` records a
    /// removal. Returns whether any were there.
    mutating func removeBookmarks(_ owned: Set<String>) -> Bool {
        guard var favorites else { return false }
        let isLunas = { (node: [String: Any]) in Self.isLeaf(node) && owned.contains(node["WebBookmarkUUID"] as? String ?? "") }
        let leaving = favorites.filter(isLunas)
        guard !leaving.isEmpty else { return false }
        favorites.removeAll(where: isLunas)
        self.favorites = favorites
        recordRemoval(of: leaving)
        return true
    }

    /// Takes out the "Luna" folder earlier builds kept the bookmarks in, with
    /// everything under it. Found by its ID only: a folder the user named Luna
    /// is theirs. Returns whether it was there.
    mutating func removeFolder(_ folderID: String) -> Bool {
        guard var favorites,
              let index = favorites.firstIndex(where: { Self.isFolder($0) && $0["WebBookmarkUUID"] as? String == folderID })
        else { return false }
        let folder = favorites.remove(at: index)
        self.favorites = favorites
        recordRemoval(of: [folder] + Self.descendants(of: folder))
        return true
    }

    /// What is in Favorites, or nil when the file has none.
    private var favorites: [[String: Any]]? {
        get { topFolder("BookmarksBar") }
        set { setTopFolder("BookmarksBar", to: newValue) }
    }

    // MARK: - Reading List

    /// Takes the Reading List items at `url` out, recorded as `removeBookmarks`
    /// records a removal. Returns whether any were there.
    mutating func removeReadingListItems(at url: String) -> Bool {
        guard var items = topFolder(Self.readingList) else { return false }
        let leaving = items.filter { $0["URLString"] as? String == url }
        guard !leaving.isEmpty else { return false }
        items.removeAll { $0["URLString"] as? String == url }
        setTopFolder(Self.readingList, to: items)
        recordRemoval(of: leaving)
        return true
    }

    /// Whether iCloud has a Reading List item at `url`.
    func hasUploadedReadingListItem(at url: String) -> Bool {
        topFolder(Self.readingList)?.contains { $0["URLString"] as? String == url && Self.isUploaded($0) } ?? false
    }

    private static let readingList = "com.apple.ReadingList"

    private func topFolder(_ title: String) -> [[String: Any]]? {
        Self.children(of: root).first { $0["Title"] as? String == title }.map(Self.children(of:))
    }

    private mutating func setTopFolder(_ title: String, to children: [[String: Any]]?) {
        var top = Self.children(of: root)
        guard let children, let index = top.firstIndex(where: { $0["Title"] as? String == title }) else { return }
        top[index]["Children"] = children
        root["Children"] = top
    }

    /// A Delete entry for each item iCloud has; one still waiting to go up only
    /// loses its pending entries, because iCloud has nothing to delete.
    private mutating func recordRemoval(of nodes: [[String: Any]]) {
        var changes: [[String: Any]] = []
        var dropped = Set<String>()
        for node in nodes {
            if Self.isUploaded(node) {
                changes.append(Self.change("Delete", for: node))
            } else if let uuid = node["WebBookmarkUUID"] as? String {
                dropped.insert(uuid)
            }
        }
        pendingChanges.removeAll { dropped.contains($0["BookmarkUUID"] as? String ?? "") }
        if usesICloud { pendingChanges += changes }
    }

    private static func descendants(of node: [String: Any]) -> [[String: Any]] {
        children(of: node).flatMap { [$0] + descendants(of: $0) }
    }

    /// Favorites made to hold `pages`, with the entries that says.
    private struct Reconciled {
        var children: [[String: Any]] = []
        var changes: [[String: Any]] = []
        /// Bookmarks removed before they were ever uploaded.
        var dropped = Set<String>()
        /// Luna's bookmarks afterwards.
        var owned = Set<String>()
    }

    /// - Parameter naming: give each new bookmark its CloudKit record name, as
    ///   Safari's uploader expects when it runs without Safari.
    private static func reconcile(
        _ favorites: [[String: Any]], with pages: [SafariFavorite], owned: Set<String>, naming: Bool
    ) -> Reconciled {
        func isOwned(_ node: [String: Any]) -> Bool {
            isLeaf(node) && owned.contains(node["WebBookmarkUUID"] as? String ?? "")
        }
        var wanted: [String: SafariFavorite] = [:]
        var order: [String] = []
        for page in pages where wanted[page.url.absoluteString] == nil {
            wanted[page.url.absoluteString] = page
            order.append(page.url.absoluteString)
        }
        // The user's own favourites count as there already.
        var present = Set(favorites.filter { isLeaf($0) && !isOwned($0) }.compactMap { $0["URLString"] as? String })
        var result = Reconciled()
        for child in favorites {
            guard isOwned(child), let url = child["URLString"] as? String else {
                result.children.append(child)
                continue
            }
            guard let page = wanted[url], !present.contains(url) else {
                if isUploaded(child) {
                    result.changes.append(change("Delete", for: child))
                } else if let uuid = child["WebBookmarkUUID"] as? String {
                    result.dropped.insert(uuid)
                }
                continue
            }
            present.insert(url)
            let (leaf, rename) = retitled(child, to: page.title)
            if let rename { result.changes.append(rename) }
            result.children.append(leaf)
            result.owned.insert(leaf["WebBookmarkUUID"] as? String ?? "")
        }
        for url in order where !present.contains(url) {
            guard let page = wanted[url] else { continue }
            let leaf = newLeaf(url, title: page.title, naming: naming)
            result.children.append(leaf)
            result.changes.append(change("Add", for: leaf))
            result.owned.insert(leaf["WebBookmarkUUID"] as? String ?? "")
        }
        return result
    }

    /// `leaf` with `title`, and the Modify entry for it if iCloud has it. One
    /// still waiting to be added goes up with its new title as it is.
    private static func retitled(_ leaf: [String: Any], to title: String) -> ([String: Any], [String: Any]?) {
        guard (leaf["URIDictionary"] as? [String: Any])?["title"] as? String != title else { return (leaf, nil) }
        var leaf = leaf
        var names = leaf["URIDictionary"] as? [String: Any] ?? [:]
        names["title"] = title
        leaf["URIDictionary"] = names
        guard isUploaded(leaf) else { return (leaf, nil) }
        var entry = change("Modify", for: leaf)
        entry["ChangedAttributes"] = ["Title"]
        return (leaf, entry)
    }

    private static func newLeaf(_ url: String, title: String, naming: Bool) -> [String: Any] {
        var leaf: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": UUID().uuidString,
            "URLString": url,
            "URIDictionary": ["title": title],
            "dateAdded": Date()
        ]
        if naming { leaf["Sync"] = ["ServerID": UUID().uuidString] }
        return leaf
    }

    /// Gives Luna's bookmarks what an Add needs when they are still waiting to
    /// go up without it: a record name, written into their pending entries too,
    /// and the date added, which every item Safari writes carries. Measured with
    /// Safari closed: the uploader left on the list an Add without a record
    /// name, and sent one with it within seconds. Returns whether anything
    /// changed.
    private mutating func prepareUnsent(_ favorites: inout [[String: Any]], owned: Set<String>) -> Bool {
        var named: [String: String] = [:]
        var dated = false
        for index in favorites.indices {
            var node = favorites[index]
            guard Self.isLeaf(node), let uuid = node["WebBookmarkUUID"] as? String, owned.contains(uuid),
                  !Self.isUploaded(node) else { continue }
            if node["dateAdded"] == nil {
                node["dateAdded"] = Date()
                dated = true
            }
            if Self.serverID(of: node) == nil {
                let server = UUID().uuidString
                var sync = node["Sync"] as? [String: Any] ?? [:]
                sync["ServerID"] = server
                node["Sync"] = sync
                named[uuid] = server
            }
            favorites[index] = node
        }
        guard !named.isEmpty else { return dated }
        pendingChanges = pendingChanges.map { entry in
            guard let uuid = entry["BookmarkUUID"] as? String, let server = named[uuid] else { return entry }
            var entry = entry
            entry["BookmarkServerID"] = server
            return entry
        }
        return true
    }

    // MARK: - Entries

    /// An entry naming the item and its CloudKit record. A Delete also hands
    /// back that record's system fields.
    static func change(_ type: String, for node: [String: Any]) -> [String: Any] {
        var entry: [String: Any] = [
            "Token": UUID().uuidString,
            "Type": type,
            "BookmarkType": isFolder(node) ? "Folder" : "Leaf",
            "BookmarkUUID": node["WebBookmarkUUID"] as? String ?? ""
        ]
        if let sync = node["Sync"] as? [String: Any], let server = sync["ServerID"] as? String {
            entry["BookmarkServerID"] = server
            if type == "Delete", let data = sync["Data"] as? Data { entry["DeletedBookmarkSyncData"] = data }
        }
        return entry
    }

    private static func children(of node: [String: Any]) -> [[String: Any]] {
        (node["Children"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func isFolder(_ node: [String: Any]) -> Bool {
        node["WebBookmarkType"] as? String == "WebBookmarkTypeList"
    }

    private static func isLeaf(_ node: [String: Any]) -> Bool {
        node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf"
    }

    /// iCloud has it: the uploader fills in `Data` once the record exists.
    private static func isUploaded(_ node: [String: Any]) -> Bool {
        (node["Sync"] as? [String: Any])?["Data"] is Data
    }

    private static func serverID(of node: [String: Any]) -> String? {
        guard let id = (node["Sync"] as? [String: Any])?["ServerID"] as? String, !id.isEmpty else { return nil }
        return id
    }
}
