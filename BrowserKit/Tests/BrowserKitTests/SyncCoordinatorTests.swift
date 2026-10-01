@testable import BrowserKit
import Foundation
import GRDB
import Synchronization
import Testing

/// The coordinator driven through `FakeSyncEngine` (docs/plans/SYNC-PLAN.md S8). Nothing here
/// constructs a `CKContainer` or `CKSyncEngine`.
@Suite("Sync coordinator (§31)")
struct SyncCoordinatorTests {

    private static let serverFields = Data([0xC0, 0xFF, 0xEE])
    private static let newerServerFields = Data([0xBE, 0xEF])

    private let engine = FakeSyncEngine()

    private func coordinator(
        _ store: BrowserStore,
        applyInbound: (@Sendable (SyncChangeSet, Bool) async throws -> Void)? = nil,
        applySettings: @escaping @Sendable (SyncChangeSet) async throws -> Void = { _ in },
        applyDevices: @escaping @Sendable (SyncChangeSet) async throws -> Void = { _ in }
    ) -> SyncCoordinator {
        SyncCoordinator(
            store: store, makeEngine: engine.factory, applyInbound: applyInbound,
            applySettings: applySettings, applyDevices: applyDevices
        )
    }

    private func newSpace(_ name: String = "Work") -> Space {
        Space(name: name, symbolName: "briefcase", gradient: .defaultSpace)
    }

    private func fetched(_ record: SyncRecord, fields: Data = serverFields) -> SyncRecord {
        var record = record
        record.systemFields = fields
        return record
    }

