//
//  SyncedDefaultsTests.swift
//  LunaTests
//
//  docs/plans/SYNC-PLAN.md S9: which settings reach iCloud, and what an incoming one
//  does here. Every test runs against its own defaults suite and database, so
//  none of them touches the running app's settings.
//

@testable import BrowserKit
import XCTest
@testable import Luna

@MainActor
final class SyncedDefaultsTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!
    private var store: BrowserStore!
    private var directory: URL!

    override func setUp() async throws {
        // One fixed suite, emptied first: a suite is a plist that emptying
        // does not delete, so a new name per run leaves a file behind (§24.11).
        suite = "luna.tests.SyncedDefaultsTests"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        directory = FileManager.default.temporaryDirectory.appending(path: "\(suite)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try BrowserStore(path: directory.appending(path: "luna.sqlite"))
        try await store.setSyncZone(.settings, enabled: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func record() async throws {
        try await SyncedDefaults.record(defaults, domain: suite, to: store)
    }

    /// The queued Setting rows, key to `isDelete`.
    private func XCTAssertOutbox(
        _ expected: [String: Bool], _ message: String = "", line: UInt = #line
    ) async throws {
        let rows = try await store.syncOutbox().filter { $0.recordType == "Setting" }
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.localKey, $0.isDelete) }), expected, message, line: line)
    }

    private func incoming(_ key: String, _ value: Any) throws -> SyncRecord {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        return SyncMapping.record(for: SyncSetting(key: key, value: data), modifiedAt: Date(), stored: nil)
    }

    func testAnAllowlistedChangeReachesTheOutbox() async throws {
        defaults.set("duckduckgo", forKey: "search.engine")
        defaults.set("cmd+shift+t", forKey: "luna.shortcut.newTab")
        try await record()

        try await XCTAssertOutbox(["search.engine": false, "luna.shortcut.newTab": false])
        let sent = try await store.outgoingRecord("Setting", localKey: "search.engine", deviceID: UUID(), secret: nil)
        let value = try XCTUnwrap(sent.flatMap(SyncMapping.setting(from:))?.value)
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: value, format: nil) as? String, "duckduckgo")
    }

    func testAKeyOutsideTheAllowlistDoesNotReachTheOutbox() async throws {
        defaults.set("/tmp", forKey: "downloads.directory")
        defaults.set("general", forKey: "settings.lastSection")
        defaults.set(true, forKey: "appearance.glassOptimisation")
        try await record()

        try await XCTAssertOutbox([:])
    }

    /// Reading preferences are the user's, not the Mac's: they follow them.
    func testReadingPreferencesSync() async throws {
        var preferences = ReadingPreferences()
        preferences.typeface = .sans
        preferences.size = 22
        preferences.width = .narrow
        preferences.page = .night
        preferences.outline = false
        preferences.wrap = false
        preferences.store(in: defaults)
        try await record()

        let keys = ReadingPreferences.Key.self
        try await XCTAssertOutbox([
            keys.typeface: false, keys.size: false, keys.width: false,
            keys.page: false, keys.outline: false, keys.wrap: false
        ])
    }

    /// Either would weaken another Mac's security without anyone at it choosing to.
    func testControlAndRequireTouchIDNeverSync() async throws {
        let control = "advanced.allowControl", touchID = PasswordSettings.Key.requireAuthentication
        XCTAssertFalse(SyncedDefaults.syncs(control))
        XCTAssertFalse(SyncedDefaults.syncs(touchID))
        defaults.set(false, forKey: control)
        defaults.set(true, forKey: touchID)
        try await record()
        try await XCTAssertOutbox([:])

        let weakened = SyncChangeSet(modifications: [try incoming(control, true), try incoming(touchID, false)])
        try await SyncedDefaults.apply(weakened, to: defaults, store: store)
        XCTAssertEqual(defaults.object(forKey: control) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: touchID) as? Bool, true)
    }

    func testAnIncomingValueIsWrittenAndPostsBothNotifications() async throws {
        let settings = expectation(forNotification: Settings.didChange, object: nil)
        let bindings = expectation(forNotification: KeyBindings.didChange, object: nil)

        let engine = SyncChangeSet(modifications: [try incoming("search.engine", "duckduckgo")])
        try await SyncedDefaults.apply(engine, to: defaults, store: store)

        XCTAssertEqual(defaults.string(forKey: "search.engine"), "duckduckgo")
        await fulfillment(of: [settings, bindings], timeout: 1)
    }

    func testAnIncomingValueIsNotEchoedBack() async throws {
        try await SyncedDefaults.apply(
            SyncChangeSet(modifications: [try incoming("luna.shortcut.newTab", "cmd+shift+t")]), to: defaults, store: store
        )
        try await XCTAssertOutbox([:], "applying it queued it")

        // The defaults change the write causes is recorded like any other.
        try await record()
        try await XCTAssertOutbox([:], "recording it afterwards queued it")
    }

    func testARemovedKeyDeletesItsRecord() async throws {
        defaults.set("cmd+shift+t", forKey: "luna.shortcut.newTab")
        try await record()
        try await store.clearOutbox("Setting", "luna.shortcut.newTab", savedAt: .distantFuture)

        defaults.removeObject(forKey: "luna.shortcut.newTab")
        try await record()

        try await XCTAssertOutbox(["luna.shortcut.newTab": true])
    }

    func testAnIncomingRemovalRemovesTheKey() async throws {
        defaults.set("cmd+shift+t", forKey: "luna.shortcut.newTab")
        try await record()
        try await store.clearOutbox("Setting", "luna.shortcut.newTab", savedAt: .distantFuture)

        let gone = SyncDeletion(recordType: "Setting", recordName: "luna.shortcut.newTab", zone: SyncZone.settings.rawValue)
        try await SyncedDefaults.apply(SyncChangeSet(deletions: [gone]), to: defaults, store: store)

        XCTAssertNil(defaults.object(forKey: "luna.shortcut.newTab"))
        try await record()
        try await XCTAssertOutbox([:])
    }
}
