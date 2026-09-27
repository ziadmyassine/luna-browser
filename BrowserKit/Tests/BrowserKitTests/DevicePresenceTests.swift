@testable import BrowserKit
import Foundation
import Synchronization
import Testing

/// Tabs on Other Macs (docs/SYNC-PLAN.md S12, §5): this Mac's Device record going up, and
/// other Macs' coming down. Driven through `FakeSyncEngine`.
@Suite("Device presence (§31.6)")
struct DevicePresenceTests {

    private let engine = FakeSyncEngine()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Sync on with the Devices zone, over a store holding one Space.
    private func started() async throws -> (BrowserStore, SyncCoordinator, UUID) {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let sync = SyncCoordinator(store: store, makeEngine: engine.factory)
        try await sync.enable(zones: [.devices])
        return (store, sync, space)
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func published(_ sync: SyncCoordinator) async throws -> SyncDevice? {
        let own = try await sync.deviceID().uuidString
        let records = try await sync.records(for: [.save(own, in: .devices)])
        return records.first.flatMap(SyncMapping.device(from:))
    }

    private func deviceRecord(_ id: UUID, name: String, modifiedAt: Date, tabs: [SyncDevice.OpenTab]) -> SyncRecord {
        var record = SyncMapping.record(for: SyncDevice(id: id, name: name, tabs: tabs), modifiedAt: modifiedAt, stored: nil)
        record.systemFields = Data([1])
        return record
    }

    // MARK: Going up

    @Test func publishingQueuesThisMacsDeviceRecord() async throws {
        let (store, sync, space) = try await started()
        try await store.upsert(Tab(spaceID: space, url: url("https://example.com/"), title: "Example"))

        try await sync.publishPresence(name: "Studio", now: start)

        let own = try await sync.deviceID().uuidString
        #expect(engine.pending.contains(.save(own, in: .devices)))
        let device = try #require(try await published(sync))
        #expect(device.name == "Studio")
        #expect(device.tabs == [SyncDevice.OpenTab(spaceID: space, url: url("https://example.com/"), title: "Example")])
    }

    @Test func cappedAtFiftyTabs() async throws {
        let (store, sync, space) = try await started()
        for index in 0..<60 {
            try await store.upsert(Tab(spaceID: space, url: url("https://example.com/\(index)"), order: index))
        }

        try await sync.publishPresence(name: "Studio", now: start)

        #expect(try await published(sync)?.tabs.count == 50)
    }

    @Test func blankInternalAndArchivedTabsAreSkipped() async throws {
        let (store, sync, space) = try await started()
        try await store.upsert(Tab(spaceID: space, url: url("about:blank")))
        try await store.upsert(Tab(spaceID: space, url: url("luna://settings")))
        try await store.upsert(Tab(spaceID: space, url: url("https://gone.example/"), archivedAt: start))
        try await store.upsert(Tab(spaceID: space, url: url("https://kept.example/")))

        try await sync.publishPresence(name: "Studio", now: start)

        #expect(try await published(sync)?.tabs.map(\.url) == [url("https://kept.example/")])
    }

    /// A private window is a session over a database of its own, so the coordinator,
    /// which reads only the main store, never sees its tabs.
    @Test func privateWindowTabsAreSkipped() async throws {
        let (store, sync, space) = try await started()
        let (privateStore, privateSpace) = try await makeTemporaryStoreWithSpace()
        try await privateStore.upsert(Tab(spaceID: privateSpace, url: url("https://secret.example/")))
        try await store.upsert(Tab(spaceID: space, url: url("https://public.example/")))

        try await sync.publishPresence(name: "Studio", now: start)

        #expect(try await published(sync)?.tabs.map(\.url) == [url("https://public.example/")])
    }

    @Test func atMostOnePublishAMinute() async throws {
        let (store, sync, space) = try await started()
        let own = try await sync.deviceID().uuidString
        try await sync.publishPresence(name: "Studio", now: start)
        engine.sent([SyncRecord(recordType: "Device", recordName: own, zone: "Devices", schemaVersion: 1)])

        try await store.upsert(Tab(spaceID: space, url: url("https://one.example/")))
        try await sync.publishPresence(name: "Studio", now: start.addingTimeInterval(30))
        #expect(!engine.pending.contains(.save(own, in: .devices)), "a change inside the minute waits")

        try await sync.publishPresence(name: "Studio", now: start.addingTimeInterval(61))
        #expect(engine.pending.contains(.save(own, in: .devices)))
    }

    @Test func anUnchangedTabSetIsNotPublishedAgain() async throws {
        let (_, sync, _) = try await started()
        let own = try await sync.deviceID().uuidString
        try await sync.publishPresence(name: "Studio", now: start)
        engine.sent([SyncRecord(recordType: "Device", recordName: own, zone: "Devices", schemaVersion: 1)])

        try await sync.publishPresence(name: "Studio", now: start.addingTimeInterval(120))

        #expect(engine.pending.isEmpty)
    }

    @Test func nothingIsPublishedWithTheDevicesZoneOff() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await store.upsert(Tab(spaceID: space, url: url("https://example.com/")))
        let sync = SyncCoordinator(store: store, makeEngine: engine.factory)
        try await sync.enable(zones: [.spaces])

        try await sync.publishPresence(name: "Studio", now: start)

        let own = try await sync.deviceID().uuidString
        #expect(!engine.pending.contains(.save(own, in: .devices)))
    }

