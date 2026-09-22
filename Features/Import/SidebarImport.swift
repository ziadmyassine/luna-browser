//
//  SidebarImport.swift
//  Luna — §23.2
//
//  The saved tabs two members of the Chromium family keep outside the Chromium
//  profile, and which `ChromiumReader` would otherwise never see.
//
//  `ChromiumImport` reads `Bookmarks`, because every Chromium browser writes
//  it. Arc does not write it at all — there is no such file in its profile —
//  and Dia writes an empty one. What each of them actually saves lives in its
//  own JSON beside `User Data`:
//
//      Arc   StorableSidebar.json           the sidebar: pinned tabs and folders
//      Dia   StorableProfileContainers.json its favourites, per profile
//
//  Measured on this Mac: Arc's file is 753 KB of plain JSON holding 118 saved
//  tabs across four Arc Spaces, and Dia's holds 8 favourites. Before this, an
//  Arc import reported `bookmarks + 0` and brought across nothing but history —
//  which for an Arc user is the wrong half, because the sidebar *is* their
//  bookmarks.
//
//  Both readers are lenient for `ChromiumReader.flatten`'s reason: the shape is
//  the browser's private business and changes between releases, so an unknown
//  key must cost one row rather than the whole import. Neither ever throws —
//  a file Luna cannot make sense of is no saved tabs, not a failed import,
//  because the `Bookmarks` half and the history have their own answers already.
//
//  Open windows are deliberately not read. Dia's file carries them beside its
//  favourites (`container.window`) and they are working state rather than
//  things kept — the same rule `exportBookmarksHTML` keeps when it leaves
//  today's tabs out of an export.
//
//  These two keep their shape; every other source does not. Arc's sidebar has
//  Spaces holding folders, which is §3.4b's own shape, and Dia's favourites are
//  scoped to a profile exactly the way Luna's tiles are scoped to a Space — so
//  both arrive as what they are. A Chromium `Bookmarks` tree has neither, and
//  §3.4b's one-import-one-folder rule still governs it. `ProfileReader`'s
//  `keepsItsOwnStructure` is the switch, and `BrowserImporter+Placement` has
//  the two writers.
//

import Foundation

/// Arc's `StorableSidebar.json`.
///
/// The one source that arrives with a shape rather than a list. Arc has Spaces,
/// each Space has a pinned tier, and that tier holds folders — which is §3.4b's
/// own shape, so it is kept rather than flattened. Measured on this Mac: two
/// Spaces, `School` and `Personal`, holding 118 saved tabs in seven folders,
/// two of them nested.
///
/// What is deliberately left behind:
///
/// · **The unpinned tier.** Those are the tabs Arc has open, which is working
///   state rather than something kept — the rule the HTML export keeps when it
///   leaves today's tabs out.
/// · **Nesting past one level.** A Luna folder holds tabs, not other folders
///   (§3.4b), so `IA ▸ Physics` becomes one folder called `IA / Physics`. The
///   alternative is dropping either the outer name or the inner one, and the
///   path is the only spelling that keeps both and cannot collide.
enum ArcSidebar {

    /// Every saved tab in the sidebar, tagged with the Arc Space and the folder
    /// it was in.
    ///
    /// The file interleaves ids and objects in one array, so the objects are
    /// what is walked and the bare ids are skipped. An item is a saved tab when
    /// it carries `data.tab.savedURL`; a folder carries `data.list`, and easels
    /// and split views carry neither an address nor anything to open.
    static func parse(_ data: Data) -> [ImportedBookmark] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sidebar = root["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [[String: Any]]
        else {
            return []
        }
        return containers.flatMap(bookmarks(inContainer:))
    }

