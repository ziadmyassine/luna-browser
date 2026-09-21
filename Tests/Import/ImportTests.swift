//
//  ImportTests.swift
//  LunaTests
//
//  The behaviour of a whole import run, against fixture profiles. Three things
//  that are invisible when they break:
//
//  · Idempotency. Running an import twice must not double every bookmark.
//    Nothing on screen says it went wrong; the user just has two of everything.
//  · A locked source database. Chromium holds `History` open. Verified
//    against Dia on this Mac: an in-place read-only open returns
//    `database is locked (5)`, and the snapshot read returns the rows. That is
//    the whole reason `ImportSnapshot` exists, so it gets a test that fails if
//    somebody "simplifies" it back to a direct read.
//  · Malformed input. A truncated `Bookmarks` must cost the bookmarks, not
//    the history, and never the process.
//
//  Fixtures throughout — never the live browser data, which changes under the
//  test and isn't on every machine. `ImportFormatTests` covers the parsers.
//

import BrowserKit
import SQLite3
import XCTest
@testable import Luna

final class ImportTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL.temporaryDirectory.appending(path: "luna-import-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Idempotency

    /// The one that matters. Import a profile, import the same profile again:
    /// the second run adds nothing and the Space is the same size.
    func testSecondRunAddsNothing() async throws {
        let profile = try makeChromiumProfile(named: "Profile 1", visits: 7, bookmarks: 5)
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: makeLedger())

        let first = try await importer.run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia — Main"
        )
        XCTAssertEqual(first.bookmarksAdded, 5)
        XCTAssertEqual(first.visitsAdded, 7)
        XCTAssertEqual(first.failed, 0, "\(first.warnings)")

        let spaceID = try XCTUnwrap(first.targetSpaceID)
        let afterFirst = try await store.tabs(inSpace: spaceID, includeArchived: true).count
        XCTAssertEqual(afterFirst, 5)

        let second = try await importer.run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia — Main"
        )
        XCTAssertEqual(second.bookmarksAdded, 0, "a second import must not duplicate bookmarks")
        XCTAssertEqual(second.bookmarksSkipped, 5)
        XCTAssertEqual(second.visitsAdded, 0, "the watermark must hold history back on a second run")
        XCTAssertEqual(second.visitsSkipped, 7)
        XCTAssertEqual(second.targetSpaceID, spaceID, "a second import must reuse the Space, not make one")

        let afterSecond = try await store.tabs(inSpace: spaceID, includeArchived: true).count
        XCTAssertEqual(afterSecond, afterFirst, "the Space grew on a second import")
    }

    /// Bookmark dedup is read from the store, not from the ledger — so it still
    /// holds for a user who lost the ledger, or who imports the same sites from
    /// two different browsers.
    func testBookmarkDedupSurvivesALostLedger() async throws {
        let profile = try makeChromiumProfile(named: "Profile 1", visits: 0, bookmarks: 4)
        let store = try makeStore()

        let first = try await BrowserImporter(store: store, ledger: makeLedger()).run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia",
            surfaces: .bookmarks
        )
        // A brand-new ledger, i.e. the file was deleted between runs.
        let second = try await BrowserImporter(store: store, ledger: makeLedger("second.json")).run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia",
            surfaces: .bookmarks
        )
        XCTAssertEqual(first.bookmarksAdded, 4)
        XCTAssertEqual(second.bookmarksAdded, 0)
        XCTAssertEqual(second.bookmarksSkipped, 4)
    }

    /// A dry run reports the same numbers and writes nothing.
    func testDryRunWritesNothing() async throws {
        let profile = try makeChromiumProfile(named: "Profile 1", visits: 3, bookmarks: 2)
        let store = try makeStore()
        let importer = BrowserImporter(store: store, ledger: makeLedger())

        let preview = try await importer.run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia",
            dryRun: true
        )
        XCTAssertTrue(preview.isDryRun)
        XCTAssertEqual(preview.bookmarksAdded, 2)
        XCTAssertEqual(preview.visitsAdded, 3)
        let spacesAfterPreview = try await store.spaces().count
        XCTAssertEqual(spacesAfterPreview, 0, "a dry run created a Space")

        let real = try await importer.run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia"
        )
        XCTAssertEqual(real.bookmarksAdded, preview.bookmarksAdded, "the preview lied")
        XCTAssertEqual(real.visitsAdded, preview.visitsAdded, "the preview lied")
    }

    // MARK: - A locked source database

    /// Chromium keeps `History` open while it runs. Reading it in place fails;
    /// reading a copy of it — with its sidecars — works.
    func testLockedDatabaseReadsThroughTheSnapshot() throws {
        let profile = try makeChromiumProfile(named: "Profile 1", visits: 3, bookmarks: 0)
        let history = profile.appending(path: "History")

        // Take a writer lock the way a running browser does, and hold it.
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(history.path, &writer, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(writer) }
        let holdLock = """
        BEGIN EXCLUSIVE;
        INSERT INTO urls(url, title, last_visit_time) VALUES('https://uncommitted.example', '', 1)
        """
        XCTAssertEqual(sqlite3_exec(writer, holdLock, nil, nil, nil), SQLITE_OK)

        XCTAssertThrowsError(try SQLiteReader(readOnly: history).query("SELECT count(*) FROM urls") { $0.int(0) }) { error in
            // The exact message is SQLite's; what matters is that it failed.
            XCTAssertTrue("\(error)".lowercased().contains("lock"), "expected a lock failure, got \(error)")
        }

        let snapshot = try ImportSnapshot()
        let reader = try ChromiumReader.snapshot(profileDirectory: profile, into: snapshot)
        // The uncommitted row is rolled back by the copied journal, which is
        // exactly right: the snapshot sees what the browser has committed.
        XCTAssertEqual(try reader.visitCount(after: 0), 3)
    }

    // MARK: - Malformed input

    /// A truncated `Bookmarks` costs the bookmarks and nothing else.
    func testTruncatedBookmarksDoesNotFailTheRun() async throws {
        let profile = try makeChromiumProfile(named: "Profile 1", visits: 4, bookmarks: 3)
        let broken = String(try String(contentsOf: profile.appending(path: "Bookmarks"), encoding: .utf8).prefix(60))
        try broken.write(to: profile.appending(path: "Bookmarks"), atomically: true, encoding: .utf8)

        let store = try makeStore()
        let summary = try await BrowserImporter(store: store, ledger: makeLedger()).run(
            reader: try reader(for: profile),
            ledgerKey: "dia/Profile 1",
            spaceName: "Dia"
        )
        XCTAssertEqual(summary.bookmarksAdded, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertFalse(summary.warnings.isEmpty)
        XCTAssertEqual(summary.visitsAdded, 4, "history must survive a broken bookmarks file")
    }

    // MARK: - Fixtures

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna-\(UUID().uuidString).sqlite"))
    }

    private func makeLedger(_ name: String = "ledger.json") -> ImportLedger {
        ImportLedger(fileURL: directory.appending(path: name))
    }

    private func reader(for profile: URL) throws -> ChromiumReader {
        let snapshot = try ImportSnapshot()
        return try ChromiumReader.snapshot(profileDirectory: profile, into: snapshot)
    }

    /// Builds a Chromium profile directory: the `urls`/`visits` schema as Dia
    /// writes it, plus a `Bookmarks` tree with the bar's loose URLs and one
    /// folder.
    @discardableResult
    private func makeChromiumProfile(named name: String, visits: Int, bookmarks: Int) throws -> URL {
        let profile = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(profile.appending(path: "History").path, &handle, flags, nil) == SQLITE_OK else {
            throw XCTSkip("couldn't create the fixture database")
        }
        defer { sqlite3_close(handle) }

        var sql = """
        CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR,
            visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL,
            last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL);
        CREATE TABLE visits(id INTEGER PRIMARY KEY AUTOINCREMENT, url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL);
        """
        // Microseconds since 1601, the way Chromium writes them.
        let base: Int64 = 13_429_579_614_840_426
        for index in 0..<visits {
            let stamp = base + Int64(index) * 1_000_000
            sql += """
            INSERT INTO urls(id, url, title, visit_count, last_visit_time)
                VALUES(\(index + 1), 'https://site\(index).example/', 'Site \(index)', 1, \(stamp));
            INSERT INTO visits(url, visit_time, transition) VALUES(\(index + 1), \(stamp), \(index % 2));
            """
        }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("couldn't populate the fixture database: \(String(cString: sqlite3_errmsg(handle)))")
        }

        func leaf(_ index: Int, _ stamp: Int64) -> String {
            #"{"type":"url","name":"B\#(index)","url":"https://b\#(index).example/","date_added":"\#(stamp)"}"#
        }
        let bar = (0..<bookmarks).map { index in
            index == 0
                ? #"{"type":"folder","name":"Folder","children":[\#(leaf(0, base))]}"#
                : leaf(index, base)
        }.joined(separator: ",")
        let json = #"{"roots":{"bookmark_bar":{"children":[\#(bar)]},"other":{"children":[]}},"version":1}"#
        try Data(json.utf8).write(to: profile.appending(path: "Bookmarks"))

        return profile
    }
}
