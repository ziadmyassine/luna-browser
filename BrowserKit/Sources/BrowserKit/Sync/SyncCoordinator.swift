import Foundation

// All of sync's decisions (docs/SYNC-PLAN.md §1, §3, §4): the outbox becomes the engine's
// pending changes, a batch is built from the rows as they are now, and each engine event
// arrives here as plain values. The engine is behind `SyncEngineControl`, so none of this
// needs iCloud to test.

public actor SyncCoordinator {

    public typealias Apply = @Sendable (SyncChangeSet) async throws -> Void

    let store: BrowserStore
    private let makeEngine: @Sendable (Data?) -> any SyncEngineControl
    private let applyInbound: @Sendable (SyncChangeSet, _ isFirstFetch: Bool) async throws -> Void
    private let applySettings: Apply
    private let applyDevices: Apply
    private let onStatus: @MainActor @Sendable (SyncStatus) -> Void

    var engine: (any SyncEngineControl)?
    private var secret = SyncSecretState()
    /// The outbox key of every change handed to the engine. A relaunch rebuilds it from the
    /// outbox and `syncRecords`.
    var keys: [String: (recordType: String, localKey: String)] = [:]
    var presence = SyncPresenceState()
    /// The names a fetch from no saved state has brought so far, which is every record
    /// iCloud holds once it finishes. Nil for a fetch resumed from saved state: that one
    /// brings only what changed since, so a name missing from it proves nothing.
    private var fullFetch: Set<String>?
    public private(set) var status = SyncStatus.off

    /// - Parameters:
    ///   - makeEngine: the engine, started from the state it last saved (nil for a fresh one).
    ///   - applyInbound: Spaces, groups, tabs, sites and history from other Macs. By default
    ///     straight to the store; the app routes them through the session (S10).
    ///   - applySettings: incoming `Setting` records (S9).
    ///   - applyDevices: told when other Macs' `Device` records have changed; they are
    ///     already in the store, for `otherMacs`.
    public init(
        store: BrowserStore,
        makeEngine: @escaping @Sendable (Data?) -> any SyncEngineControl,
        applyInbound: (@Sendable (SyncChangeSet, Bool) async throws -> Void)? = nil,
        applySettings: @escaping Apply = { _ in },
        applyDevices: @escaping Apply = { _ in },
        onStatus: @escaping @MainActor @Sendable (SyncStatus) -> Void = { _ in }
    ) {
        self.store = store
        self.makeEngine = makeEngine
        self.applyInbound = applyInbound ?? { changes, isFirstFetch in
            try await store.applyRemote(changes, isFirstFetch: isFirstFetch)
        }
        self.applySettings = applySettings
        self.applyDevices = applyDevices
        self.onStatus = onStatus
    }

    // MARK: Switches

    /// At launch: an engine only while a zone is on (§4, Sync off: no `cloudd` traffic).
    public func start() async throws {
        guard !(try await store.enabledSyncZones().isEmpty) else { return await report(.off) }
        if let bytes = try await store.syncMeta(SyncMetaKey.secret) {
            secret = SyncSecretState(settled: SyncSecret(bytes: bytes))
        }
        let state = try await store.syncMeta(SyncMetaKey.engineState)
        engine = makeEngine(state)
        fullFetch = state == nil ? [] : nil
        let last = try await store.syncMeta(SyncMetaKey.lastSyncedAt)
            .flatMap { String(bytes: $0, encoding: .utf8) }.flatMap(Double.init)
        await report(last.map { .synced(Date(timeIntervalSince1970: $0)) } ?? .syncing)
        try await pushOutbox()
    }

    /// The master switch on, with these zones. `Meta` comes with any of them.
    public func enable(zones: Set<SyncZone>) async throws {
        let zones = zones.union([.meta])
        for zone in zones { try await store.setSyncZone(zone, enabled: true) }
        if engine == nil { try await start() } else { try await pushOutbox() }
        await engine?.addZoneSaves(Array(zones))
        try await engine?.fetchChanges()
    }

    /// The master switch off. The system fields stay, so turning sync back on can tell
    /// rows iCloud once had (§3); the engine state goes, so that turn-on fetches everything.
    public func disable() async throws {
        if try await store.enabledSyncZones().contains(.devices) {
            await engine?.add(pending: [.delete(try await deviceID().uuidString, in: .devices)])
            try? await engine?.sendChanges()
        }
        presence = SyncPresenceState()
        for zone in try await store.enabledSyncZones() { try await store.setSyncZone(zone, enabled: false) }
        try await store.setSyncMeta(SyncMetaKey.engineState, nil)
        try await store.setSyncMeta(SyncMetaKey.fetchedOnce, nil)
        engine = nil
        fullFetch = nil
        await report(.off)
    }

    /// One zone's switch. Off drops its outbox rows (S3), and whatever it still had
    /// pending is dropped when a batch asks for it.
    public func setZone(_ zone: SyncZone, enabled: Bool) async throws {
        try await store.setSyncZone(zone, enabled: enabled)
        guard enabled else { return }
        await engine?.addZoneSaves([zone])
        try await pushOutbox()
    }

    /// Remove Luna Data from iCloud: every zone goes, and with it this Mac's sync state.
    public func removeAll() async throws {
        let engine = engine ?? makeEngine(nil)
        await engine.addZoneDeletes(SyncZone.allCases)
        try await engine.sendChanges()
        try await turnOff()
        await report(.off)
    }

    public func deviceID() async throws -> UUID {
        try await store.syncDeviceID()
    }

    // MARK: Outgoing

    /// Hands the outbox to the engine. Site records wait until the secret has settled.
    public func pushOutbox() async throws {
        guard let engine else { return }
        let device = try await deviceID()
        var changes: [SyncPendingChange] = []
        for entry in try await store.syncOutbox() {
            guard let zone = SyncZone(rawValue: entry.zone),
                  let name = SyncKeys.recordName(entry, deviceID: device, secret: secret.settled) else { continue }
            keys[name] = (entry.recordType, entry.localKey)
            changes.append(entry.isDelete ? .delete(name, in: zone) : .save(name, in: zone))
        }
        await engine.add(pending: changes)
    }

    /// `nextRecordZoneChangeBatch`: the records for these saves, built from the rows as
    /// they are now. A save whose row is gone, or whose zone is off, leaves the engine.
    public func records(for changes: [SyncPendingChange]) async throws -> [SyncRecord] {
        let zones = try await store.enabledSyncZones()
        let device = try await deviceID()
        var records: [SyncRecord] = []
        var gone: [SyncPendingChange] = []
        for change in changes where !change.isDelete {
            if zones.contains(change.zone), let record = try await record(named: change.recordName, device: device) {
                records.append(record)
            } else {
                gone.append(change)
            }
        }
        if !gone.isEmpty { await engine?.remove(pending: gone) }
        return records
    }

    private func record(named name: String, device: UUID) async throws -> SyncRecord? {
        if name == SyncSecret.recordName {
            let stored = try await store.storedRecord(named: name)
            return (secret.settled ?? secret.proposal()).record(stored: stored)
        }
        guard let key = try await key(of: name) else { return nil }
        if key.recordType == "Device" { return try await presenceRecord(named: name) }
        return try await store.outgoingRecord(key.recordType, localKey: key.localKey, deviceID: device, secret: secret.settled)
    }

    private func key(of name: String) async throws -> (recordType: String, localKey: String)? {
        if let key = keys[name] { return key }
        return try await store.storedKey(of: name)
    }

    /// `sentRecordZoneChanges`.
    public func sent(saved: [SyncRecord] = [], deleted: [String] = [], failed: [SyncSaveFailure] = []) async throws {
        // Saved while the full fetch runs, so it may not be in it, and is on the server.
        fullFetch?.formUnion(saved.map(\.recordName))
        for record in saved {
            if record.recordType == SyncSecret.recordType {
                secret.saved()
                try await settled(record)
                continue
            }
            guard let key = try await key(of: record.recordName) else { continue }
            try await store.storeSystemFields(of: record, localKey: key.localKey)
            let modifiedAt: Date? = if case .date(let date) = record["modifiedAt"] { date } else { nil }
            try await store.clearOutbox(key.recordType, key.localKey, savedAt: modifiedAt ?? .distantFuture)
        }
        for name in deleted {
            guard let key = try await key(of: name) else { continue }
            try await store.forgetSystemFields(of: name)
            try await store.clearOutbox(key.recordType, key.localKey, savedAt: nil)
            keys[name] = nil
        }
        for failure in failed { try await handle(failure) }
    }

    private func handle(_ failure: SyncSaveFailure) async throws {
        let record = failure.record
        switch failure.error {
        case .serverRecordChanged(let server):
            try await merge(record, server: server)
        case .unknownItem:
            try await merge(record, server: nil)
        case .zoneNotFound:
            guard let zone = SyncZone(rawValue: record.zone) else { return }
            await engine?.addZoneSaves([zone])
            await engine?.add(pending: [.save(record.recordName, in: zone)])
        default:
            await failed(failure.error)
        }
    }

    /// A save the server refused because its copy moved on or is gone (§3). `unknownItem`
    /// is not one rule: `SyncMerge` deletes a Space, group or tab locally and saves
    /// anything else again as a new record.
    private func merge(_ sent: SyncRecord, server: SyncRecord?) async throws {
        guard let zone = SyncZone(rawValue: sent.zone) else { return }
        if sent.recordType == SyncSecret.recordType { return try await mergeSecret(sent, server: server, zone: zone) }
        guard let key = try await key(of: sent.recordName) else { return }
        let changedAt = try await store.outboxEntry(key.recordType, key.localKey)?.changedAt ?? Date()
        switch SyncMerge.resolve(recordType: sent.recordType, local: sent, changedAt: changedAt, server: server) {
        case .takeServer:
            try await store.clearOutbox(key.recordType, key.localKey, savedAt: .distantFuture)
            let gone = SyncDeletion(recordType: sent.recordType, recordName: sent.recordName, zone: sent.zone)
            try await fetched(modifications: server.map { [$0] } ?? [], deletions: server == nil ? [gone] : [])
        case .save(let merged):
            if let server {
                try await store.storeSystemFields(of: server, localKey: key.localKey)
            } else {
                try await store.forgetSystemFields(of: sent.recordName)
            }
            // A field merge can bring the server's answers in; the other types' merge is
            // this Mac's row as it stands.
            if merged.recordType == "SiteSetting", server != nil {
                try await applyInbound(SyncChangeSet(modifications: [merged]), false)
            }
            await engine?.add(pending: [.save(sent.recordName, in: zone)])
        case .deleteOnServer:
            if let server { try await store.storeSystemFields(of: server, localKey: key.localKey) }
            await engine?.add(pending: [.delete(sent.recordName, in: zone)])
        }
    }

    /// The server always wins; a secret gone from it is saved again.
    private func mergeSecret(_ sent: SyncRecord, server: SyncRecord?, zone: SyncZone) async throws {
        guard let server else {
            await engine?.add(pending: [.save(sent.recordName, in: zone)])
            return
        }
        try await fetched(modifications: [server], deletions: [])
    }
}