    private static func bookmarks(inContainer container: [String: Any]) -> [ImportedBookmark] {
        let items = (container["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        var children: [String: [[String: Any]]] = [:]
        for item in items {
            guard let parent = item["parentID"] as? String else { continue }
            children[parent, default: []].append(item)
        }
        let favourites = favouriteContainers(container["topAppsContainerIDs"] as? [Any] ?? [])

        var bookmarks: [ImportedBookmark] = []
        for space in (container["spaces"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
            guard let name = (space["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else {
                continue
            }
            var inSpace: [ImportedBookmark] = []
            // Arc's favourites belong to the profile rather than to one Space,
            // and every Space on that profile shows the same row — so every
            // Space imported from it gets them, which is what the user is
            // looking at in Arc.
            if let top = favourites[profileKey(space["profile"])] {
                append(childrenOf: top, in: children, path: [], placement: .favorite, into: &inSpace)
            }
            if let pinned = pinnedContainerID(space["containerIDs"] as? [Any] ?? []) {
                append(childrenOf: pinned, in: children, path: [], placement: .folder, into: &inSpace)
            }
            bookmarks += inSpace.map { bookmark in
                var tagged = bookmark
                tagged.spaceName = name
                return tagged
            }
        }
        return bookmarks
    }

    /// `containerIDs` is marker/id pairs — `"pinned"`, its id, `"unpinned"`,
    /// its id — so the pinned container is the entry after the marker rather
    /// than a fixed index.
    private static func pinnedContainerID(_ ids: [Any]) -> String? {
        guard let marker = ids.firstIndex(where: { $0 as? String == "pinned" }) else { return nil }
        return ids.indices.contains(marker + 1) ? ids[marker + 1] as? String : nil
    }

    /// `topAppsContainerIDs` is marker/id pairs too, and the markers are
    /// profiles: `{"default": true}` or `{"custom": {…}}`. Keyed by the same
    /// spelling a Space's own `profile` field uses, so the two can be matched.
    private static func favouriteContainers(_ ids: [Any]) -> [String: String] {
        var byProfile: [String: String] = [:]
        var pending: String?
        for entry in ids {
            if let id = entry as? String {
                if let pending { byProfile[pending] = id }
                pending = nil
            } else {
                pending = profileKey(entry)
            }
        }
        return byProfile
    }

    /// A profile, as a string that is the same on both sides of the file.
    /// `{"custom": {"_0": {"directoryBasename": "Profile 3"}}}` is that
    /// directory; anything else is the default one.
    private static func profileKey(_ value: Any?) -> String {
        guard let profile = value as? [String: Any] else { return "default" }
        guard let custom = profile["custom"] as? [String: Any],
              let fields = custom["_0"] as? [String: Any],
              let basename = fields["directoryBasename"] as? String
        else {
            return "default"
        }
        return basename
    }

    /// Depth cap for `ChromiumReader.maxDepth`'s reason: JSON cannot express a
    /// cycle, but a corrupt file can be arbitrarily deep and an uncapped walk
    /// allocates a path per level without bound.
    private static let maxDepth = 12

    private static func append(
        childrenOf parent: String,
        in children: [String: [[String: Any]]],
        path: [String],
        placement: BookmarkPlacement,
        into bookmarks: inout [ImportedBookmark]
    ) {
        guard path.count <= maxDepth else { return }
        for item in children[parent] ?? [] {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else {
                // Not a tab. A folder is the only other kind worth walking into
                // — an easel and a split view have no address in them.
                guard let id = item["id"] as? String, (item["data"] as? [String: Any])?["list"] != nil else {
                    continue
                }
                append(
                    childrenOf: id,
                    in: children,
                    path: path + [title.isEmpty ? String(localized: "Folder") : title],
                    placement: placement,
                    into: &bookmarks
                )
                continue
            }
            guard
                let address = tab["savedURL"] as? String,
                let url = ImportedBookmark.webURL(address)
            else {
                continue
            }
            let saved = (tab["savedTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            bookmarks.append(ImportedBookmark(
                url: url,
                title: title.isEmpty ? saved : title,
                dateAdded: referenceDate(item["createdAt"]),
                folderPath: path,
                placement: placement
            ))
        }
    }
}

/// Dia's `StorableProfileContainers.json`.
enum DiaFavorites {

    /// One profile's favourites.
    ///
    /// `profileID` in the file is the profile's directory name — `"Default"`,
    /// `"Profile 2"` — which is what makes filtering possible at all: the file
    /// is one per app rather than one per profile, so importing Dia's `Work`
    /// profile must not hand over `Personal`'s favourites.
    ///
    /// A container is favourites only when its id says so. The other kind is a
    /// window, and a window is what is open rather than what is kept.
    static func parse(_ data: Data, profileDirectory: String) -> [ImportedBookmark] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let containers = root["containers"] as? [[String: Any]]
        else {
            return []
        }
        // An empty directory name is the single-profile layout, which Dia still
        // writes as `Default`.
        let wanted = profileDirectory.isEmpty ? "Default" : profileDirectory
        var bookmarks: [ImportedBookmark] = []
        var seen: Set<String> = []
        for container in containers {
            let id = container["id"] as? [String: Any]
            guard (id?["profileID"] as? String) == wanted,
                  (id?["container"] as? [String: Any])?["favorites"] != nil
            else {
                continue
            }
            for tab in container["tabs"] as? [[String: Any]] ?? [] {
                let when = referenceDate(tab["creationDate"])
                for content in tab["contents"] as? [[String: Any]] ?? [] {
                    guard
                        let page = (content["variant"] as? [String: Any])?["webContent"] as? [String: Any],
                        let fields = page["_0"] as? [String: Any],
                        let address = fields["url"] as? String,
                        let url = ImportedBookmark.webURL(address),
                        seen.insert(url.absoluteString).inserted
                    else {
                        continue
                    }
                    let title = (fields["title"] as? String) ?? ""
                    bookmarks.append(ImportedBookmark(
                        url: url,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        dateAdded: when,
                        // §3.3's grid. Dia's favourites are its one-click row
                        // and a Dia profile is exactly one Luna Space, so the
                        // two are scoped the same way and the row is a row of
                        // tiles. `spaceName` stays nil: the profile's Space is
                        // the one this import is already making.
                        placement: .favorite
                    ))
                }
            }
        }
        return bookmarks
    }
}

/// Both files date things in seconds since 2001, which is what Foundation
/// calls the reference date — they are Swift apps writing `Date` through
/// `Codable`, not Chromium writing its 1601 microseconds.
private func referenceDate(_ value: Any?) -> Date? {
    guard let seconds = value as? Double, seconds > 0 else { return nil }
    return Date(timeIntervalSinceReferenceDate: seconds)
}
