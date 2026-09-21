//
//  SidebarImportTests.swift
//  LunaTests
//
//  §23.2: the saved tabs Arc and Dia keep outside the Chromium profile.
//
//  This file exists because the import was quietly delivering half of itself.
//  Measured against the real browsers on this Mac: an Arc import reported
//  `bookmarks + 0` and brought across nothing but 21 visits, while 118 saved
//  tabs sat in `StorableSidebar.json`; Dia reported `bookmarks + 0` with 8
//  favourites in `StorableProfileContainers.json`. Neither was an error and
//  neither showed a warning — the summary said zero and zero was wrong.
//
//  Fixtures, never the installed browsers: the real files change under the test
//  and are not on every machine. The shapes below are trimmed copies of the
//  real ones, including the parts that are easy to get wrong — Arc interleaving
//  item ids with item objects in one array, and Dia keeping two profiles and an
//  open window in the same file as the favourites.
//

import BrowserKit
import XCTest
@testable import Luna

final class SidebarImportTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-sidebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Arc

    /// Arc's array holds item ids and item objects side by side, and only the
    /// objects carrying `data.tab.savedURL` are saved tabs. The rest are
    /// folders, easels and split views — none of them an address.
    func testArcReadsItsSavedTabsAndSkipsEverythingElse() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))

        XCTAssertEqual(bookmarks.map(\.url.absoluteString), [
            "https://example.com/kept",
            "https://example.com/second"
        ])
        XCTAssertEqual(bookmarks.first?.title, "Renamed By Hand", "the item's own title outranks the page's")
        XCTAssertEqual(bookmarks.last?.title, "Saved Title", "and the page's is the fallback")
    }

    /// `arc://` is Arc's own furniture, not somewhere Luna can go, and a row
    /// for one would be a tab that opens nothing in the folder just made.
    func testArcLeavesItsOwnInternalPagesBehind() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        XCTAssertFalse(bookmarks.contains { $0.url.scheme != "https" })
    }

    /// The same page pinned in two Arc Spaces is one bookmark. §3.4b puts one
    /// import in one folder, so two rows for it would be two identical tabs.
    func testArcCollapsesAPagePinnedTwice() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        XCTAssertEqual(Set(bookmarks.map(\.url)).count, bookmarks.count)
    }

    /// Arc dates in seconds since 2001 — it is a Swift app writing `Date`
    /// through `Codable`, not Chromium writing microseconds since 1601. Read as
    /// Chromium's, every bookmark would arrive dated some time in the year
    /// 25000.
    func testArcDatesDecodeAsTheReferenceDate() throws {
        let when = try XCTUnwrap(ArcSidebar.parse(Data(Self.arcSidebar.utf8)).first?.dateAdded)
        XCTAssertEqual(when.timeIntervalSinceReferenceDate, 747_565_943.657964, accuracy: 0.001)
    }

    /// A shape Luna does not recognise costs the sidebar and nothing else: the
    /// `Bookmarks` half and the history have their own answers already.
    func testAnUnreadableArcSidebarIsNoSavedTabsRatherThanAFailure() {
        XCTAssertTrue(ArcSidebar.parse(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(ArcSidebar.parse(Data(#"{"sidebar":{}}"#.utf8)).isEmpty)
    }

    // MARK: - Dia

    /// Dia's file is one per app and holds every profile, so importing `Work`
    /// must not hand over `Personal`'s favourites.
    func testDiaTakesOnlyThePickedProfilesFavourites() throws {
        let data = Data(Self.diaContainers.utf8)

        let personal = DiaFavorites.parse(data, profileDirectory: "Default")
        XCTAssertEqual(personal.map(\.url.absoluteString), ["https://example.com/personal"])

        let work = DiaFavorites.parse(data, profileDirectory: "Profile 2")
        XCTAssertEqual(work.map(\.url.absoluteString), ["https://example.com/work"])
    }

    /// The same file carries the open window. Those are working state rather
    /// than things kept — the rule `exportBookmarksHTML` already keeps when it
    /// leaves today's tabs out of an export.
    func testDiaLeavesTheOpenWindowAlone() throws {
        let bookmarks = DiaFavorites.parse(Data(Self.diaContainers.utf8), profileDirectory: "Default")
        XCTAssertFalse(bookmarks.contains { $0.url.path().contains("open-right-now") })
    }

    /// A favourite that is a new-tab page has no address to import.
    func testDiaSkipsATabWithNoPageInIt() throws {
        let bookmarks = DiaFavorites.parse(Data(Self.diaContainers.utf8), profileDirectory: "Default")
        XCTAssertEqual(bookmarks.count, 1)
    }

    // MARK: - The whole run

    /// Arc end to end: a profile with a `History` and no `Bookmarks` file at
    /// all — which is every Arc profile — still delivers its sidebar.
    func testAnArcProfileWithNoBookmarksFileStillImportsItsSidebar() async throws {
        let profile = directory.appending(path: "Default", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let sidebarFile = directory.appending(path: "StorableSidebar.json")
        try Data(Self.arcSidebar.utf8).write(to: sidebarFile)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: profile.appending(path: "Bookmarks").path),
            "the premise: Arc writes no Bookmarks file"
        )

        let snapshot = try ImportSnapshot()
        let reader = try ChromiumReader.snapshot(
            profileDirectory: profile,
            sidebar: .arc(fileName: "StorableSidebar.json"),
            sidebarFile: sidebarFile,
            into: snapshot
        )
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let summary = try await BrowserImporter(store: store, ledger: makeLedger())
            .run(reader: reader, ledgerKey: "arc/Default", spaceName: "Arc", folderName: "Arc")

        XCTAssertEqual(summary.bookmarksAdded, 2)
        XCTAssertEqual(summary.failed, 0)
        let spaceID = try XCTUnwrap(summary.targetSpaceID)
        let groups = try await store.groups(inSpace: spaceID)
        XCTAssertEqual(groups.map(\.name), ["Arc"], "§3.4b: one import, one folder")
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertTrue(tabs.allSatisfy { $0.groupID == groups.first?.id })
    }

    /// A second Arc import adds nothing. The sidebar has no watermark of its
    /// own — it is deduplicated against the Space by URL, like every other
    /// bookmark — so this is the claim that path is actually on.
    func testASecondArcImportAddsNothing() async throws {
        let profile = directory.appending(path: "Default", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let sidebarFile = directory.appending(path: "StorableSidebar.json")
        try Data(Self.arcSidebar.utf8).write(to: sidebarFile)
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let importer = BrowserImporter(store: store, ledger: makeLedger())

        func run() async throws -> ImportSummary {
            let snapshot = try ImportSnapshot()
            let reader = try ChromiumReader.snapshot(
                profileDirectory: profile,
                sidebar: .arc(fileName: "StorableSidebar.json"),
                sidebarFile: sidebarFile,
                into: snapshot
            )
            return try await importer.run(reader: reader, ledgerKey: "arc/Default", spaceName: "Arc", folderName: "Arc")
        }

        let first = try await run()
        XCTAssertEqual(first.bookmarksAdded, 2)
        let second = try await run()
        XCTAssertEqual(second.bookmarksAdded, 0)
        XCTAssertEqual(second.bookmarksSkipped, 2)
        let spaceID = try XCTUnwrap(second.targetSpaceID)
        let tabs = try await store.tabs(inSpace: spaceID, includeArchived: true)
        let groups = try await store.groups(inSpace: spaceID)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(groups.count, 1)
    }

    private func makeLedger() -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: "ledger-\(UUID().uuidString).json"))
    }

    // MARK: - Fixtures

    /// Trimmed from the real file. Two saved tabs, one of them pinned twice,
    /// plus the three kinds of item that are not addresses.
    private static let arcSidebar = """
    {"sidebar":{"containers":[
      {"global":{}},
      {"items":[
        "A08933E5-FDB0-4ECB-BC1E-CDAE90576CFD",
        {"id":"1","title":"Renamed By Hand","createdAt":747565943.657964,
         "data":{"tab":{"savedURL":"https://example.com/kept","savedTitle":"Page Title"}}},
        "B08933E5-FDB0-4ECB-BC1E-CDAE90576CFD",
        {"id":"2","createdAt":747565999.0,
         "data":{"tab":{"savedURL":"https://example.com/second","savedTitle":"Saved Title"}}},
        {"id":"3","title":"A Folder","childrenIds":["1","2"],"data":{"list":{}}},
        {"id":"4","title":"An Easel","data":{"easel":{"easelID":"E1"}}},
        {"id":"5","title":"Arc Max","data":{"tab":{"savedURL":"arc://settings"}}}
      ],"spaces":[]},
      {"items":[
        {"id":"6","title":"Renamed By Hand","createdAt":747566000.0,
         "data":{"tab":{"savedURL":"https://example.com/kept","savedTitle":"Page Title"}}}
      ],"spaces":[]}
    ]},"version":1}
    """

    /// Two profiles' favourites and one open window, the way Dia writes them.
    private static let diaContainers = """
    {"version":3,"containers":[
      {"id":{"profileID":"Default","container":{"favorites":{}}},
       "tabs":[
         {"id":"T1","creationDate":784409165.313087,
          "contents":[{"id":"C1","variant":{"webContent":{"_0":{"url":"https://example.com/personal","title":"Personal"}}}}]},
         {"id":"T2","creationDate":784409165.5,"contents":[{"id":"C2","variant":{"newTabPage":{}}}]}
       ]},
      {"id":{"profileID":"Profile 2","container":{"favorites":{}}},
       "tabs":[
         {"id":"T3","creationDate":784409166.0,
          "contents":[{"id":"C3","variant":{"webContent":{"_0":{"url":"https://example.com/work","title":"Work"}}}}]}
       ]},
      {"id":{"profileID":"Default","container":{"window":{"_0":"8EE05723"}}},
       "tabs":[
         {"id":"T4","creationDate":786767267.952417,
          "contents":[{"id":"C4","variant":{"webContent":{"_0":{"url":"https://example.com/open-right-now","title":"Open"}}}}]}
       ]}
    ]}
    """
}
