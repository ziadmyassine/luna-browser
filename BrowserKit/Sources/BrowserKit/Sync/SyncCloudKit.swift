import CloudKit
import Foundation

// The only file that touches `CKRecord` or `CKSyncEngine` (docs/SYNC-PLAN.md §1): the
// conversion between `CKRecord` and `SyncRecord`, and `SyncCloudKitEngine`, the live
// `SyncEngineControl`.
//
// Only `SyncCloudKitEngine.init` constructs a `CKContainer`. The rest works on plain
// values, which is what lets `CloudKitBoundaryTests` run in an unsigned test host.

enum SyncCloudKit {

    static let schemaVersionKey = "schemaVersion"

    /// The `CKRecord` to save. It starts from the stored system fields when there are any,
    /// so it carries the server's change tag, and it sets only the fields in `record`:
    /// a field a newer Luna added stays on the server untouched.
    static func record(from record: SyncRecord) -> CKRecord {
        let zoneID = CKRecordZone.ID(zoneName: record.zone, ownerName: CKCurrentUserDefaultName)
        let ckRecord = record.systemFields.flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: record.recordType, recordID: CKRecord.ID(recordName: record.recordName, zoneID: zoneID))
        ckRecord[schemaVersionKey] = NSNumber(value: record.schemaVersion)
        for (key, field) in record.fields {
            let object = field.value.map(objectValue)
            if field.isEncrypted {
                ckRecord.encryptedValues[key] = object
            } else {
                ckRecord[key] = object
            }
        }
        return ckRecord
    }

    /// Fields of a type outside `SyncValue` (assets, locations, lists) are dropped: the
    /// schema uses none, and a reader ignores what it does not know.
    static func syncRecord(from ckRecord: CKRecord) -> SyncRecord {
        var fields: [String: SyncField] = [:]
        var schemaVersion: Int64 = 0
        let encrypted = Set(ckRecord.encryptedValues.allKeys())
        for key in encrypted {
            if let value = ckRecord.encryptedValues[key].flatMap(syncValue) {
                fields[key] = SyncField(value, encrypted: true)
            }
        }
        for key in ckRecord.allKeys() where !encrypted.contains(key) {
            guard let value = ckRecord[key].flatMap(syncValue) else { continue }
            if key == schemaVersionKey, case .int(let version) = value {
                schemaVersion = version
            } else {
                fields[key] = SyncField(value)
            }
        }
        return SyncRecord(
            recordType: ckRecord.recordType,
            recordName: ckRecord.recordID.recordName,
            zone: ckRecord.recordID.zoneID.zoneName,
            schemaVersion: schemaVersion,
            fields: fields,
            systemFields: systemFields(of: ckRecord)
        )
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// The server's copy from a `serverRecordChanged` failure: the one a merge goes into,
    /// because only it carries the current change tag.
    static func serverRecord(in error: Error) -> SyncRecord? {
        guard let error = error as? CKError, error.code == .serverRecordChanged,
              let server = error.serverRecord else { return nil }
        return syncRecord(from: server)
    }

    private static func objectValue(_ value: SyncValue) -> any CKRecordValue {
        switch value {
        case .string(let string): string as NSString
        case .int(let int): NSNumber(value: int)
        case .double(let double): NSNumber(value: double)
        case .date(let date): date as NSDate
        case .bytes(let data): data as NSData
        }
    }

    private static func syncValue(_ object: any __CKRecordObjCValue) -> SyncValue? {
        switch object {
        case let string as String: return .string(string)
        case let date as Date: return .date(date)
        case let data as Data: return .bytes(data)
        case let number as NSNumber:
            // `objCType` is the only thing that tells an INT64 field from a DOUBLE one.
            let type = String(cString: number.objCType)
            return type == "d" || type == "f" ? .double(number.doubleValue) : .int(number.int64Value)
        default: return nil
        }
    }
}

extension SyncRecord {
    init(_ record: CKRecord) {
        self = SyncCloudKit.syncRecord(from: record)
    }
}

// MARK: The live engine

extension SyncCloudKit {

    /// A `CKError` as the coordinator acts on it. A conflict without the server's record
    /// cannot be merged, so it is `other`, and the engine retries it.
    static func syncError(_ error: any Error) -> SyncError {
        guard let error = error as? CKError else { return .other }
        switch error.code {
        case .serverRecordChanged: return serverRecord(in: error).map(SyncError.serverRecordChanged) ?? .other
        case .unknownItem: return .unknownItem
        case .zoneNotFound: return .zoneNotFound
        case .quotaExceeded: return .quotaExceeded
        case .networkUnavailable, .networkFailure: return .networkUnavailable
        case .notAuthenticated: return .notAuthenticated
        case .accountTemporarilyUnavailable: return .temporarilyUnavailable
        default: return .other
        }
    }