    private func count(_ store: BrowserStore, _ sql: String, _ arguments: StatementArguments = []) async throws -> Int {
        try await store.pool.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    private func storedFields(_ store: BrowserStore, _ name: String) async throws -> Data? {
        try await store.pool.read { db in
            try Data.fetchOne(db, sql: "SELECT systemFields FROM syncRecords WHERE recordName = ?", arguments: [name])
        }
    }

    /// Sync on for `zones`, with the one Space it will send.
    private func started(_ zones: Set<SyncZone> = [.spaces]) async throws -> (BrowserStore, SyncCoordinator, Space) {
        let store = try makeTemporaryStore()
        let space = newSpace()
        try await store.upsert(space)
        let sync = coordinator(store)
        try await sync.enable(zones: zones)
        return (store, sync, space)
    }

    // MARK: Outbox → engine

    @Test func theOutboxBecomesPendingChanges() async throws {
        let (store, sync, space) = try await started()

        #expect(engine.pending == [.save(space.id.uuidString, in: .spaces)])
        #expect(Set(engine.zoneSaves) == [.spaces, .meta])

        try await store.delete(spaceID: space.id)
        try await sync.pushOutbox()
        #expect(engine.pending.contains(.delete(space.id.uuidString, in: .spaces)))
    }

    @Test func theBatchIsBuiltFromCurrentRows() async throws {
        let (store, sync, space) = try await started()
        var renamed = space
        renamed.name = "Renamed"
        try await store.upsert(renamed)

        let records = try await sync.records(for: engine.pending)
        #expect(records.count == 1)
        #expect(SyncMapping.space(from: records[0])?.name == "Renamed")
        #expect(records[0].zone == SyncZone.spaces.rawValue)
    }

    @Test func aRowThatIsGoneLeavesThePendingChanges() async throws {
        let (store, sync, space) = try await started()
        let pending = engine.pending
        try await store.delete(spaceID: space.id)

        #expect(try await sync.records(for: pending).isEmpty)
        #expect(!engine.pending.contains(.save(space.id.uuidString, in: .spaces)))
    }

    @Test func aSaveClearsTheOutboxRowOnlyIfItHasNotMoved() async throws {
        let (store, sync, space) = try await started()
        let sent = try await sync.records(for: engine.pending).map { fetched($0) }

        try await Task.sleep(for: .milliseconds(5))
        var renamed = space
        renamed.name = "Edited while sending"
        try await store.upsert(renamed)
        try await sync.sent(saved: sent)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 1, "the newer edit still has to go")
        #expect(try await storedFields(store, space.id.uuidString) == Self.serverFields)

        let resent = try await sync.records(for: engine.pending).map { fetched($0) }
        try await sync.sent(saved: resent)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 0)
    }

    @Test func aSentDeleteForgetsTheRecord() async throws {
        let (store, sync, space) = try await started()
        try await sync.sent(saved: sync.records(for: engine.pending).map { fetched($0) })
        try await store.delete(spaceID: space.id)
        try await sync.pushOutbox()

        try await sync.sent(deleted: [space.id.uuidString])
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 0)
        #expect(try await storedFields(store, space.id.uuidString) == nil)
    }

    // MARK: Conflicts

    /// S6 skips an incoming record older than a pending local edit and keeps none of its
    /// system fields, so the local save meets the server's change tag, merges, and goes
    /// again carrying it.
    @Test func serverRecordChangedMergesAndRequeues() async throws {
        let (store, sync, space) = try await started()
        try await sync.fetchFinished()
        var older = space
        older.name = "Older elsewhere"
        let server = fetched(SyncMapping.record(for: older, modifiedAt: Date().addingTimeInterval(-60), stored: nil))
        var mine = space
        mine.name = "Mine"
        try await store.upsert(mine)

        try await sync.fetched(modifications: [server], deletions: [])
        #expect(try await store.spaces().first?.name == "Mine")
        #expect(try await storedFields(store, space.id.uuidString) == nil)

        let attempt = try await sync.records(for: engine.pending)
        #expect(attempt.first?.systemFields == nil)
        engine.sent(attempt)
        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .serverRecordChanged(server)) })

        #expect(engine.pending == [.save(space.id.uuidString, in: .spaces)])
        let retry = try await sync.records(for: engine.pending)
        #expect(retry.first?.systemFields == Self.serverFields)
        #expect(retry.first.flatMap(SyncMapping.space(from:))?.name == "Mine")
    }

    @Test func aNewerServerRecordWinsTheConflict() async throws {
        let (store, sync, space) = try await started()
        let attempt = try await sync.records(for: engine.pending)
        engine.sent(attempt)
        var theirs = space
        theirs.name = "Theirs"
        let server = fetched(SyncMapping.record(for: theirs, modifiedAt: Date().addingTimeInterval(60), stored: nil))

        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .serverRecordChanged(server)) })

        #expect(try await store.spaces().first?.name == "Theirs")
        #expect(engine.pending.isEmpty)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 0)
        #expect(try await storedFields(store, space.id.uuidString) == Self.serverFields)
    }

    /// Delete beats edit for the structure: a Space deleted elsewhere goes here too.
    @Test func unknownItemDeletesASpaceLocally() async throws {
        let (store, sync, space) = try await started()
        let attempt = try await sync.records(for: engine.pending)
        engine.sent(attempt)

        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .unknownItem) })

        #expect(try await store.spaces().map(\.id).contains(space.id) == false)
        #expect(engine.pending.isEmpty)
    }

    /// Anything else that is set beats unset: a site setting deleted elsewhere is saved
    /// again as a new record.
    @Test func unknownItemResavesASiteSetting() async throws {
        let (store, sync, _) = try await started([.sites])
        let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))
        try await sync.fetched(modifications: [fetched(secret.record(stored: nil))], deletions: [])
        try await store.setSitePermission(.savePasswords, allowed: true, host: "example.com")
        try await sync.pushOutbox()
        let name = secret.siteRecordName(forHost: "example.com")
        #expect(engine.pending.contains(.save(name, in: .sites)))
        let saved = try await sync.records(for: [.save(name, in: .sites)]).map { fetched($0) }
        try await sync.sent(saved: saved)
        try await store.setSitePermission(.savePasswords, allowed: false, host: "example.com")
        try await sync.pushOutbox()
        let attempt = try await sync.records(for: [.save(name, in: .sites)])
        engine.sent(attempt)

        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .unknownItem) })

        #expect(try await store.sitePermissions()[.savePasswords]?["example.com"] == false)
        #expect(engine.pending.contains(.save(name, in: .sites)))
        #expect(try await sync.records(for: [.save(name, in: .sites)]).first?.systemFields == nil)
    }

    @Test func zoneNotFoundSavesTheZoneAgain() async throws {
        let (_, sync, space) = try await started()
        let attempt = try await sync.records(for: engine.pending)
        engine.sent(attempt)
        let before = engine.zoneSaves.count

        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .zoneNotFound) })

        #expect(engine.zoneSaves.dropFirst(before) == [.spaces])
        #expect(engine.pending == [.save(space.id.uuidString, in: .spaces)])
    }

    // MARK: Status

    @Test func errorsSetTheStatus() async throws {
        let (store, sync, _) = try await started()
        let attempt = try await sync.records(for: engine.pending)

        try await sync.sent(failed: attempt.map { SyncSaveFailure(record: $0, error: .quotaExceeded) })
        #expect(await sync.status == .storageFull)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 1, "the outbox waits for space")

        await sync.failed(.networkUnavailable)
        #expect(await sync.status == .offline)
        await sync.failed(.notAuthenticated)
        #expect(await sync.status == .noAccount)
        await sync.failed(.temporarilyUnavailable)
        #expect(await sync.status == .unavailable)

        try await sync.fetchFinished()
        guard case .synced = await sync.status else { Issue.record("expected synced"); return }
    }

    @Test func theStatusLines() {
        let now = Date()
        #expect(SyncStatus.off.line() == "iCloud sync off")
        #expect(SyncStatus.needsSignedBuild.line() == "iCloud sync needs the signed build.")
        #expect(SyncStatus.noAccount.line() == "Sign in to iCloud to sync.")
        #expect(SyncStatus.unavailable.line() == "iCloud is unavailable right now.")
        #expect(SyncStatus.switchedAccount.line() == "Signed into a different iCloud account.")
        #expect(SyncStatus.storageFull.line() == "iCloud storage is full.")
        #expect(SyncStatus.offline.line() == "Offline — will sync when connected.")
        #expect(SyncStatus.removedElsewhere.line() == "Luna's iCloud data was removed from another Mac.")
        let twoMinutesAgo = SyncStatus.synced(now.addingTimeInterval(-120))
        #expect(twoMinutesAgo.line(now: now, locale: Locale(identifier: "en_US")) == "Synced 2 minutes ago")
        #expect(SyncStatus.synced(now).line(now: now) == "Synced just now")
    }

    // MARK: Engine state

    @Test func engineStateIsSavedAndHandedBackOnStart() async throws {
        let (store, sync, _) = try await started()
        #expect(engine.startedWith == [nil])
        try await sync.stateUpdated(Data([1, 2, 3]))

        let relaunched = coordinator(store)
        try await relaunched.start()
        #expect(engine.startedWith == [nil, Data([1, 2, 3])])
    }

    @Test func withSyncOffStartMakesNoEngine() async throws {
        let sync = coordinator(try makeTemporaryStore())
        try await sync.start()
        #expect(engine.startedWith.isEmpty)
        #expect(await sync.status == .off)
    }

}

