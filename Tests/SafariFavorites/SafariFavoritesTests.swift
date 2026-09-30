//
//  SafariFavoritesTests.swift
//  LunaTests
//
//  docs/SAFARI-FAVORITES.md: Luna's bookmarks in Safari's Favorites, and the
//  change entries that make Safari's own iCloud sync carry it to the iPhone.
//  Every document here is built in memory; nothing touches the real Safari.
//

import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SafariBookmarksDocumentTests: XCTestCase {

    private func page(_ path: String, _ title: String? = nil) -> SafariFavorite {
        SafariFavorite(title: title ?? path, url: URL(string: "https://example.com/\(path)")!)
    }

    /// Favorites, the Bookmarks Menu and the Reading List, as Safari lays a
    /// fresh file out, with iCloud on unless asked otherwise.
    private func document(iCloud: Bool = true, favorites: [[String: Any]] = []) throws -> SafariBookmarksDocument {
        var root: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkFileVersion": 1,
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "Children": favorites],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksMenu", "Children": [Any]()]
            ]
        ]
        if iCloud { root["Sync"] = ["CloudKitMigrationState": 3, "CloudKitDeviceIdentifier": "device"] }
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        return try SafariBookmarksDocument(data: data)
    }

    private func tree(_ document: SafariBookmarksDocument) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: document.data(), format: nil) as? [String: Any])
    }

    private func favorites(_ document: SafariBookmarksDocument) throws -> [[String: Any]] {
        let bar = try XCTUnwrap((tree(document)["Children"] as? [[String: Any]])?.first { $0["Title"] as? String == "BookmarksBar" })
        return bar["Children"] as? [[String: Any]] ?? []
    }

    private func urls(_ document: SafariBookmarksDocument) throws -> [String] {
        try favorites(document).compactMap { $0["URLString"] as? String }
    }

    /// A bookmark as it stands once the sync agent has uploaded it.
    private func uploaded(_ path: String, title: String, server: String, id: String = UUID().uuidString) -> [String: Any] {
        [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": id,
            "URLString": "https://example.com/\(path)",
            "URIDictionary": ["title": title],
            "Sync": ["ServerID": server, "Data": Data([1, 2, 3])]
        ]
    }

    func testPagesGoStraightIntoFavoritesAsSafariRecordsThem() throws {
        let theirs = uploaded("mine", title: "Mine", server: "record-mine", id: "theirs")
        var document = try document(favorites: [theirs])
        let result = try XCTUnwrap(document.mirror([page("a"), page("b")], owned: []))
        XCTAssertTrue(result.changed)
        XCTAssertEqual(try urls(document), ["https://example.com/mine", "https://example.com/a", "https://example.com/b"],
                       "after the user's own, with no folder around them")
        let added = try favorites(document).dropFirst()
        XCTAssertEqual(result.owned, Set(added.compactMap { $0["WebBookmarkUUID"] as? String }))

        let changes = document.pendingChanges
        XCTAssertEqual(changes.map { $0["Type"] as? String }, ["Add", "Add"])
        XCTAssertEqual(changes.map { $0["BookmarkType"] as? String }, ["Leaf", "Leaf"])
        XCTAssertEqual(Set(changes.compactMap { $0["Token"] as? String }).count, 2)

        // Each Add names the record it makes, and the item carries that name
        // and no system fields yet: the uploader sends it without Safari open.
        let records = added.map { ($0["Sync"] as? [String: Any])?["ServerID"] as? String }
        XCTAssertEqual(changes.map { $0["BookmarkServerID"] as? String }, records)
        XCTAssertEqual(Set(records.compactMap { $0 }).count, 2)
        XCTAssertTrue(added.allSatisfy { ($0["Sync"] as? [String: Any])?["Data"] == nil })
        XCTAssertTrue(added.allSatisfy { $0["dateAdded"] is Date })
    }

    /// A page the user already has in Favorites is theirs, not added twice, and
    /// their bookmark is never changed or removed.
    func testTheUsersOwnFavoritesAreLeftAlone() throws {
        let theirs = uploaded("a", title: "Their title", server: "record-a", id: "theirs")
        var document = try document(favorites: [theirs])
        let result = try XCTUnwrap(document.mirror([page("a", "Luna's title")], owned: []))
        XCTAssertFalse(result.changed)
        XCTAssertTrue(result.owned.isEmpty)
        XCTAssertFalse(try XCTUnwrap(document.mirror([], owned: [])).changed)
        XCTAssertFalse(document.removeBookmarks([]))
        XCTAssertEqual(try favorites(document).compactMap { $0["WebBookmarkUUID"] as? String }, ["theirs"])
    }

    /// A bookmark written by a build that recorded its Add without a record
    /// name or a date waits on the list for good; the next run adds both.
    func testAnUnsentBookmarkWithoutARecordNameIsGivenOne() throws {
        let leaf: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf", "WebBookmarkUUID": "luna-a",
            "URLString": "https://example.com/a", "URIDictionary": ["title": "a"]
        ]
        var document = try document(favorites: [leaf])
        document.pendingChanges = [["Token": "t", "Type": "Add", "BookmarkType": "Leaf", "BookmarkUUID": "luna-a"]]
        XCTAssertTrue(try XCTUnwrap(document.mirror([page("a")], owned: ["luna-a"])).changed)
        let stored = try XCTUnwrap(favorites(document).first)
        let record = try XCTUnwrap((stored["Sync"] as? [String: Any])?["ServerID"] as? String)
        XCTAssertEqual(document.pendingChanges.map { $0["BookmarkServerID"] as? String }, [record])
        XCTAssertTrue(stored["dateAdded"] is Date)

        XCTAssertFalse(try XCTUnwrap(document.mirror([page("a")], owned: ["luna-a"])).changed)
    }

    func testTheSamePagesAgainChangeNothing() throws {
        var document = try document()
        let first = try XCTUnwrap(document.mirror([page("a")], owned: []))
        let again = try XCTUnwrap(document.mirror([page("a")], owned: first.owned))
        XCTAssertFalse(again.changed)
        XCTAssertEqual(again.owned, first.owned)
        XCTAssertEqual(document.pendingChanges.count, 1)
    }

    /// An uploaded bookmark is deleted from iCloud with its record's name and
    /// system fields; one still waiting to go up only loses its entry.
    func testUnpinningDeletesFromICloudOnlyWhatICloudHas() throws {
        var document = try document(favorites: [uploaded("a", title: "a", server: "record-a", id: "luna-a")])
        let first = try XCTUnwrap(document.mirror([page("a"), page("b")], owned: ["luna-a"]))
        let waiting = try XCTUnwrap(favorites(document).first { $0["URLString"] as? String == "https://example.com/b" })

        let second = try XCTUnwrap(document.mirror([], owned: first.owned))
        XCTAssertTrue(second.owned.isEmpty)
        XCTAssertTrue(try favorites(document).isEmpty)
        let changes = document.pendingChanges
        XCTAssertFalse(changes.contains { $0["BookmarkUUID"] as? String == waiting["WebBookmarkUUID"] as? String },
                       "a bookmark iCloud never had is still waiting to be added")
        let delete = try XCTUnwrap(changes.first { $0["Type"] as? String == "Delete" })
        XCTAssertEqual(delete["BookmarkServerID"] as? String, "record-a")
        XCTAssertEqual(delete["DeletedBookmarkSyncData"] as? Data, Data([1, 2, 3]))
    }

    func testARenamedPinSendsItsNewTitle() throws {
        var document = try document(favorites: [uploaded("a", title: "Old", server: "record-a", id: "luna-a")])
        _ = try XCTUnwrap(document.mirror([page("a", "New")], owned: ["luna-a"]))
        let leaf = try XCTUnwrap(favorites(document).first)
        XCTAssertEqual((leaf["URIDictionary"] as? [String: Any])?["title"] as? String, "New")
        let modify = try XCTUnwrap(document.pendingChanges.first)
        XCTAssertEqual(modify["Type"] as? String, "Modify")
        XCTAssertEqual(modify["BookmarkServerID"] as? String, "record-a")
        XCTAssertEqual(modify["ChangedAttributes"] as? [String], ["Title"])
    }

    /// Switched off, Luna's bookmarks go, and only Luna's.
    func testSwitchingOffRemovesOnlyLunasBookmarks() throws {
        var document = try document(favorites: [
            uploaded("mine", title: "Mine", server: "record-mine", id: "theirs"),
            uploaded("a", title: "a", server: "record-a", id: "luna-a")
        ])
        XCTAssertTrue(document.removeBookmarks(["luna-a"]))
        XCTAssertEqual(try urls(document), ["https://example.com/mine"])
        XCTAssertEqual(document.pendingChanges.compactMap { $0["BookmarkServerID"] as? String }, ["record-a"])
        XCTAssertFalse(document.removeBookmarks(["luna-a"]), "a second removal found something")
    }

    /// The folder earlier builds used goes, with everything in it, and iCloud
    /// is told about each item it has. A folder the user named Luna stays.
    func testTheOldFolderIsTakenOutByItsIDOnly() throws {
        let old: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList", "WebBookmarkUUID": "folder", "Title": "Luna",
            "Sync": ["ServerID": "folder-record", "Data": Data([9])],
            "Children": [uploaded("a", title: "a", server: "record-a")]
        ]
        let theirs: [String: Any] = ["WebBookmarkType": "WebBookmarkTypeList", "WebBookmarkUUID": "theirs", "Title": "Luna"]
        var document = try document(favorites: [old, theirs])
        XCTAssertTrue(document.removeFolder("folder"))
        XCTAssertEqual(try favorites(document).compactMap { $0["WebBookmarkUUID"] as? String }, ["theirs"])
        XCTAssertEqual(Set(document.pendingChanges.compactMap { $0["BookmarkServerID"] as? String }), ["folder-record", "record-a"])
        XCTAssertTrue(document.pendingChanges.allSatisfy { $0["Type"] as? String == "Delete" })
        XCTAssertFalse(document.removeFolder("folder"), "a second removal found something")
    }

    /// With iCloud bookmarks off there is no sync to feed: the bookmarks are
    /// kept for Safari on this Mac, and no entries pile up for an agent that is
    /// not running.
    func testWithoutICloudNothingIsQueued() throws {
        var document = try document(iCloud: false)
        _ = try XCTUnwrap(document.mirror([page("a")], owned: []))
        XCTAssertEqual(try urls(document), ["https://example.com/a"])
        XCTAssertTrue(document.pendingChanges.isEmpty)
    }

    /// The Reading List item Luna had Safari add goes again, deleted from
    /// iCloud once iCloud has it; everything else in the list stays.
    func testTheNudgeItemIsTakenOutOfTheReadingList() throws {
        var root = try tree(document())
        var folders = try XCTUnwrap(root["Children"] as? [[String: Any]])
        folders.append([
            "WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList",
            "Children": [
                uploaded("theirs", title: "Theirs", server: "record-theirs"),
                [
                    "WebBookmarkType": "WebBookmarkTypeLeaf", "WebBookmarkUUID": "nudge",
                    "URLString": "https://luna.invalid/safari-sync",
                    "Sync": ["ServerID": "record-nudge", "Data": Data([4])]
                ] as [String: Any]
            ]
        ])
        root["Children"] = folders
        var document = try SafariBookmarksDocument(
            data: PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        )
        XCTAssertTrue(document.hasUploadedReadingListItem(at: "https://luna.invalid/safari-sync"))
        XCTAssertTrue(document.removeReadingListItems(at: "https://luna.invalid/safari-sync"))
        XCTAssertFalse(document.hasUploadedReadingListItem(at: "https://luna.invalid/safari-sync"))
        let top = try XCTUnwrap(tree(document)["Children"] as? [[String: Any]])
        let list = try XCTUnwrap(top.first { $0["Title"] as? String == "com.apple.ReadingList" })
        XCTAssertEqual((list["Children"] as? [[String: Any]])?.compactMap { $0["URLString"] as? String }, ["https://example.com/theirs"])
        XCTAssertEqual(document.pendingChanges.compactMap { $0["BookmarkServerID"] as? String }, ["record-nudge"])
        XCTAssertFalse(document.removeReadingListItems(at: "https://luna.invalid/safari-sync"))
    }

    /// Safari's file is binary, and everything this does not know about goes
    /// back as it came.
    func testTheFileKeepsItsFormatAndItsOtherKeys() throws {
        var document = try document()
        _ = try XCTUnwrap(document.mirror([page("a")], owned: []))
        let data = try document.data()
        XCTAssertEqual(data.prefix(6), Data("bplist".utf8))
        let root = try tree(document)
        XCTAssertEqual(root["WebBookmarkFileVersion"] as? Int, 1)
        XCTAssertEqual((root["Sync"] as? [String: Any])?["CloudKitDeviceIdentifier"] as? String, "device")
    }
}