    static func zoneID(_ zone: SyncZone) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.rawValue, ownerName: CKCurrentUserDefaultName)
    }

    static func pendingChange(_ change: SyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        let id = CKRecord.ID(recordName: change.recordName, zoneID: zoneID(change.zone))
        return change.isDelete ? .deleteRecord(id) : .saveRecord(id)
    }

    /// Nil for a zone this Luna does not know.
    static func pendingChange(_ change: CKSyncEngine.PendingRecordZoneChange) -> SyncPendingChange? {
        switch change {
        case .saveRecord(let id): SyncZone(rawValue: id.zoneID.zoneName).map { .save(id.recordName, in: $0) }
        case .deleteRecord(let id): SyncZone(rawValue: id.zoneID.zoneName).map { .delete(id.recordName, in: $0) }
        @unknown default: nil
        }
    }
}

/// One record of each of Luna's eight types, built by the real mappers with every field
/// they write filled in, for `Luna --cloudkit-probe-records`. Production has no
/// just-in-time schema, so saving these is what proves the deployed schema takes every
/// field sync sends.
public enum SyncProbe {

    public static func records(inZone zoneName: String) -> [CKRecord] {
        let now = Date()
        let secret = SyncSecret.generate()
        let space = Space(name: "Probe", symbolName: "moon", gradient: .defaultSpace, imageData: Data([0x89, 0x50]), order: 1)
        let group = TabGroup(spaceID: space.id, name: "Probe", symbolName: "folder", kind: .pinned, order: 1)
        let url = URL(string: "https://example.com/")!
        let tab = Tab(
            spaceID: space.id, kind: .pinned, url: url, title: "Probe", createdAt: now, archivedAt: now, order: 1,
            pinnedURL: url, customTitle: "Probe", customSymbolName: "star", groupID: group.id
        )
        let site = SyncSiteSetting(
            host: "example.com", automaticPictureInPicture: true, localNetwork: false, savePasswords: true,
            popups: false, blockingDisabled: true, insecureAllowed: false
        )
        let visit = SyncHistoryEntry.Visit(spaceID: space.id, at: now, kind: "typed")
        let device = SyncDevice(id: UUID(), name: "Probe", tabs: [SyncDevice.OpenTab(spaceID: space.id, url: url, title: "Probe")])
        let records = [
            SyncMapping.record(for: space, modifiedAt: now, stored: nil),
            SyncMapping.record(for: group, modifiedAt: now, stored: nil),
            SyncMapping.record(for: tab, modifiedAt: now, stored: nil),
            SyncMapping.record(for: site, secret: secret, modifiedAt: now, stored: nil),
            SyncMapping.record(for: SyncSetting(key: "search.engine", value: Data("<plist/>".utf8)), modifiedAt: now, stored: nil),
            SyncMapping.record(
                for: SyncHistoryEntry(deviceID: device.id, placeID: 1, url: url, title: "Probe", visits: [visit]),
                modifiedAt: now, stored: nil
            ),
            SyncMapping.record(for: device, modifiedAt: now, stored: nil),
            secret.record(stored: nil)
        ]
        return records.map { record in
            var record = record
            record.zone = zoneName
            return SyncCloudKit.record(from: record)
        }
    }
}

/// `CKSyncEngine` over the private database, behind `SyncEngineControl`, with each of its
/// events handed to the coordinator as plain values. Constructing one without the iCloud
/// entitlement crashes, so only the app, past its entitlement gate, makes one; tests use
/// `FakeSyncEngine`, and `Luna --cloudkit-probe` is what exercises CloudKit itself.
public final class SyncCloudKitEngine: SyncEngineControl, CKSyncEngineDelegate, @unchecked Sendable {

    // Unchecked: `engine` is set once, at the end of init, before anything can reach it.
    private var engine: CKSyncEngine!
    /// Strong, and a cycle while sync is on: the coordinator drops this engine when sync
    /// turns off, which ends it. `CKSyncEngine` holds its delegate weakly.
    private let coordinator: SyncCoordinator

