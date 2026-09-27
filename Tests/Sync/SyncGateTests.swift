//
//  SyncGateTests.swift
//  LunaTests
//
//  The app's half of iCloud sync (docs/SYNC-PLAN.md S11): the entitlement
//  gate, and the coordinator hooked up to Settings, the session and the
//  History menu. The test host is unsigned, so anything that constructed a
//  `CKContainer` here would crash the run; past the gate, an engine that
//  only counts stands in for `CKSyncEngine`.
//

@testable import BrowserKit
import Synchronization
import XCTest
@testable import Luna

@MainActor
final class SyncGateTests: XCTestCase {

    private let directory = URL.temporaryDirectory.appending(path: "luna-tests-\(UUID().uuidString)")
    private let engine = CountingEngine()

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> BrowserStore {
        try BrowserStore(path: directory.appending(path: "luna.sqlite"))
    }

    /// Past the gate, over `engine`.
    private func started(
        _ settings: SyncSettings, store: BrowserStore? = nil, session: BrowserSession? = nil
    ) async throws -> AppSync {
        let store = try store ?? makeStore()
        let sync = await AppSync.start(store: store, session: session, settings: settings, entitled: true, makeEngine: engine.factory)
        return try XCTUnwrap(sync)
    }

    private func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(condition(), what)
    }

    // MARK: - The gate

    func testTheUnsignedTestHostHasNoICloudEntitlement() {
        XCTAssertFalse(SyncGate.isEntitled)
    }

    /// The real gate and the real engine factory: a `CKContainer` built here
    /// would take the test host down with it.
    func testTheUnsignedBuildSaysSoAndBuildsNothing() async throws {
        let settings = SyncSettings()
        settings.status = .off

        let sync = await AppSync.start(store: try makeStore(), session: nil, settings: settings)

        XCTAssertNil(sync)
        XCTAssertEqual(settings.status, .needsSignedBuild)
        XCTAssertEqual(settings.status.line(), "iCloud sync needs the signed build.")
    }

    func testSyncOffBuildsNoEngineAndActivationFetchesNothing() async throws {
        let settings = SyncSettings()
        let sync = try await started(settings)

        await sync.activated()

        XCTAssertEqual(engine.count(\.made), 0, "sync off built an engine")
        XCTAssertEqual(engine.count(\.fetches), 0)
        XCTAssertEqual(settings.status, .off)
        XCTAssertTrue(settings.zones.isEmpty)
    }

    // MARK: - Settings

    func testTheSyncSwitchTurnsEveryZoneOnAndActivationThenFetches() async throws {
        let settings = SyncSettings()
        let sync = try await started(settings)

        settings.setEnabled(true)
        try await eventually("the zones never came back to Settings") { settings.zones.contains(.spaces) }

        XCTAssertEqual(settings.zones, [.spaces, .sites, .settings, .history, .devices, .meta])
        XCTAssertEqual(engine.count(\.made), 1)
        let fetches = engine.count(\.fetches)
        await sync.activated()
        XCTAssertEqual(engine.count(\.fetches), fetches + 1)
    }

    func testAZoneSwitchSyncNowAndRemoveAllReachTheCoordinator() async throws {
        let settings = SyncSettings()
        let sync = try await started(settings)
        settings.setEnabled(true)
        try await eventually("sync never turned on") { settings.zones.contains(.history) }

        settings.setZone(.history, false)
        try await eventually("the zone switch was not written back") { !settings.zones.contains(.history) }

        let sends = engine.count(\.sends)
        settings.syncNow()
        try await eventually("Sync Now sent nothing") { engine.count(\.sends) > sends }

        settings.removeAll()
        try await eventually("Remove All left sync on") { settings.zones.isEmpty }
        XCTAssertEqual(settings.status, .off)
        XCTAssertEqual(Set(engine.zoneDeletes), Set(SyncZone.allCases))
        withExtendedLifetime(sync) {}
    }

    // MARK: - The session and the menu

    /// Another Mac's rename reaches the window, not only the database.
    func testIncomingChangesGoThroughTheSession() async throws {
        let store = try makeStore()
        let session = try await BrowserSession.restored(store: store)
        let sync = try await started(SyncSettings(), store: store, session: session)
        try await sync.coordinator.enable(zones: [.spaces])
        var space = try XCTUnwrap(session.spaces.first)
        space.name = "Elsewhere"
        var record = SyncMapping.record(for: space, modifiedAt: Date(), stored: nil)
        record.systemFields = Data([1])

        try await sync.coordinator.fetched(modifications: [record], deletions: [])

        XCTAssertEqual(session.space(space.id)?.name, "Elsewhere")
    }

    func testActivationPublishesThisMac() async throws {
        let sync = try await started(SyncSettings())
        try await sync.coordinator.enable(zones: [.devices])

        await sync.activated()

        let own = try await sync.coordinator.deviceID().uuidString
        XCTAssertTrue(engine.pending.contains(.save(own, in: .devices)))
    }

    func testOtherMacsFillTheHistoryMenuAndLeaveItWhenSyncTurnsOff() async throws {
        let settings = SyncSettings()
        let sync = try await started(settings)
        settings.setEnabled(true)
        try await eventually("sync never turned on") { settings.zones.contains(.devices) }
        var laptop = SyncMapping.record(
            for: SyncDevice(id: UUID(), name: "Laptop", tabs: [
                SyncDevice.OpenTab(spaceID: UUID(), url: URL(string: "https://example.com/")!, title: "From the laptop")
            ]),
            modifiedAt: Date(),
            stored: nil
        )
        laptop.systemFields = Data([1])

        try await sync.coordinator.fetched(modifications: [laptop], deletions: [])
        try await eventually("the laptop's tab never reached the menu") { otherMacsTitles().contains("From the laptop") }

        settings.setEnabled(false)
        try await eventually("the menu kept the laptop after sync turned off") { otherMacsTitles() == ["No Other Macs"] }
    }

    private func otherMacsTitles() -> [String] {
        let history = NSApp.mainMenu?.items.first { $0.submenu?.title == "History" }?.submenu
        let others = history?.items.first { $0.title == "Tabs on Other Macs" }?.submenu
        return others?.items.map(\.title) ?? []
    }
}

/// `SyncEngineControl` that only counts, so these tests can pass the gate.
private final class CountingEngine: SyncEngineControl {

    struct Counts {
        var made = 0
        var fetches = 0
        var sends = 0
        var pending: [SyncPendingChange] = []
        var zoneDeletes: [SyncZone] = []
    }

    let counts = Mutex(Counts())

    func count(_ key: KeyPath<Counts, Int>) -> Int { counts.withLock { $0[keyPath: key] } }
    var pending: [SyncPendingChange] { counts.withLock(\.pending) }
    var zoneDeletes: [SyncZone] { counts.withLock(\.zoneDeletes) }

    var factory: @Sendable (SyncCoordinator, Data?) -> any SyncEngineControl {
        { [self] _, _ in
            counts.withLock { $0.made += 1 }
            return self
        }
    }

    func add(pending changes: [SyncPendingChange]) async { counts.withLock { $0.pending += changes } }
    func remove(pending changes: [SyncPendingChange]) async { counts.withLock { $0.pending.removeAll(where: changes.contains) } }
    func addZoneSaves(_ zones: [SyncZone]) async {}
    func addZoneDeletes(_ zones: [SyncZone]) async { counts.withLock { $0.zoneDeletes += zones } }
    func fetchChanges() async throws { counts.withLock { $0.fetches += 1 } }
    func sendChanges() async throws { counts.withLock { $0.sends += 1 } }
}