// MARK: Incoming

extension SyncCoordinator {

    /// `fetchedRecordZoneChanges`. Settings and Devices go to their own owners, the secret
    /// to `SyncSecretState`; the store's own types go through `applyInbound`, which keeps
    /// their system fields itself.
    public func fetched(modifications: [SyncRecord], deletions: [SyncDeletion]) async throws {
        fullFetch?.formUnion(modifications.map(\.recordName))
        let device = try await deviceID().uuidString
        // This Mac's own history, fetched again after sync was turned back on. Its visits
        // are here already; applying them would count each twice.
        let ownHistory = modifications.filter { $0.recordType == "HistoryEntry" && $0.recordName.hasPrefix(device) }
        for record in ownHistory {
            try await store.storeSystemFields(of: record, localKey: String(record.recordName.dropFirst(device.count + 1)))
        }
        for record in modifications where record.recordType == SyncSecret.recordType {
            secret.received(record)
            try await settled(record)
        }
        let changes = SyncChangeSet(
            modifications: modifications.filter { $0.recordType != SyncSecret.recordType && !ownHistory.contains($0) },
            deletions: deletions
        )
        let settings = changes.only { $0 == "Setting" }
        let devices = changes.only { $0 == "Device" }
        let inbound = changes.only { $0 != "Setting" && $0 != "Device" }
        for record in settings.modifications + devices.modifications {
            try await store.storeSystemFields(of: record, localKey: record.recordName)
        }
        for deletion in settings.deletions + devices.deletions { try await store.forgetSystemFields(of: deletion.recordName) }
        try await store.applyPresence(devices)
        if !inbound.isEmpty { try await applyInbound(inbound, try await store.syncMeta(SyncMetaKey.fetchedOnce) == nil) }
        if !settings.isEmpty { try await applySettings(settings) }
        if !devices.isEmpty { try await applyDevices(devices) }
    }