// MARK: Account and zones

extension SyncCoordinatorTests {

    private func syncState(_ store: BrowserStore) async throws -> Int {
        try await count(store, """
        SELECT (SELECT COUNT(*) FROM syncRecords) + (SELECT COUNT(*) FROM syncOutbox) + (SELECT COUNT(*) FROM syncParked)
             + (SELECT COUNT(*) FROM syncMeta WHERE key NOT IN ('deviceID', 'userRecordName'))
        """)
    }

    private func synced() async throws -> (BrowserStore, SyncCoordinator, UUID) {
        let (store, sync, _) = try await started()
        try await sync.stateUpdated(Data([9]))
        try await sync.accountChanged(.signIn(userRecordName: "_alice"))
        try await sync.sent(saved: sync.records(for: engine.pending).map { fetched($0) })
        try await store.upsert(newSpace("Unsent"))
        let device = try await sync.deviceID()
        #expect(try await syncState(store) > 0)
        return (store, sync, device)
    }

    @Test func signingOutWipesSyncStateAndKeepsLocalData() async throws {
        let (store, sync, device) = try await synced()

        try await sync.accountChanged(.signOut)

        #expect(try await syncState(store) == 0)
        #expect(try await sync.deviceID() == device)
        #expect(try await store.spaces().count == 2)
        #expect(await sync.status == .noAccount)
    }

    @Test func switchingAccountWipesAndTurnsSyncOff() async throws {
        let (store, sync, _) = try await synced()

        try await sync.accountChanged(.switchAccounts)

        #expect(try await syncState(store) == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncZones") == 0)
        #expect(try await store.spaces().count == 2)
        #expect(await sync.status == .switchedAccount)
    }

    @Test func aDifferentUserRecordNameIsASwitch() async throws {
        let (store, sync, _) = try await synced()

        try await sync.accountChanged(.signIn(userRecordName: "_bob"))

        #expect(try await count(store, "SELECT COUNT(*) FROM syncZones") == 0)
        #expect(await sync.status == .switchedAccount)
    }

