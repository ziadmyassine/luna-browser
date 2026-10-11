//
//  BookmarkTreeImportTests.swift
//  LunaTests
//
//  §23.2's folder tree. The sidebar keeps one level of folders, so the tree an
//  import arrived with is kept in `bookmarks` beside it, and the HTML export
//  (§23.4) writes that tree back out rather than the flat folder.
//

import BrowserKit
import XCTest
@testable import Luna

final class BookmarkTreeImportTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-tree-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The source's tree: a bar link, two levels of folder, and one page filed
    /// in two folders.
    private let source = [
        ImportedBookmark(url: URL(string: "https://bar.example/")!, title: "Bar", placement: .favorite),
        ImportedBookmark(url: URL(string: "https://deep.example/")!, title: "Deep", folderPath: ["Work", "Deep"]),
        ImportedBookmark(url: URL(string: "https://ref.example/")!, title: "Ref", folderPath: ["Work"]),
        ImportedBookmark(url: URL(string: "https://ref.example/")!, title: "Ref", folderPath: ["Home"])
    ]

    private struct Leaf: Hashable {
        var url: String
        var path: [String]
    }

    private var sourceLeaves: Set<Leaf> {
        Set(source.map { Leaf(url: $0.url.absoluteString, path: $0.folderPath) })
    }

    func testAnImportKeepsTheTree() async throws {
        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger()).importBookmarks(htmlAt: writeSource())
        let spaceID = try XCTUnwrap(summary.targetSpaceID)

        let tree = try await store.bookmarks(inSpace: spaceID)
        XCTAssertEqual(Set(tree.map { Leaf(url: $0.url.absoluteString, path: $0.folderPath) }), sourceLeaves)
        // The sidebar is unchanged: one folder, one row per page.
        let groups = try await store.groups(inSpace: spaceID)
        XCTAssertEqual(groups.count, 1)
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        XCTAssertEqual(tabs.count, 3)
    }

    func testASecondImportAddsNoBranches() async throws {
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: try makeLedger())
        let file = try writeSource()
        let first = try await importer.importBookmarks(htmlAt: file)
        let spaceID = try XCTUnwrap(first.targetSpaceID)
        let second = try await importer.importBookmarks(htmlAt: file, into: spaceID)

        XCTAssertEqual(second.bookmarksAdded, 0)
        let tree = try await store.bookmarks(inSpace: spaceID)
        XCTAssertEqual(tree.count, source.count)
    }

    func testADryRunRecordsNoTree() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let spaceID = try await store.spaces()[0].id
        _ = try await BrowserImporter(store: store, ledger: makeLedger())
            .importBookmarks(htmlAt: writeSource(), into: spaceID, dryRun: true)
        let tree = try await store.bookmarks(inSpace: spaceID)
        XCTAssertTrue(tree.isEmpty)
    }

    /// Import, export, parse: the same leaves under the same folders, the page
    /// in two folders in both, and the bar link back on the bar.
    func testTheExportRoundTripsTheTree() async throws {
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: try makeLedger())
        let summary = try await importer.importBookmarks(htmlAt: writeSource())
        let spaceID = try XCTUnwrap(summary.targetSpaceID)

        let exported = NetscapeBookmarks.parse(try await importer.exportBookmarksHTML(spaceID: spaceID))
        XCTAssertEqual(Set(exported.map { Leaf(url: $0.url.absoluteString, path: $0.folderPath) }), sourceLeaves)
        XCTAssertEqual(exported.first { $0.folderPath.isEmpty }?.placement, .favorite)
    }

    /// A tab the user saved themselves still exports, and a deleted import does
    /// not: the sidebar decides what goes out, the tree decides where.
    func testTheExportFollowsTheSidebar() async throws {
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: try makeLedger())
        let summary = try await importer.importBookmarks(htmlAt: writeSource())
        let spaceID = try XCTUnwrap(summary.targetSpaceID)
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        let deep = try XCTUnwrap(tabs.first { $0.url.host() == "deep.example" })
        try await store.delete(tabID: deep.id)
        try await store.upsert(Tab(spaceID: spaceID, kind: .pinned, url: URL(string: "https://mine.example/")!, title: "Mine"))

        let exported = NetscapeBookmarks.parse(try await importer.exportBookmarksHTML(spaceID: spaceID))
        let hosts = Set(exported.compactMap { $0.url.host() })
        XCTAssertFalse(hosts.contains("deep.example"))
        XCTAssertTrue(hosts.contains("mine.example"))
    }

    // MARK: - Fixtures

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna-\(UUID().uuidString).sqlite"))
    }

    private func makeLedger() throws -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: "ledger-\(UUID().uuidString).json"))
    }

    private func writeSource() throws -> URL {
        let file = directory.appending(path: "tree.html")
        try Data(NetscapeBookmarks.write(source).utf8).write(to: file)
        return file
    }
}