    /// `didFetchChanges`. With site settings on and no secret on the server, this Mac
    /// proposes one; site records wait until the server has accepted it.
    public func fetchFinished() async throws {
        if let seen = fullFetch {
            fullFetch = nil
            try await deleteWhatTheFullFetchLacked(seen)
        }
        let now = Date()
        try await store.setSyncMeta(SyncMetaKey.fetchedOnce, Data([1]))
        try await store.setSyncMeta(SyncMetaKey.lastSyncedAt, Data(String(now.timeIntervalSince1970).utf8))
        await report(.synced(now))
        guard secret.settled == nil, try await store.enabledSyncZones().contains(.sites) else { return }
        _ = secret.proposal()
        await engine?.add(pending: [.save(SyncSecret.recordName, in: .meta)])
    }

    /// §3, turning sync on: a row whose system fields prove iCloud once had it, and which
    /// the full fetch did not bring, was deleted on another Mac while this one was not
    /// listening. It leaves as any other deletion does, through `fetched`, so the session
    /// tears it down too. Rows with no system fields are the other half of that rule, and
    /// the outbox seeded when the zone came on is already sending them.
    private func deleteWhatTheFullFetchLacked(_ seen: Set<String>) async throws {
        let gone = try await store.syncedRecords(in: store.enabledSyncZones())
            .filter { $0.recordType != SyncSecret.recordType && !seen.contains($0.recordName) }
        if !gone.isEmpty { try await fetched(modifications: [], deletions: gone) }
    }