    @Test func zonesDeletedElsewhereTurnSyncOff() async throws {
        let (store, sync, _) = try await synced()

        try await sync.zonesDeleted([.spaces], reason: .deleted)

        #expect(try await syncState(store) == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncZones") == 0)
        #expect(try await store.spaces().count == 2)
        #expect(await sync.status == .removedElsewhere)
    }

    @Test func anEncryptedDataResetUploadsEverythingAgain() async throws {
        let (store, sync, _) = try await synced()
        let zoneSaves = engine.zoneSaves.count

        try await sync.zonesDeleted([.spaces], reason: .encryptedDataReset)

        #expect(try await count(store, "SELECT COUNT(*) FROM syncRecords") == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 2)
        #expect(Set(engine.zoneSaves.dropFirst(zoneSaves)) == [.spaces, .meta])
        #expect(try await sync.records(for: engine.pending).allSatisfy { $0.systemFields == nil })
    }

    @Test func removeAllDeletesEveryZoneAndWipes() async throws {
        let (store, sync, _) = try await synced()

        try await sync.removeAll()

        #expect(Set(engine.zoneDeletes) == Set(SyncZone.allCases))
        #expect(try await syncState(store) == 0)
        #expect(try await count(store, "SELECT COUNT(*) FROM syncZones") == 0)
        #expect(await sync.status == .off)
    }

    /// Turning a zone off drops its outbox rows (S3), so what it still had pending is
    /// dropped when the batch asks for it.
    @Test func aZoneTurnedOffDropsItsPendingChanges() async throws {
        let (_, sync, _) = try await started()

        try await sync.setZone(.spaces, enabled: false)

        #expect(try await sync.records(for: engine.pending).isEmpty)
        #expect(engine.pending.isEmpty)
    }

    // MARK: Incoming

    @Test func theDeviceIDIsMadeOnceAndKept() async throws {
        let store = try makeTemporaryStore()
        let first = try await coordinator(store).deviceID()
        #expect(try await coordinator(store).deviceID() == first)
    }

    /// Re-enabling sync fetches everything again, this Mac's own history included; those
    /// visits are already here.
    @Test func thisMacsOwnHistoryIsNotAppliedAgain() async throws {
        let (store, sync, space) = try await started([.spaces, .history])
        let visit = SyncHistoryEntry.Visit(spaceID: space.id, at: Date(), kind: "typed")
        func entry(_ device: UUID, _ place: Int64) -> SyncRecord {
            let url = URL(string: "https://e\(place).example")!
            let entry = SyncHistoryEntry(deviceID: device, placeID: place, url: url, title: "", visits: [visit])
            return fetched(SyncMapping.record(for: entry, modifiedAt: Date(), stored: nil))
        }

        try await sync.fetched(modifications: [entry(sync.deviceID(), 1), entry(UUID(), 2)], deletions: [])

        #expect(try await count(store, "SELECT COUNT(*) FROM visits") == 1)
    }

    @Test func isFirstFetchHoldsUntilAFetchCompletes() async throws {
        let seen = Mutex<[Bool]>([])
        let store = try makeTemporaryStore()
        let record = { @Sendable (_: SyncChangeSet, first: Bool) in seen.withLock { $0.append(first) } }
        let sync = coordinator(store, applyInbound: record)
        try await sync.enable(zones: [.spaces])
        let change = fetched(SyncMapping.record(for: newSpace(), modifiedAt: Date(), stored: nil))

        try await sync.fetched(modifications: [change], deletions: [])
        try await sync.fetchFinished()
        try await coordinator(store, applyInbound: record).fetched(modifications: [change], deletions: [])

        #expect(seen.withLock { $0 } == [true, false])
    }

    /// On the fetch after turning sync on, iCloud wins for every record it has (§3), even
    /// over the outbox rows turning the zone on just queued.
    @Test func theFirstFetchLetsICloudWin() async throws {
        let (store, sync, space) = try await started()
        var theirs = space
        theirs.name = "From iCloud"

        try await sync.fetched(
            modifications: [fetched(SyncMapping.record(for: theirs, modifiedAt: Date().addingTimeInterval(-3600), stored: nil))],
            deletions: []
        )

        #expect(try await store.spaces().first?.name == "From iCloud")
        #expect(try await count(store, "SELECT COUNT(*) FROM syncOutbox") == 0)
    }

