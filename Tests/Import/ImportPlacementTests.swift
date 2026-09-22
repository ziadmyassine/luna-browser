//
//  ImportPlacementTests.swift
//  LunaTests
//
//  Where an imported bookmark lands. §23.2 reads a bookmark; Luna has no
//  bookmarks table (§11.1), so what it writes is a `Tab` — a saved one, inside
//  a §3.4b folder named after the browser it came from.
//
//  The two things that go wrong silently:
//
//  · The folder. Bookmarks that arrive loose are mixed into whatever the user
//    had already saved, and there is then no gesture that undoes an import.
//  · One URL in two of the source's folders is one row here, because Luna
//    keeps one folder per import rather than the source's tree.
//

import BrowserKit
import XCTest
@testable import Luna

final class ImportPlacementTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-placement-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Every bookmark lands in one folder, named after where it came from,
    /// and every one of them is saved.
    func testEveryBookmarkLandsInTheImportsOwnFolder() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: try write(favourites: 20))

        let spaceID = try XCTUnwrap(summary.targetSpaceID)
        let groups = try await store.groups(inSpace: spaceID)
        XCTAssertEqual(groups.count, 1, "an import makes one folder")
        let folder = try XCTUnwrap(groups.first)
        XCTAssertEqual(folder.name, "bar-20", "the folder is named after the source")
        XCTAssertEqual(folder.kind, .pinned, "an import is something kept")

        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        XCTAssertEqual(tabs.count, 20)
        XCTAssertTrue(tabs.allSatisfy { $0.groupID == folder.id }, "a bookmark landed outside the folder")
        XCTAssertTrue(tabs.allSatisfy { $0.kind == .pinned })
    }

    /// The bookmarks bar is not special any more. It used to become §3.3's
    /// tiles, which cannot be in a folder — so a bar of four left four
    /// bookmarks outside the one the user was told to look in.
    func testTheBookmarksBarGoesInTheFolderToo() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: try write(favourites: 4))

        let spaceID = try XCTUnwrap(summary.targetSpaceID)
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        XCTAssertEqual(tabs.count, 4)
        XCTAssertTrue(tabs.allSatisfy { $0.kind == .pinned })
        let favorites = try await store.favorites(inSpace: spaceID)
        XCTAssertTrue(favorites.isEmpty, "an import made a tile")
    }

    /// A second import of the same source lands in the folder that is already
    /// there rather than making "Safari 2".
    func testASecondImportReusesTheFolder() async throws {
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: try makeLedger())
        let file = try write(favourites: 3)
        let first = try await importer.importBookmarks(htmlAt: file)
        let spaceID = try XCTUnwrap(first.targetSpaceID)
        _ = try await importer.importBookmarks(htmlAt: file, into: spaceID)

        let groups = try await store.groups(inSpace: spaceID)
        XCTAssertEqual(groups.count, 1)
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        XCTAssertEqual(tabs.count, 3)
    }

    /// The same site filed in two folders is one row. It reads like a loss and
    /// is not: with no folder to tell them apart they would be two identical
    /// tabs in one Space.
    func testOneURLInTwoFoldersLandsOnce() async throws {
        let store = try makeStore()
        let repeated = URL(string: "https://example.com/reference")!
        let html = NetscapeBookmarks.write(
            [
                ImportedBookmark(url: repeated, title: "Reference", folderPath: ["Work"], placement: .folder),
                ImportedBookmark(url: repeated, title: "Reference", folderPath: ["Home"], placement: .folder)
            ],
            title: "Bookmarks"
        )
        let file = directory.appending(path: "twice.html")
        try Data(html.utf8).write(to: file)

        let summary = try await BrowserImporter(store: store, ledger: makeLedger()).importBookmarks(htmlAt: file)
        XCTAssertEqual(summary.bookmarksAdded, 1)
        XCTAssertEqual(summary.bookmarksSkipped, 1)
        let tabs = try await store.tabs(inSpace: try XCTUnwrap(summary.targetSpaceID), includeArchived: true)
        XCTAssertEqual(tabs.count, 1)
    }

    // MARK: - Fixtures

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna-\(UUID().uuidString).sqlite"))
    }

    private func makeLedger() throws -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: "ledger-\(UUID().uuidString).json"))
    }

    /// A bookmarks bar of `favourites` loose links, written in the format every
    /// browser exports and `NetscapeBookmarks` reads back.
    private func write(favourites: Int) throws -> URL {
        let bookmarks = (0..<favourites).map { index in
            ImportedBookmark(
                url: URL(string: "https://site\(index).example/")!,
                title: "Site \(index)",
                placement: .favorite
            )
        }
        let file = directory.appending(path: "bar-\(favourites).html")
        try Data(NetscapeBookmarks.write(bookmarks, title: "Bookmarks").utf8).write(to: file)
        return file
    }
}
