//
//  DiaMappingTests.swift
//  Luna — §23.2
//
//  The Dia import through its mapping step. Dia 1.51 keeps its sidebar —
//  pinned tabs, pinned folders, favourites — in an encrypted `tabs.db`, so
//  what Luna can read is the Chromium `Bookmarks` tree, `History`, and an
//  older install's `StorableProfileContainers.json`. Before the step, the
//  bookmark tree arrived as pinned folders whether or not that was wanted.
//
//  The fixture has the real file's shape — bar folders, one nested, a loose
//  bar URL, empty `other` and `synced` roots — and none of its contents.
//

import BrowserKit
import SQLite3
import XCTest
@testable import Luna

final class DiaMappingTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-dia-mapping-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Reading

    func testBookmarksAreTaggedByWhereTheyStood() throws {
        let bookmarks = try ChromiumReader.flatten(bookmarksJSON: Data(Self.bookmarks.utf8))
        let byURL = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.url.host() ?? "", $0.category) })
        XCTAssertEqual(byURL["loose.example"], .bookmarkBar)
        XCTAssertEqual(byURL["work-one.example"], .bookmarkFolders)
        XCTAssertEqual(byURL["archive.example"], .bookmarkFolders)
    }

    func testTheStartingMappingCountsWhatDiaHas() throws {
        let mapping = try reader().defaultMapping()
        XCTAssertEqual(mapping.categories, [.favorites, .bookmarkBar, .bookmarkFolders, .history])
        XCTAssertEqual(mapping.counts[.bookmarkFolders], 5)
        XCTAssertEqual(mapping.counts[.bookmarkBar], 1)
        XCTAssertEqual(mapping.counts[.favorites], 1)
        XCTAssertEqual(mapping.counts[.history], 2)
        XCTAssertEqual(mapping[.bookmarkFolders], .pinnedFolders, "Dia exposes no pinned folders of its own")
    }

    // MARK: - Writing

    func testTheDefaultMappingKeepsFoldersAndTiles() async throws {
        let (store, summary) = try await runImport(mapping: nil)
        let space = try await onlyImportedSpace(store)
        let folders = try await store.groups(inSpace: space)
        XCTAssertEqual(folders.map(\.name), ["Work", "Work / Archive", "Reading"])
        let tiles = try await store.favorites(inSpace: space)
        XCTAssertEqual(Set(tiles.map { $0.url.host() ?? "" }), ["favourite.example", "loose.example"])
        XCTAssertEqual(summary.visitsAdded, 2)
    }

    func testSkipWritesNothing() async throws {
        var mapping = try reader().defaultMapping()
        for category in mapping.categories { mapping[category] = .skip }
        let (store, summary) = try await runImport(mapping: mapping)

        XCTAssertEqual(summary.bookmarksAdded, 0)
        XCTAssertEqual(summary.visitsAdded, 0)
        for space in try await store.spaces() {
            let tabs = try await store.tabs(inSpace: space.id, includeArchived: true)
            let groups = try await store.groups(inSpace: space.id)
            XCTAssertTrue(tabs.isEmpty && groups.isEmpty, "a skipped import left something in \(space.name)")
        }
    }

    /// The owner's case: the bookmark tree is not wanted as pinned folders.
    func testSkippingBookmarkFoldersKeepsTheRest() async throws {
        var mapping = try reader().defaultMapping()
        mapping[.bookmarkFolders] = .skip
        let (store, summary) = try await runImport(mapping: mapping)
        let space = try await onlyImportedSpace(store)

        let groups = try await store.groups(inSpace: space)
        XCTAssertTrue(groups.isEmpty, "got \(groups.map(\.name))")
        let tiles = try await store.favorites(inSpace: space)
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(summary.bookmarksAdded, 2)
    }

    func testNestedFolderKeepsBothNamesAndOrder() async throws {
        let (store, _) = try await runImport(mapping: nil)
        let space = try await onlyImportedSpace(store)
        let folders = try await store.groups(inSpace: space).sorted { $0.order < $1.order }
        XCTAssertEqual(folders.map(\.name), ["Work", "Work / Archive", "Reading"])

        let work = try XCTUnwrap(folders.first { $0.name == "Work" })
        let tabs = try await store.tabs(inSpace: space, includeArchived: true)
            .filter { $0.groupID == work.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(tabs.map(\.title), ["Work One", "Work Two"])
    }

    /// The favourite is also filed in `Reading`. One Space, one row per URL.
    func testSameURLInTwoCategoriesLandsOnce() async throws {
        let (store, summary) = try await runImport(mapping: nil)
        let space = try await onlyImportedSpace(store)
        let tabs = try await store.tabs(inSpace: space, includeArchived: true)
        XCTAssertEqual(tabs.filter { $0.url.host() == "favourite.example" }.count, 1)
        XCTAssertEqual(summary.bookmarksSkipped, 1)
    }

    func testBookmarkBarCanGoToPinnedFolders() async throws {
        var mapping = try reader().defaultMapping()
        mapping[.bookmarkBar] = .pinnedFolders
        let (store, _) = try await runImport(mapping: mapping)
        let space = try await onlyImportedSpace(store)
        let folders = try await store.groups(inSpace: space)
        XCTAssertTrue(folders.contains { $0.name == "Dia" }, "got \(folders.map(\.name))")
        let tiles = try await store.favorites(inSpace: space)
        XCTAssertEqual(tiles.map { $0.url.host() ?? "" }, ["favourite.example"])
    }

    // MARK: - Plumbing

    private func runImport(mapping: ImportMapping?) async throws -> (BrowserStore, ImportSummary) {
        let store = try BrowserStore(path: directory.appending(path: "luna-\(UUID().uuidString).sqlite"))
        let summary = try await BrowserImporter(
            store: store,
            ledger: ImportLedger(fileURL: directory.appending(path: "ledger-\(UUID().uuidString).json"))
        ).run(
            reader: try reader(),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia — Main",
            folderName: "Dia",
            mapping: mapping
        )
        return (store, summary)
    }

    private func onlyImportedSpace(_ store: BrowserStore) async throws -> UUID {
        let spaces = try await store.spaces()
        return try XCTUnwrap(spaces.first { $0.name == "Dia — Main" }).id
    }

    private func reader() throws -> ChromiumReader {
        let profile = directory.appending(path: "Profile 1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data(Self.bookmarks.utf8).write(to: profile.appending(path: "Bookmarks"))
        try makeHistory(at: profile.appending(path: "History"))
        let sidebar = directory.appending(path: "StorableProfileContainers.json")
        try Data(Self.containers.utf8).write(to: sidebar)
        return try ChromiumReader.snapshot(
            profileDirectory: profile,
            sidebar: .dia(fileName: "StorableProfileContainers.json", profileDirectory: "Profile 1"),
            sidebarFile: sidebar,
            into: ImportSnapshot()
        )
    }

    private func makeHistory(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw XCTSkip("couldn't create the fixture database")
        }
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE urls(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
            last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL);
        CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL, transition INTEGER DEFAULT 0 NOT NULL);
        INSERT INTO urls VALUES(1, 'https://visited.example/', 'Visited', 13429579614840426, 0);
        INSERT INTO visits VALUES(1, 1, 13429579614840426, 1);
        INSERT INTO visits VALUES(2, 1, 13429579615840426, 0);
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("couldn't populate the fixture database")
        }
    }

    // MARK: - Fixtures

    /// The real file's shape: bar folders, one nested inside another, a loose
    /// bar URL after them, and the `other` and `synced` roots empty.
    private static let bookmarks = """
    {"checksum":"0","roots":{
      "bookmark_bar":{"children":[
        {"type":"folder","name":"Work","guid":"F1","id":"2","date_added":"13429579614840426","children":[
          {"type":"url","name":"Work One","url":"https://work-one.example/","guid":"U1","id":"3","date_added":"13429579614840426"},
          {"type":"url","name":"Work Two","url":"https://work-two.example/","guid":"U2","id":"4","date_added":"13429579614840427"},
          {"type":"folder","name":"Archive","guid":"F2","id":"5","children":[
            {"type":"url","name":"Old","url":"https://archive.example/","guid":"U3","id":"6","date_added":"13429579614840428"}
          ]}
        ]},
        {"type":"folder","name":"Reading","guid":"F3","id":"7","children":[
          {"type":"url","name":"Also A Favourite","url":"https://favourite.example/","guid":"U4","id":"8"},
          {"type":"url","name":"Essay","url":"https://reading.example/","guid":"U6","id":"12"}
        ]},
        {"type":"url","name":"Loose","url":"https://loose.example/","guid":"U5","id":"9"}
      ],"name":"Bookmarks bar","type":"folder","id":"1"},
      "other":{"children":[],"name":"Other bookmarks","type":"folder","id":"10"},
      "synced":{"children":[],"name":"Mobile bookmarks","type":"folder","id":"11"}
    },"version":1}
    """

    /// An older Dia's favourites file, with the profile this import reads.
    private static let containers = """
    {"version":3,"containers":[
      {"id":{"profileID":"Profile 1","container":{"favorites":{}}},
       "tabs":[{"id":"T1","creationDate":784409165.3,
         "contents":[{"id":"C1","variant":{"webContent":{"_0":{"url":"https://favourite.example/","title":"Favourite"}}}}]}]}
    ]}
    """
}