    @Test func settingsDevicesAndTheSecretAreRouted() async throws {
        let settings = Mutex<[SyncChangeSet]>([])
        let devices = Mutex<[SyncChangeSet]>([])
        let store = try makeTemporaryStore()
        let sync = coordinator(
            store,
            applySettings: { change in settings.withLock { $0.append(change) } },
            applyDevices: { change in devices.withLock { $0.append(change) } }
        )
        try await sync.enable(zones: [.settings, .devices, .sites])
        try await store.setSitePermission(.savePasswords, allowed: true, host: "example.com")
        try await sync.pushOutbox()
        #expect(!engine.pending.contains { $0.zone == .sites }, "nothing keyed by the secret before it settles")

        var setting = SyncMapping.record(for: SyncSamples.setting, modifiedAt: Date(), stored: nil)
        setting.schemaVersion = 3
        let device = SyncMapping.record(for: SyncSamples.device, modifiedAt: Date(), stored: nil)
        let secret = SyncSecret(bytes: Data(repeating: 7, count: 32))
        try await sync.fetched(
            modifications: [fetched(setting), fetched(device), fetched(secret.record(stored: nil))],
            deletions: [SyncDeletion(recordType: "Setting", recordName: "search.engine", zone: SyncZone.settings.rawValue)]
        )

        #expect(settings.withLock { $0.first?.modifications.map(\.recordName) } == [SyncSamples.setting.key])
        #expect(settings.withLock { $0.first?.deletions.map(\.recordName) } == ["search.engine"])
        #expect(devices.withLock { $0.first?.modifications.map(\.recordName) } == [SyncSamples.device.id.uuidString])
        for name in [SyncSamples.setting.key, SyncSamples.device.id.uuidString, "secret"] {
            #expect(try await storedFields(store, name) == Self.serverFields)
        }
        #expect(try await count(store, "SELECT schemaVersion FROM syncRecords WHERE recordName = ?", [SyncSamples.setting.key]) == 3)
        #expect(engine.pending.contains(.save(secret.siteRecordName(forHost: "example.com"), in: .sites)))
    }

    /// With no secret on the server after a fetch, this Mac proposes one; site records
    /// wait until the server has accepted it.
    @Test func aMissingSecretIsProposedAndSettlesOnSave() async throws {
        let (store, sync, _) = try await started([.sites])
        try await store.setSitePermission(.savePasswords, allowed: true, host: "example.com")
        try await sync.fetchFinished()
        #expect(engine.pending.contains(.save("secret", in: .meta)))
        #expect(!engine.pending.contains { $0.zone == .sites })

        let proposal = try await sync.records(for: [.save("secret", in: .meta)]).map { fetched($0) }
        try await sync.sent(saved: proposal)

        let secret = try #require(proposal.first.flatMap(SyncSecret.init(record:)))
        #expect(engine.pending.contains(.save(secret.siteRecordName(forHost: "example.com"), in: .sites)))
    }
}

// MARK: The app's calls (S11)

extension SyncCoordinatorTests {

    @Test func syncNowFetchesThenSends() async throws {
        let (_, sync, _) = try await started()
        let before = engine.calls.withLock { ($0.fetches, $0.sends) }

        try await sync.syncNow()

        let after = engine.calls.withLock { ($0.fetches, $0.sends) }
        #expect(after.0 == before.0 + 1)
        #expect(after.1 == before.1 + 1)
    }

    /// An app activation with sync off must not reach CloudKit at all.
    @Test func fetchAsksTheEngineOnlyWhileSyncIsOn() async throws {
        let store = try makeTemporaryStore()
        let sync = coordinator(store)
        try await sync.start()
        try await sync.fetch()
        #expect(engine.startedWith.isEmpty, "sync off built an engine")
        #expect(engine.calls.withLock(\.fetches) == 0)

        try await sync.enable(zones: [.spaces])
        let fetches = engine.calls.withLock(\.fetches)
        try await sync.fetch()
        #expect(engine.calls.withLock(\.fetches) == fetches + 1)
    }

    /// Writers other than the session (history, site settings, the importer) fill the
    /// outbox too, so the coordinator hears the outbox rather than any one caller.
    @Test func aLocalWriteReachesTheEngineWithoutBeingPushed() async throws {
        let (store, sync, _) = try await started()
        let later = newSpace("Later")
        try await store.upsert(later)

        let change = SyncPendingChange.save(later.id.uuidString, in: .spaces)
        for _ in 0..<50 where !engine.pending.contains(change) { try await Task.sleep(for: .milliseconds(100)) }
        #expect(engine.pending.contains(change))
        withExtendedLifetime(sync) {}
    }
}