    /// The secret settled, fetched or saved: keep it, and send the site records it names.
    private func settled(_ record: SyncRecord) async throws {
        guard let settled = secret.settled else { return }
        try await store.setSyncMeta(SyncMetaKey.secret, settled.bytes)
        try await store.storeSystemFields(of: record, localKey: SyncSecret.recordName)
        try await pushOutbox()
    }

}

// MARK: Account, zones and state

extension SyncCoordinator {

    /// §4. A sign-in queues every row again, since a sign-out or a fresh engine left the
    /// server knowing nothing of this Mac.
    public func accountChanged(_ change: SyncAccountChange) async throws {
        switch change {
        case .signIn(let user):
            let stored = try await store.syncMeta(SyncMetaKey.userRecordName).flatMap { String(bytes: $0, encoding: .utf8) }
            if let stored, stored != user { return try await accountChanged(.switchAccounts) }
            try await store.setSyncMeta(SyncMetaKey.userRecordName, Data(user.utf8))
            try await store.reseedSyncZones(forgettingSystemFields: false)
            try await pushOutbox()
        case .signOut:
            // The user record name stays, so signing into another account reads as a switch.
            try await store.wipeSyncState(keeping: [SyncMetaKey.deviceID, SyncMetaKey.userRecordName], turningSyncOff: false)
            secret = SyncSecretState()
            keys = [:]
            presence = SyncPresenceState()
            await report(.noAccount)
        case .switchAccounts:
            // Nothing goes up to the new account until the user turns sync on again.
            try await turnOff()
            await report(.switchedAccount)
        }
    }

    public func zonesDeleted(_ zones: [SyncZone], reason: SyncZoneDeletionReason) async throws {
        switch reason {
        case .deleted, .purged:
            try await turnOff()
            await report(.removedElsewhere)
        case .encryptedDataReset:
            try await store.reseedSyncZones(forgettingSystemFields: true)
            await engine?.addZoneSaves(Array(try await store.enabledSyncZones()))
            try await pushOutbox()
            if secret.settled != nil { await engine?.add(pending: [.save(SyncSecret.recordName, in: .meta)]) }
        }
    }

    /// `stateUpdate`. An engine already dropped by `turnOff` does not write it back.
    public func stateUpdated(_ state: Data) async throws {
        guard engine != nil else { return }
        try await store.setSyncMeta(SyncMetaKey.engineState, state)
    }

    /// An error outside a single record's save: the engine retries, the status says why.
    public func failed(_ error: SyncError) async {
        switch error {
        case .quotaExceeded: await report(.storageFull)
        case .networkUnavailable: await report(.offline)
        case .notAuthenticated: await report(.noAccount)
        case .temporarilyUnavailable: await report(.unavailable)
        default: break
        }
    }

    private func turnOff() async throws {
        try await store.wipeSyncState(keeping: [SyncMetaKey.deviceID], turningSyncOff: true)
        secret = SyncSecretState()
        keys = [:]
        presence = SyncPresenceState()
        engine = nil
        fullFetch = nil
    }

    private func report(_ status: SyncStatus) async {
        self.status = status
        await onStatus(status)
    }
}

private extension SyncChangeSet {
    var isEmpty: Bool { modifications.isEmpty && deletions.isEmpty }

    func only(_ type: (String) -> Bool) -> SyncChangeSet {
        SyncChangeSet(modifications: modifications.filter { type($0.recordType) }, deletions: deletions.filter { type($0.recordType) })
    }
}
