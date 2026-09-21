//
//  ImportFormatTests.swift
//  LunaTests
//
//  The parsers, tested as pure functions — no browser installed, no fixture
//  database, nothing on disk but a temp directory. Every fact asserted here was
//  read off a real Dia 1.48.0 profile first: `date_added` being a string, the
//  bookmarks bar's loose URLs being the Favorites, the transition bitfield's
//  core values, and `Default` being named something other than "Default".
//
//  The HTML round trip is here too, because §23.4's export is only a backup if
//  it reads back.
//

import BrowserKit
import XCTest
@testable import Luna

final class ImportFormatTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-import-format-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna-\(UUID().uuidString).sqlite"))
    }

    private func makeLedger() -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: "ledger.json"))
    }

    // MARK: - Chromium bookmarks and history formats

    /// A tree far deeper than anything a human made stops at the depth cap
    /// instead of walking forever. JSON cannot hold a literal cycle; a corrupt
    /// or generated file can be arbitrarily deep, which costs the same.
    func testPathologicallyDeepBookmarkTreeIsCapped() throws {
        var node = #"{"type":"url","name":"deep","url":"https://deep.example/"}"#
        for level in (0..<40).reversed() {
            node = #"{"type":"folder","name":"L\#(level)","children":[\#(node)]}"#
        }
        let json = #"{"roots":{"bookmark_bar":{"children":[\#(node)]},"other":{"children":[]}}}"#

        let bookmarks = try ChromiumReader.flatten(bookmarksJSON: Data(json.utf8))
        XCTAssertTrue(bookmarks.isEmpty, "a 40-deep tree should be cut off by the depth cap")
    }

    /// A bookmarks file that is valid JSON but not a bookmarks tree is a
    /// reportable failure, not a silent empty import.
    func testNonBookmarksJSONIsReportedAsMalformed() {
        XCTAssertThrowsError(try ChromiumReader.flatten(bookmarksJSON: Data(#"{"hello":1}"#.utf8))) { error in
            XCTAssertEqual(error as? ImportError, .malformed("Bookmarks"))
        }
    }

    // MARK: - Chromium format details

    /// `date_added` is microseconds since 1601 written as a string. This is
    /// the detail a default `Decodable` gets wrong, and it is verified against
    /// a real value out of Dia's own `Bookmarks`.
    func testBookmarkBarLooseURLsAreFavoritesAndDatesDecode() throws {
        let json = """
        {"roots":{
          "bookmark_bar":{"children":[
            {"type":"url","name":"Loose","url":"https://loose.example/","date_added":"13429579614840426"},
            {"type":"folder","name":"Trego","children":[
              {"type":"url","name":"Inside","url":"https://inside.example/"}]}]},
          "other":{"children":[{"type":"url","name":"Other","url":"https://other.example/"}]}
        }}
        """
        let bookmarks = try ChromiumReader.flatten(bookmarksJSON: Data(json.utf8))
        XCTAssertEqual(bookmarks.count, 3)

        let loose = try XCTUnwrap(bookmarks.first { $0.title == "Loose" })
        XCTAssertEqual(loose.placement, .favorite)
        XCTAssertTrue(loose.folderPath.isEmpty)
        XCTAssertEqual(loose.dateAdded?.timeIntervalSince1970 ?? 0, 1_785_106_014.840426, accuracy: 0.001)

        let inside = try XCTUnwrap(bookmarks.first { $0.title == "Inside" })
        XCTAssertEqual(inside.placement, .folder)
        XCTAssertEqual(inside.folderPath, ["Trego"], "the bar itself is not a folder, its subfolders are")

        let other = try XCTUnwrap(bookmarks.first { $0.title == "Other" })
        XCTAssertEqual(other.folderPath, ["Other Bookmarks"])
    }

    /// `visits.transition` is a bitfield: low byte is the core type, the top
    /// two bits mark a redirect. Cores seen in Dia's live profile: 0, 1, 2, 3,
    /// 4, 7, 8, plus 3,236 redirect rows.
    func testTransitionMapping() {
        XCTAssertEqual(ChromiumReader.visitKind(transition: 0), .link)
        XCTAssertEqual(ChromiumReader.visitKind(transition: 1), .typed)
        XCTAssertEqual(ChromiumReader.visitKind(transition: 2), .bookmarked)
        XCTAssertEqual(ChromiumReader.visitKind(transition: 3), .embed)
        XCTAssertEqual(ChromiumReader.visitKind(transition: 8), .link)
        // TYPED with SERVER_REDIRECT set: a redirect first, whatever started it.
        XCTAssertEqual(ChromiumReader.visitKind(transition: 0x8000_0001), .redirect)
    }

    /// Chromium writes `0` for "never". Converted naively that is 1601, which
    /// would sort to the top of every history list forever.
    func testZeroTimestampIsRejected() {
        XCTAssertNil(ChromiumTimestamp.date(microsecondsSince1601: 0))
        XCTAssertNil(ChromiumTimestamp.date(microsecondsSince1601: "0"))
        XCTAssertNil(ChromiumTimestamp.date(microsecondsSince1601: "not a number"))
        XCTAssertNotNil(ChromiumTimestamp.date(microsecondsSince1601: 13_429_579_614_840_426))
    }

    // MARK: - Netscape HTML round trip (§23.2 import, §23.4 export)

    func testHTMLRoundTrip() {
        let bookmarks = [
            ImportedBookmark(
                url: URL(string: "https://one.example/")!,
                title: "Tom & Jerry <best>",
                dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
                folderPath: [],
                placement: .favorite
            ),
            ImportedBookmark(
                url: URL(string: "https://two.example/a?b=c")!,
                title: "Nested",
                dateAdded: Date(timeIntervalSince1970: 1_600_000_000),
                folderPath: ["Work", "Deep"],
                placement: .folder
            ),
            ImportedBookmark(
                url: URL(string: "https://three.example/")!,
                title: "Sibling",
                folderPath: ["Work"],
                placement: .folder
            )
        ]

        let parsed = NetscapeBookmarks.parse(NetscapeBookmarks.write(bookmarks))
        XCTAssertEqual(parsed.count, bookmarks.count)
        for original in bookmarks {
            let match = parsed.first { $0.url == original.url }
            XCTAssertEqual(match?.title, original.title, "titles must survive entity escaping")
            XCTAssertEqual(match?.folderPath, original.folderPath, "the folder tree must survive")
            XCTAssertEqual(match?.placement, original.placement)
            XCTAssertEqual(
                match?.dateAdded?.timeIntervalSince1970,
                original.dateAdded?.timeIntervalSince1970,
                "ADD_DATE is whole seconds since 1970 in this format"
            )
        }
    }

    /// Export then re-import our own file: the same Space, no duplicates.
    func testExportThenReimportIsIdempotent() async throws {
        let store = try makeStore()
        try await store.seedIfEmpty()
        let seeded = try await store.spaces().first
        let space = try XCTUnwrap(seeded)
        for (index, host) in ["a.example", "b.example"].enumerated() {
            try await store.upsert(Tab(
                spaceID: space.id,
                kind: index == 0 ? .essential : .pinned,
                url: URL(string: "https://\(host)/")!,
                title: host,
                order: index
            ))
        }

        let importer = BrowserImporter(store: store, ledger: makeLedger())
        let html = try await importer.exportBookmarksHTML(spaceID: space.id)
        let file = directory.appending(path: "Luna Bookmarks.html")
        try html.write(to: file, atomically: true, encoding: .utf8)

        let summary = try await importer.importBookmarks(htmlAt: file, into: space.id)
        XCTAssertEqual(summary.bookmarksAdded, 0, "re-importing our own export duplicated tabs")
        XCTAssertEqual(summary.bookmarksSkipped, 2)
        let tabsAfterReimport = try await store.tabs(inSpace: space.id, includeArchived: true).count
        XCTAssertEqual(tabsAfterReimport, 2)
    }

    /// A file that isn't a bookmarks file is refused rather than importing zero
    /// bookmarks and looking like it worked.
    func testGarbageHTMLIsRefused() async throws {
        let file = directory.appending(path: "notes.html")
        try "<html><body>no bookmarks here</body></html>".write(to: file, atomically: true, encoding: .utf8)
        let importer = BrowserImporter(store: try makeStore(), ledger: makeLedger())
        do {
            _ = try await importer.importBookmarks(htmlAt: file)
            XCTFail("expected a malformed error")
        } catch {
            XCTAssertEqual(error as? ImportError, .malformed("notes.html"))
        }
    }

    // MARK: - Detection

    /// A support directory that exists but holds no profile is not an install.
    /// Verified on this Mac: `Arc`, `Chromium`, `Microsoft Edge`, `Vivaldi` and
    /// `com.operasoftware.Opera` all exist as empty leftovers.
    func testEmptySupportDirectoryIsNotAnInstall() throws {
        let empty = directory.appending(path: "EmptyBrowser")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertNil(ChromiumProfileLocator.userDataRoot(in: empty, candidates: [""]))
    }

    /// `Default` is routinely not the profile the user lives in — on this Mac
    /// Dia's `Default` is called "Work" and `Profile 1` is "Main".
    func testLocalStateNamesWinOverDirectoryNames() {
        let json = """
        {"profile":{"last_used":"Profile 1","info_cache":{
          "Default":{"name":"Work"},"Profile 1":{"name":"Main"}}}}
        """
        let profiles = ChromiumProfileLocator.decodeProfiles(
            localState: Data(json.utf8),
            existingDirectories: ["Default", "Profile 1"]
        )
        XCTAssertEqual(profiles.map(\.displayName), ["Work", "Main"])
        XCTAssertEqual(profiles.first { $0.isLastUsed }?.directoryName, "Profile 1")
        XCTAssertEqual(profiles[1].label(for: .dia), "Main")
    }

    /// URLs that differ only by a trailing slash or by case in the scheme/host
    /// are the same bookmark; a different path is not.
    func testDedupKeyNormalisation() {
        func key(_ string: String) -> String { BrowserImporter.dedupKey(URL(string: string)!) }
        XCTAssertEqual(key("https://Example.com/"), key("HTTPS://example.com"))
        XCTAssertNotEqual(key("https://example.com/a"), key("https://example.com/b"))
    }

}
