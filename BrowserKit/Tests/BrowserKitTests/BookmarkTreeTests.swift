@testable import BrowserKit
import Foundation
import GRDB
import Testing

/// `v18`'s `bookmarks` table: the folder tree an import arrived with, kept beside the
/// one-level sidebar folders its tabs were written into.
@Suite("Bookmark tree (§23.2)")
struct BookmarkTreeTests {

    private let page = URL(string: "https://physics.example/notes")!

    @Test func theMigrationMakesTheTable() async throws {
        let path = temporaryDatabasePath()
        _ = try BrowserStore(path: path)
        let exists = try await DatabaseQueue(path: path.path).read { try $0.tableExists("bookmarks") }
        #expect(exists)
    }

    /// The same page under two folders is two branches of the tree, and a slash inside a
    /// folder's name is part of the name, not a level.
    @Test func keepsEveryBranchAndEveryName() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let added = try await store.recordBookmarks([
            Bookmark(spaceID: space, url: page, title: "Notes", folderPath: ["IA", "Physics"]),
            Bookmark(spaceID: space, url: page, title: "Notes", folderPath: ["A/B"]),
            Bookmark(spaceID: space, url: page, title: "Notes", folderPath: [])
        ])
        #expect(added == 3)
        let paths = try await store.bookmarks(inSpace: space).map(\.folderPath)
        #expect(paths == [["IA", "Physics"], ["A/B"], []])
    }

    /// Recording the same tree twice adds nothing: a re-import is a no-op.
    @Test func recordingTwiceAddsNothing() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let tree = [Bookmark(spaceID: space, url: page, title: "Notes", folderPath: ["IA"])]
        #expect(try await store.recordBookmarks(tree) == 1)
        #expect(try await store.recordBookmarks(tree) == 0)
        #expect(try await store.bookmarks(inSpace: space).count == 1)
    }

    /// The tree belongs to its Space and goes with it.
    @Test func deletingTheSpaceDeletesItsTree() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = Space(name: "Work", symbolName: "hammer", gradient: .defaultSpace)
        try await store.upsert(other)
        try await store.recordBookmarks([Bookmark(spaceID: other.id, url: page, title: "Notes", folderPath: ["IA"])])
        try await store.delete(spaceID: other.id)
        #expect(try await store.bookmarks(inSpace: other.id).isEmpty)
        #expect(try await store.bookmarks(inSpace: space).isEmpty)
    }
}
