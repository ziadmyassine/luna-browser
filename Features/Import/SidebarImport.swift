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
//  Arc's Spaces are not recreated. §3.4b puts one import in one folder named
//  after the browser, so the four of them flatten into `Arc` like everything
//  else; the alternative is a second answer to "where does an import land".
//

import Foundation

/// Arc's `StorableSidebar.json`.
enum ArcSidebar {

    /// Every saved tab in the sidebar, in the order Arc lists them.
    ///
    /// The file interleaves item ids and item objects in one array, so the
    /// objects are what is walked and the ids are skipped. An item is a saved
    /// tab when it carries `data.tab.savedURL`; the others are folders, easels
    /// and split views, none of which is an address.
    static func parse(_ data: Data) -> [ImportedBookmark] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sidebar = root["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [[String: Any]]
        else {
            return []
        }
        var bookmarks: [ImportedBookmark] = []
        var seen: Set<String> = []
        for container in containers {
            for item in (container["items"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                guard
                    let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any],
                    let address = tab["savedURL"] as? String,
                    let url = ImportedBookmark.webURL(address),
                    seen.insert(url.absoluteString).inserted
                else {
                    continue
                }
                let title = (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? ""
                bookmarks.append(ImportedBookmark(
                    url: url,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dateAdded: referenceDate(item["createdAt"]),
                    placement: .folder
                ))
            }
        }
        return bookmarks
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
                        placement: .folder
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
