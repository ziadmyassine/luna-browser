//
//  ImportPlacementTests.swift
//  LunaTests
//
//  Where an imported bookmark lands. §23.2 reads a bookmark; Luna has no
//  bookmarks table (§11.1), so what it writes is a `Tab`, and the tier it
//  picks is the whole of the decision — three things that are wrong silently:
//
//  · Favorites are capped at twelve per Profile and a bookmarks bar is
//    routinely longer. Written over the cap the rows look right until `v2`'s
//    migration next runs and demotes whichever twelve it likes.
//  · `profileID` is the column that makes a Favorite a Favorite. Left nil the
//    tile still draws — the session derives the Profile from the Space — and
//    `favorites(onProfile:)` cannot see it.
//  · One URL in two folders is one row here, because there are no folders to
//    tell the two apart.
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

    /// Twenty bookmarks on the bar, twelve tiles. The rest are pinned rather
    /// than dropped: past the cap a bookmark is still a thing the user kept.
    func testTheFavoritesCapIsAppliedOnTheWayIn() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: try write(favourites: 20))

        XCTAssertEqual(summary.bookmarksAdded, 20, "the cap must place a bookmark, not discard it")
        let tabs = try await store.tabs(inSpace: try XCTUnwrap(summary.targetSpaceID), includeArchived: true)
        XCTAssertEqual(tabs.filter { $0.kind == .essential }.count, BrowserStore.favoritesCap)
        XCTAssertEqual(tabs.filter { $0.kind == .pinned }.count, 20 - BrowserStore.favoritesCap)
    }

    /// And the twelve belong to a Profile, which is what `favorites(onProfile:)`
    /// answers for. Nothing else carries the column.
    func testAnImportedFavoriteBelongsToAProfile() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: try write(favourites: 20))

        let spaceID = try XCTUnwrap(summary.targetSpaceID)
        let spaces = try await store.spaces()
        let space = try XCTUnwrap(spaces.first { $0.id == spaceID })
        let favorites = try await store.favorites(onProfile: space.profileID)
        XCTAssertEqual(favorites.count, BrowserStore.favoritesCap, "the tiles are invisible to their own Profile")

        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        for tab in tabs where tab.kind != .essential {
            XCTAssertNil(tab.profileID, "\(tab.title) is not a Favorite and should carry no Profile")
        }
    }

    /// A bookmarks bar under the cap is all tiles, so the cap is a ceiling
    /// rather than a rule that fires on every import.
    func testASmallBarIsAllTiles() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: try write(favourites: 4))

        let tabs = try await store.tabs(inSpace: try XCTUnwrap(summary.targetSpaceID), includeArchived: true)
        XCTAssertEqual(tabs.filter { $0.kind == .essential }.count, 4)
        XCTAssertTrue(tabs.allSatisfy { $0.profileID != nil })
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