final class SafariBookmarksLockTests: XCTestCase {

    private let folder = URL.temporaryDirectory.appending(path: "luna-safari-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheLockIsHeldByOneAtATime() throws {
        let lock = try XCTUnwrap(SafariBookmarksLock.take(in: folder))
        XCTAssertNil(SafariBookmarksLock.take(in: folder), "a second writer got in")
        lock.release()
        XCTAssertNotNil(SafariBookmarksLock.take(in: folder)?.release())
    }

    /// A lock left by a process that has gone is taken over rather than
    /// waited on for ever.
    func testALockFromAGoneProcessIsTakenOver() throws {
        let lock = folder.appending(path: "lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        let details: [String: Any] = [
            "LockFileProcessID": 999_999, "LockFileHostname": SafariBookmarksLock.platformUUID ?? "", "LockFileDate": Date()
        ]
        try PropertyListSerialization.data(fromPropertyList: details, format: .xml, options: 0)
            .write(to: lock.appending(path: "details.plist"))
        XCTAssertNotNil(SafariBookmarksLock.take(in: folder)?.release())
    }

    /// Replacing is refused when the file changed since it was read.
    func testAFileChangedSinceItWasReadIsNotReplaced() throws {
        let plist = folder.appending(path: "Bookmarks.plist")
        try Data("old".utf8).write(to: plist)
        let read = try SafariBookmarksFile.read(from: folder)
        try Data("theirs".utf8).write(to: plist)
        XCTAssertThrowsError(try SafariBookmarksFile.replace(read, with: Data("mine".utf8), in: folder)) { error in
            XCTAssertEqual(error as? SafariBookmarksFile.Failure, .busy)
        }
        XCTAssertEqual(try Data(contentsOf: plist), Data("theirs".utf8))
        try SafariBookmarksFile.replace(Data("theirs".utf8), with: Data("mine".utf8), in: folder)
        XCTAssertEqual(try Data(contentsOf: plist), Data("mine".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "lock").path), "the lock was left behind")
    }
}

