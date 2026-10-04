//
//  ImportMapping.swift
//  Luna — §23.2
//
//  What the import's mapping step edits: for each kind of thing another
//  browser keeps, where in Luna it lands. Here rather than beside the
//  importer so the rules are tested without a store or a window; the importer
//  asks `placement` once per bookmark and the screen only edits the value.
//

import Foundation

/// A kind of thing a source browser keeps, as the mapping step lists it.
public enum ImportCategory: String, CaseIterable, Sendable, Codable {
    /// The source's own one-click row: Arc's top apps, an older Dia's favourites.
    case favorites
    /// Folders in the source's own sidebar.
    case pinnedFolders
    /// Saved tabs loose in the source's sidebar, outside any folder.
    case pinnedTabs
    /// URLs loose on the bookmarks bar.
    case bookmarkBar
    /// Everything filed in a bookmark folder, `Other` and `Mobile` included.
    case bookmarkFolders
    case history

    /// What this can become, the like-for-like answer first. There is no
    /// loose pinned tab to offer: §3.4b's tier under the tiles holds folders
    /// and nothing else.
    public var destinations: [ImportDestination] {
        switch self {
        case .favorites, .bookmarkBar: [.favorites, .pinnedFolders, .skip]
        case .pinnedTabs: [.pinnedFolders, .favorites, .skip]
        case .pinnedFolders, .bookmarkFolders: [.pinnedFolders, .skip]
        case .history: [.history, .skip]
        }
    }
}

/// Where a category lands in Luna.
public enum ImportDestination: String, Sendable, Codable {
    /// §3.3's grid.
    case favorites
    /// §3.4b's folders.
    case pinnedFolders
    /// The Space's history.
    case history
    case skip
}

/// Where one imported bookmark goes.
public enum ImportPlacement: Hashable, Sendable {
    case favorite
    /// A pinned folder, by name.
    case folder(String)
}

/// One import's answers, and how many of each category there are to answer for.
public struct ImportMapping: Hashable, Sendable {

    public let counts: [ImportCategory: Int]
    private var choices: [ImportCategory: ImportDestination] = [:]

    public init(counts: [ImportCategory: Int]) {
        self.counts = counts
    }

    /// The categories with something in them, in the order the step lists them.
    public var categories: [ImportCategory] {
        ImportCategory.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    /// A destination the category does not offer is ignored.
    public subscript(category: ImportCategory) -> ImportDestination {
        get { choices[category] ?? defaultDestination(for: category) }
        set {
            guard category.destinations.contains(newValue) else { return }
            choices[category] = newValue
        }
    }

    /// Like for like, with one exception: a browser that has pinned folders of
    /// its own keeps them there, and the bookmark tree beside them is usually
    /// what an older import left behind. Both arriving as pinned folders is
    /// the duplicate the user then has to take apart.
    private func defaultDestination(for category: ImportCategory) -> ImportDestination {
        if category == .bookmarkFolders, (counts[.pinnedFolders] ?? 0) > 0 { return .skip }
        return category.destinations[0]
    }

    /// Nil when the category is skipped. A Luna folder holds tabs and not other
    /// folders (§3.4b), so a nested folder's path is its name — `Work / Archive`
    /// keeps both names and cannot collide with another `Archive` — and a loose
    /// item sent to the folders tier goes in the one named after the browser.
    public func placement(of category: ImportCategory, folderPath: [String], browser: String) -> ImportPlacement? {
        switch self[category] {
        case .skip, .history: nil
        case .favorites: .favorite
        case .pinnedFolders: .folder(folderPath.isEmpty ? browser : folderPath.joined(separator: " / "))
        }
    }
}
