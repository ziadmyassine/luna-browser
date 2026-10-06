@testable import BrowserKit
import Foundation
import Testing

/// §23.2's mapping step: what each kind of saved thing in another browser
/// becomes in Luna. The importer asks `placement` once per bookmark, so these
/// are the rules the whole import lands by.
@Suite("Import mapping (§23.2)")
struct ImportMappingTests {

    @Test("Defaults are like for like")
    func defaultsAreLikeForLike() {
        let mapping = ImportMapping(counts: [.favorites: 2, .pinnedFolders: 3, .bookmarkBar: 1, .history: 9])
        #expect(mapping[.favorites] == .favorites)
        #expect(mapping[.pinnedFolders] == .pinnedFolders)
        #expect(mapping[.bookmarkBar] == .favorites)
        #expect(mapping[.history] == .history)
    }

    /// A browser's bookmark tree sitting beside its own sidebar folders is
    /// the duplicate: both arriving as pinned folders is what had to be undone.
    @Test("Bookmark folders default to Skip when the source has pinned folders of its own")
    func bookmarkFoldersDefaultToSkipWhenPinnedFoldersExist() {
        #expect(ImportMapping(counts: [.pinnedFolders: 1, .bookmarkFolders: 44])[.bookmarkFolders] == .skip)
        #expect(ImportMapping(counts: [.bookmarkFolders: 44])[.bookmarkFolders] == .pinnedFolders)
    }

    @Test("Only categories with something in them are listed, in a fixed order")
    func listsOnlyWhatIsThere() {
        let mapping = ImportMapping(counts: [.history: 5, .bookmarkFolders: 44, .favorites: 0, .bookmarkBar: 1])
        #expect(mapping.categories == [.bookmarkBar, .bookmarkFolders, .history])
    }

    /// A folder is a list of tabs and §3.3's grid is one tab per tile, so a
    /// folder cannot be offered as tiles.
    @Test("A destination a category does not offer is refused")
    func refusesAnUnofferedDestination() {
        var mapping = ImportMapping(counts: [.bookmarkFolders: 3])
        mapping[.bookmarkFolders] = .favorites
        #expect(mapping[.bookmarkFolders] == .pinnedFolders)
        mapping[.bookmarkFolders] = .skip
        #expect(mapping[.bookmarkFolders] == .skip)
    }

    @Test("Skip places nothing")
    func skipPlacesNothing() {
        var mapping = ImportMapping(counts: [.bookmarkBar: 1])
        mapping[.bookmarkBar] = .skip
        #expect(mapping.placement(of: .bookmarkBar, folderPath: [], browser: "Dia") == nil)
    }

    /// A Luna folder holds tabs, not folders (§3.4b), so the path is the name:
    /// it keeps both names and cannot collide with another `Archive`.
    @Test("A nested folder lands as one folder named by its path")
    func nestedFolderKeepsBothNames() {
        let mapping = ImportMapping(counts: [.bookmarkFolders: 1])
        #expect(
            mapping.placement(of: .bookmarkFolders, folderPath: ["Work", "Archive"], browser: "Dia")
                == .folder("Work / Archive")
        )
    }

    /// §3.4b's tier holds folders and nothing else, so a loose item sent there
    /// goes in the folder named after the browser.
    @Test("A loose item sent to pinned folders lands in the browser's folder")
    func looseItemLandsInTheBrowsersFolder() {
        var mapping = ImportMapping(counts: [.bookmarkBar: 1])
        mapping[.bookmarkBar] = .pinnedFolders
        #expect(mapping.placement(of: .bookmarkBar, folderPath: [], browser: "Dia") == .folder("Dia"))
        mapping[.bookmarkBar] = .favorites
        #expect(mapping.placement(of: .bookmarkBar, folderPath: [], browser: "Dia") == .favorite)
    }
}
