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

    /// Arc's Spaces survive the crossing, with each Space's own items in it.
    func testArcKeepsItsSpaces() {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        XCTAssertEqual(Set(bookmarks.compactMap(\.spaceName)), ["School", "Personal"])
        let school = bookmarks.filter { $0.spaceName == "School" }
        XCTAssertTrue(school.contains { $0.url.absoluteString == "https://ibphysics.example/topic2" })
        XCTAssertFalse(school.contains { $0.url.absoluteString == "https://copilot.example/" })
    }

    /// A folder inside a folder becomes one folder named by its path. A Luna
    /// folder holds tabs and not other folders (§3.4b), and the path is the
    /// only spelling that keeps both names and cannot collide with another
    /// `Physics` under a different parent.
    func testArcFlattensANestedFolderOntoItsPath() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        let nested = try XCTUnwrap(bookmarks.first { $0.url.host() == "physics.example" && $0.spaceName == "School" })
        XCTAssertEqual(nested.folderPath, ["IA", "Physics"])
    }

    /// A pin that was loose in Arc's pinned tier carries no folder, and the
    /// writer is what gives it one.
    func testArcMarksALoosePinAsHavingNoFolder() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        let loose = try XCTUnwrap(bookmarks.first { $0.url.absoluteString == "https://copilot.example/" })
        XCTAssertTrue(loose.folderPath.isEmpty)
        XCTAssertEqual(loose.title, "Copilot", "the item's own title outranks the page's")
    }

    /// Arc's favourites belong to its profile, and every Space on that profile
    /// shows the same row — so every Space imported from it gets them, which is
    /// what the user is looking at in Arc. Another profile's row stays out.
    func testArcGivesEverySpaceItsProfilesFavourites() {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        let tiles = bookmarks.filter { $0.placement == .favorite }
        XCTAssertEqual(tiles.count, 2, "one per Space, from the default profile's row")
        XCTAssertEqual(Set(tiles.map(\.url.absoluteString)), ["https://outlook.example/mail"])
        XCTAssertFalse(bookmarks.contains { $0.url.host() == "other-profile.example" })
    }

    /// The unpinned tier is what Arc has open. Working state, not something
    /// kept — the rule the HTML export keeps when it leaves today's tabs out.
    func testArcLeavesItsOpenTabsBehind() {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        XCTAssertFalse(bookmarks.contains { $0.url.host() == "open-right-now.example" })
    }

    /// `arc://` is Arc's own furniture, and an easel has no address in it at
    /// all. A row for either would be a tab that opens nothing.
    func testArcSkipsWhatIsNotAnAddress() {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        XCTAssertTrue(bookmarks.allSatisfy { $0.url.scheme == "https" })
        XCTAssertFalse(bookmarks.contains { $0.title == "An Easel" })
    }

    /// The same page pinned in two Arc Spaces is two bookmarks, one per Space.
    /// Dedupe is per Space because a Space is what holds tabs, and collapsing
    /// them would take the page out of one of the two sidebars it was in.
    func testArcKeepsAPagePinnedInTwoSpacesInBoth() {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        let shared = bookmarks.filter { $0.url.absoluteString == "https://physics.example/uncertainties" }
        XCTAssertEqual(Set(shared.compactMap(\.spaceName)), ["School", "Personal"])
    }

    /// Arc dates in seconds since 2001 — it is a Swift app writing `Date`
    /// through `Codable`, not Chromium writing microseconds since 1601. Read as
    /// Chromium's, every bookmark would arrive dated in the year 25000.
    func testArcDatesDecodeAsTheReferenceDate() throws {
        let bookmarks = ArcSidebar.parse(Data(Self.arcSidebar.utf8))
        let one = try XCTUnwrap(bookmarks.first { $0.folderPath == ["IA", "Physics"] })
        XCTAssertEqual(
            try XCTUnwrap(one.dateAdded).timeIntervalSinceReferenceDate,
            747_565_943.657964,
            accuracy: 0.001
        )
    }

    /// A shape Luna does not recognise costs the sidebar and nothing else: the
    /// `Bookmarks` half and the history have their own answers already.
    func testAnUnreadableArcSidebarIsNoSavedTabsRatherThanAFailure() {
        XCTAssertTrue(ArcSidebar.parse(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(ArcSidebar.parse(Data(#"{"sidebar":{}}"#.utf8)).isEmpty)
        XCTAssertTrue(ArcSidebar.parse(Data(#"{"sidebar":{"containers":[{"spaces":[]}]}}"#.utf8)).isEmpty)
    }

    // MARK: - Dia

    /// Dia's file is one per app and holds every profile, so importing `Work`
    /// must not hand over `Personal`'s favourites.
    func testDiaTakesOnlyThePickedProfilesFavourites() {
        let data = Data(Self.diaContainers.utf8)
        XCTAssertEqual(
            DiaFavorites.parse(data, profileDirectory: "Default").map(\.url.absoluteString),
            ["https://example.com/personal"]
        )
        XCTAssertEqual(
            DiaFavorites.parse(data, profileDirectory: "Profile 2").map(\.url.absoluteString),
            ["https://example.com/work"]
        )
    }

    /// Dia's favourites are its one-click row, and a Dia profile is exactly one
    /// Luna Space — so they are §3.3's tiles, in the Space the profile makes.
    func testDiaFavouritesAreTilesInTheProfilesOwnSpace() {
        let bookmarks = DiaFavorites.parse(Data(Self.diaContainers.utf8), profileDirectory: "Default")
        XCTAssertTrue(bookmarks.allSatisfy { $0.placement == .favorite })
        XCTAssertTrue(bookmarks.allSatisfy { $0.spaceName == nil })
    }

    /// The same file carries the open window. Working state again.
    func testDiaLeavesTheOpenWindowAlone() {
        let bookmarks = DiaFavorites.parse(Data(Self.diaContainers.utf8), profileDirectory: "Default")
        XCTAssertFalse(bookmarks.contains { $0.url.path().contains("open-right-now") })
    }

    /// A favourite that is a new-tab page has no address to import.
    func testDiaSkipsATabWithNoPageInIt() {
        XCTAssertEqual(DiaFavorites.parse(Data(Self.diaContainers.utf8), profileDirectory: "Default").count, 1)
    }

    // MARK: - The whole run

    /// Arc end to end. A profile with a `History` and no `Bookmarks` file at
    /// all — which is every Arc profile — arrives as two Spaces, each with its
    /// own folders, its own tiles, and one folder named after the browser for
    /// whatever was loose in Arc's pinned tier.
    func testAnArcImportArrivesAsSpacesFoldersAndTiles() async throws {
        let (store, summary) = try await importArc()

        XCTAssertEqual(summary.spacesTouched, 2)
        XCTAssertEqual(summary.failed, 0)
        let spaces = try await store.spaces()
        let names = spaces.map(\.name)
        XCTAssertTrue(names.contains("Arc — School"), "got \(names)")
        XCTAssertTrue(names.contains("Arc — Personal"), "got \(names)")

        let school = try XCTUnwrap(spaces.first { $0.name == "Arc — School" })
        let folders = try await store.groups(inSpace: school.id)
        XCTAssertEqual(Set(folders.map(\.name)), ["IA / Physics", "Arc"])
        XCTAssertTrue(folders.allSatisfy { $0.kind == .pinned }, "§3.4b: the upper tier holds folders")
        let tiles = try await store.favorites(inSpace: school.id)
        XCTAssertEqual(tiles.map(\.url.absoluteString), ["https://outlook.example/mail"])
        let tabs = try await store.tabs(inSpace: school.id, includeArchived: true)
        XCTAssertTrue(
            tabs.filter { $0.kind == .pinned }.allSatisfy { $0.groupID != nil },
            "§3.4b: nothing is loose in the pinned tier"
        )
    }

    /// The Space names are prefixed with the browser. `resolveTargetSpace`
    /// reuses a Space of the same name, and Arc's `Personal` would otherwise
    /// land in the middle of Luna's own seeded `Personal`.
    func testAnArcSpaceDoesNotLandInsideAnExistingSpaceOfTheSameName() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let seeded = try await store.spaces()[0]

        _ = try await importArc(into: store)
        let inSeeded = try await store.tabs(inSpace: seeded.id, includeArchived: true)
        XCTAssertTrue(inSeeded.isEmpty, "Arc's Personal landed inside Luna's own Personal")
    }

    /// A second Arc import adds nothing. The sidebar has no watermark of its
    /// own — it deduplicates against each Space by URL, like every other
    /// bookmark — so this is the claim that path is actually on.
    func testASecondArcImportAddsNothing() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let first = try await importArc(into: store).1
        let second = try await importArc(into: store).1

        XCTAssertEqual(second.bookmarksAdded, 0)
        XCTAssertEqual(second.bookmarksSkipped, first.bookmarksAdded)
        let spaces = try await store.spaces()
        let school = try XCTUnwrap(spaces.first { $0.name == "Arc — School" })
        let folders = try await store.groups(inSpace: school.id)
        XCTAssertEqual(folders.count, 2, "no second set of folders")
    }

    /// A caller that named a Space has already said where everything goes, so
    /// the sidebar's own Spaces are not made — it flattens like any other
    /// source. That is what §30.17's "import into this Space" means.
    func testNamingASpaceFlattensTheSidebarIntoIt() async throws {
        let store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.seedIfEmpty()
        let into = try await store.spaces()[0]

        _ = try await importArc(into: store, targetSpaceID: into.id)
        let spaces = try await store.spaces()
        let folders = try await store.groups(inSpace: into.id)
        XCTAssertEqual(spaces.count, 1, "no Space was made")
        XCTAssertEqual(folders.map(\.name), ["Arc"], "one import, one folder")
    }

    // MARK: - Fixture plumbing

    @discardableResult
    private func importArc(
        into existing: BrowserStore? = nil,
        targetSpaceID: UUID? = nil
    ) async throws -> (BrowserStore, ImportSummary) {
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
        let store = try existing ?? BrowserStore(path: directory.appending(path: "luna.sqlite"))
        let summary = try await BrowserImporter(store: store, ledger: makeLedger()).run(
            reader: reader,
            ledgerKey: "arc/Default",
            spaceName: "Arc",
            folderName: "Arc",
            surfaces: .bookmarks,
            targetSpaceID: targetSpaceID
        )
        return (store, summary)
    }

    private func makeLedger() -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: "ledger-\(UUID().uuidString).json"))
    }

    // MARK: - Fixtures

    /// Trimmed from the real file, keeping every shape that is easy to get
    /// wrong: two Spaces, marker/id pairs in `containerIDs` and
    /// `topAppsContainerIDs`, a folder inside a folder, loose pins beside the
    /// folders, an unpinned container, and the three item kinds that are not
    /// addresses.
    private static let arcSidebar = """
    {"sidebar":{"containers":[
      {"global":{}},
      {
       "topAppsContainerIDs":[{"default":true},"TOPDEFAULT",{"custom":{"_0":{"directoryBasename":"Profile 3"}}},"TOPOTHER"],
       "spaces":[
         "B1F80AB0",
         {"id":"B1F80AB0","title":"School","profile":{"default":true},
          "containerIDs":["pinned","PINSCHOOL","unpinned","UNPINSCHOOL"]},
         {"id":"1666A263","title":"Personal","profile":{"default":true},
          "containerIDs":["pinned","PINPERSONAL","unpinned","UNPINPERSONAL"]}
       ],
       "items":[
         "A08933E5-FDB0-4ECB-BC1E-CDAE90576CFD",
         {"id":"fav1","parentID":"TOPDEFAULT","createdAt":747565900.0,
          "data":{"tab":{"savedURL":"https://outlook.example/mail","savedTitle":"Mail"}}},
         {"id":"fav2","parentID":"TOPOTHER","createdAt":747565900.0,
          "data":{"tab":{"savedURL":"https://other-profile.example/","savedTitle":"Not Ours"}}},

         {"id":"ia","parentID":"PINSCHOOL","title":"IA","childrenIds":["physics"],"data":{"list":{}}},
         {"id":"physics","parentID":"ia","title":"Physics","childrenIds":["p1"],"data":{"list":{}}},
         {"id":"p1","parentID":"physics","title":"Percentage Uncertainties","createdAt":747565943.657964,
          "data":{"tab":{"savedURL":"https://physics.example/uncertainties","savedTitle":"Page Title"}}},
         {"id":"loose1","parentID":"PINSCHOOL","createdAt":747565999.0,
          "data":{"tab":{"savedURL":"https://ibphysics.example/topic2","savedTitle":"Mechanics"}}},
         {"id":"easel","parentID":"PINSCHOOL","title":"An Easel","data":{"easel":{"easelID":"E1"}}},
         {"id":"internal","parentID":"PINSCHOOL","title":"Arc Max","data":{"tab":{"savedURL":"arc://settings"}}},
         {"id":"open1","parentID":"UNPINSCHOOL","createdAt":747566100.0,
          "data":{"tab":{"savedURL":"https://open-right-now.example/","savedTitle":"Open"}}},

         {"id":"bored","parentID":"PINPERSONAL","title":"Bored","childrenIds":["b1"],"data":{"list":{}}},
         {"id":"b1","parentID":"bored","createdAt":747566200.0,
          "data":{"tab":{"savedURL":"https://games.example/","savedTitle":"Online Games"}}},
         {"id":"loose2","parentID":"PINPERSONAL","title":"Copilot","createdAt":747566300.0,
          "data":{"tab":{"savedURL":"https://copilot.example/","savedTitle":"Microsoft Copilot"}}},
         {"id":"shared","parentID":"PINPERSONAL","createdAt":747566400.0,
          "data":{"tab":{"savedURL":"https://physics.example/uncertainties","savedTitle":"Page Title"}}}
       ]
      }
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