    @Test func turningSyncOffDeletesThisMacsRecord() async throws {
        let (_, sync, _) = try await started()
        try await sync.publishPresence(name: "Studio", now: start)

        try await sync.disable()

        let own = try await sync.deviceID().uuidString
        #expect(engine.pending.contains(.delete(own, in: .devices)))
    }

    /// The next save must carry the server's change tag, or every one after the first
    /// comes back `serverRecordChanged`.
    @Test func aSavedRecordsSystemFieldsCarryIntoTheNextSave() async throws {
        let (_, sync, _) = try await started()
        try await sync.publishPresence(name: "Studio", now: start)
        var saved = try #require(try await sync.records(for: engine.pending).first)
        saved.systemFields = Data([7])

        try await sync.sent(saved: [saved])

        #expect(try await sync.records(for: [.save(saved.recordName, in: .devices)]).first?.systemFields == Data([7]))
    }

    // MARK: Coming down

    @Test func otherMacsArriveAndThisMacIsExcluded() async throws {
        let (_, sync, space) = try await started()
        let own = try await sync.deviceID()
        let laptop = UUID()
        let tab = SyncDevice.OpenTab(spaceID: space, url: url("https://laptop.example/"), title: "Laptop tab")

        try await sync.fetched(
            modifications: [
                deviceRecord(laptop, name: "Laptop", modifiedAt: start, tabs: [tab]),
                deviceRecord(own, name: "Studio", modifiedAt: start, tabs: [])
            ],
            deletions: []
        )

        #expect(try await sync.otherMacs(now: start) == [SyncDevice(id: laptop, name: "Laptop", tabs: [tab])])
    }

    @Test func macsOlderThanThirtyDaysAreHidden() async throws {
        let (_, sync, _) = try await started()
        let stale = UUID()
        let fresh = UUID()
        let now = start.addingTimeInterval(31 * 86_400)

        try await sync.fetched(
            modifications: [
                deviceRecord(stale, name: "Old Mac", modifiedAt: start, tabs: []),
                deviceRecord(fresh, name: "New Mac", modifiedAt: now.addingTimeInterval(-86_400), tabs: [])
            ],
            deletions: []
        )

        #expect(try await sync.otherMacs(now: now).map(\.id) == [fresh])
    }

    @Test func aDeletedDeviceRecordLeavesTheList() async throws {
        let (_, sync, _) = try await started()
        let laptop = UUID()
        try await sync.fetched(modifications: [deviceRecord(laptop, name: "Laptop", modifiedAt: start, tabs: [])], deletions: [])

        try await sync.fetched(
            modifications: [],
            deletions: [SyncDeletion(recordType: "Device", recordName: laptop.uuidString, zone: "Devices")]
        )

        #expect(try await sync.otherMacs(now: start).isEmpty)
    }

    @Test func incomingDevicesStillReachTheAppHook() async throws {
        let (store, _) = try await makeTemporaryStoreWithSpace()
        let heard = Mutex(0)
        let sync = SyncCoordinator(store: store, makeEngine: engine.factory, applyDevices: { _ in heard.withLock { $0 += 1 } })
        try await sync.enable(zones: [.devices])

        try await sync.fetched(modifications: [deviceRecord(UUID(), name: "Laptop", modifiedAt: start, tabs: [])], deletions: [])

        #expect(heard.withLock { $0 } == 1)
    }
}