    public init(containerIdentifier: String, state: Data?, coordinator: SyncCoordinator) {
        self.coordinator = coordinator
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        // State this Luna cannot read starts a fresh engine, which fetches everything.
        let serialization = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: self))
    }

    // MARK: SyncEngineControl

    public func add(pending: [SyncPendingChange]) async {
        engine.state.add(pendingRecordZoneChanges: pending.map(SyncCloudKit.pendingChange))
    }

    public func remove(pending: [SyncPendingChange]) async {
        engine.state.remove(pendingRecordZoneChanges: pending.map(SyncCloudKit.pendingChange))
    }

    public func addZoneSaves(_ zones: [SyncZone]) async {
        engine.state.add(pendingDatabaseChanges: zones.map { .saveZone(CKRecordZone(zoneID: SyncCloudKit.zoneID($0))) })
    }

    public func addZoneDeletes(_ zones: [SyncZone]) async {
        engine.state.add(pendingDatabaseChanges: zones.map { .deleteZone(SyncCloudKit.zoneID($0)) })
    }

    /// A failure also reaches the status line; the engine retries on its own.
    public func fetchChanges() async throws {
        do { try await engine.fetchChanges() } catch {
            await coordinator.failed(SyncCloudKit.syncError(error))
            throw error
        }
    }

    public func sendChanges() async throws {
        do { try await engine.sendChanges() } catch {
            await coordinator.failed(SyncCloudKit.syncError(error))
            throw error
        }
    }

    // MARK: CKSyncEngineDelegate

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let coordinator = coordinator
        // A save the coordinator can no longer build comes back nil, and `records(for:)`
        // has already taken it out of the pending changes.
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let change = SyncCloudKit.pendingChange(.saveRecord(id)),
                  let record = try? await coordinator.records(for: [change]).first else { return nil }
            return SyncCloudKit.record(from: record)
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // A store error is dropped: the engine's state has not moved past a change the
        // store failed to take, so the next fetch or send brings it again.
        try? await handle(event)
    }

    private func handle(_ event: CKSyncEngine.Event) async throws {
        switch event {
        case .stateUpdate(let update):
            try await coordinator.stateUpdated(JSONEncoder().encode(update.stateSerialization))
        case .accountChange(let change):
            try await accountChanged(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            try await zonesDeleted(changes.deletions)
        case .fetchedRecordZoneChanges(let changes):
            try await coordinator.fetched(
                modifications: changes.modifications.map { SyncRecord($0.record) },
                deletions: changes.deletions.map {
                    SyncDeletion(recordType: $0.recordType, recordName: $0.recordID.recordName, zone: $0.recordID.zoneID.zoneName)
                }
            )
        case .sentRecordZoneChanges(let sent):
            try await sentRecords(sent)
        case .sentDatabaseChanges(let sent):
            await report(sent.failedZoneSaves.map(\.error))
        case .didFetchRecordZoneChanges(let done):
            await report(done.error.map { [$0] } ?? [])
        case .didFetchChanges:
            try await coordinator.fetchFinished()
        default:
            break
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async throws {
        switch change {
        case .signIn(let user): try await coordinator.accountChanged(.signIn(userRecordName: user.recordName))
        case .signOut: try await coordinator.accountChanged(.signOut)
        case .switchAccounts: try await coordinator.accountChanged(.switchAccounts)
        @unknown default: break
        }
    }

    private func zonesDeleted(_ deletions: [CKDatabase.DatabaseChange.Deletion]) async throws {
        let byReason = Dictionary(grouping: deletions) { deletion -> SyncZoneDeletionReason in
            switch deletion.reason {
            case .purged: .purged
            case .encryptedDataReset: .encryptedDataReset
            default: .deleted
            }
        }
        for (reason, deletions) in byReason {
            let zones = deletions.compactMap { SyncZone(rawValue: $0.zoneID.zoneName) }
            if !zones.isEmpty { try await coordinator.zonesDeleted(zones, reason: reason) }
        }
    }

    /// A delete of a record that is already gone is done, not failed.
    private func sentRecords(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async throws {
        let goneAlready = sent.failedRecordDeletes.filter { $0.value.code == .unknownItem }.map(\.key.recordName)
        try await coordinator.sent(
            saved: sent.savedRecords.map { SyncRecord($0) },
            deleted: sent.deletedRecordIDs.map(\.recordName) + goneAlready,
            failed: sent.failedRecordSaves.map { SyncSaveFailure(record: SyncRecord($0.record), error: SyncCloudKit.syncError($0.error)) }
        )
        await report(sent.failedRecordDeletes.values.filter { $0.code != .unknownItem })
    }

    private func report(_ errors: [CKError]) async {
        for error in errors { await coordinator.failed(SyncCloudKit.syncError(error)) }
    }
}