@MainActor
final class SafariFavoritesPagesTests: XCTestCase {

    func testOnlyKeptWebPagesGoOnceEachAtTheirPinnedAddress() {
        let space = UUID()
        let home = URL(string: "https://mail.example.com/")!
        let tabs = [
            Tab(spaceID: space, kind: .pinned, url: URL(string: "https://mail.example.com/inbox/42")!, title: "Inbox", pinnedURL: home),
            Tab(spaceID: space, kind: .today, url: URL(string: "https://news.example.com/")!, title: "News"),
            Tab(spaceID: space, kind: .pinned, url: URL(string: "luna://settings")!, title: "Settings"),
            Tab(spaceID: space, kind: .pinned, url: home, title: "Again"),
            Tab(spaceID: space, kind: .pinned, url: URL(string: "https://docs.example.com/")!, title: "", customTitle: "Docs"),
            Tab(spaceID: space, kind: .pinned, url: URL(string: "https://empty.example.com/")!, title: "")
        ]
        XCTAssertEqual(SafariFavorites.pages(in: tabs), [
            SafariFavorite(title: "Inbox", url: home),
            SafariFavorite(title: "Docs", url: URL(string: "https://docs.example.com/")!),
            SafariFavorite(title: "empty.example.com", url: URL(string: "https://empty.example.com/")!)
        ])
    }

    /// The tiles come first, by host or the name the user gave them: a tile's
    /// page title changes with every visit.
    func testFavoritesTilesGoFirstByTheirHost() {
        let space = UUID()
        let tabs = [
            Tab(spaceID: space, kind: .pinned, url: URL(string: "https://docs.example.com/")!, title: "Docs"),
            Tab(spaceID: space, kind: .essential, url: URL(string: "https://www.youtube.com/watch?v=1")!,
                title: "(3) A video - YouTube", pinnedURL: URL(string: "https://www.youtube.com/")!),
            Tab(spaceID: space, kind: .essential, url: URL(string: "https://mail.example.com/")!, title: "Inbox (4)",
                customTitle: "Mail")
        ]
        XCTAssertEqual(SafariFavorites.pages(in: tabs), [
            SafariFavorite(title: "youtube.com", url: URL(string: "https://www.youtube.com/")!),
            SafariFavorite(title: "Mail", url: URL(string: "https://mail.example.com/")!),
            SafariFavorite(title: "Docs", url: URL(string: "https://docs.example.com/")!)
        ])
    }
}
