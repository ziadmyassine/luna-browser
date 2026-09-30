import Foundation

// The seam between `SyncCoordinator` and `CKSyncEngine` (docs/plans/SYNC-PLAN.md §1, The seam),
// and the plain values the engine's events are translated into. Constructing a
// `CKSyncEngine` without the iCloud entitlement crashes, so tests and CI drive the
// coordinator through `FakeSyncEngine` instead.

/// A record the engine is to save or delete on its next send.
public struct SyncPendingChange: Sendable, Hashable {
    public var isDelete: Bool
    public var recordName: String
    public var zone: SyncZone

    public static func save(_ recordName: String, in zone: SyncZone) -> Self {
        Self(isDelete: false, recordName: recordName, zone: zone)
    }

    public static func delete(_ recordName: String, in zone: SyncZone) -> Self {
        Self(isDelete: true, recordName: recordName, zone: zone)
    }
}

/// What the coordinator asks of the engine: the calls `CKSyncEngine` and its `state` take.
public protocol SyncEngineControl: Sendable {
    func add(pending: [SyncPendingChange]) async
    /// A change whose record can no longer be built; `CKSyncEngine` would otherwise ask again.
    func remove(pending: [SyncPendingChange]) async
    func addZoneSaves(_ zones: [SyncZone]) async
    func addZoneDeletes(_ zones: [SyncZone]) async
    func fetchChanges() async throws
    func sendChanges() async throws
}

/// The `CKError` codes the coordinator acts on.
public enum SyncError: Sendable, Equatable {
    /// Carries the server's record, with its current system fields.
    case serverRecordChanged(SyncRecord)
    case unknownItem
    case zoneNotFound
    case quotaExceeded
    case networkUnavailable
    case notAuthenticated
    case temporarilyUnavailable
    /// Anything else. The engine retries what it can.
    case other
}

public struct SyncSaveFailure: Sendable, Equatable {
    /// The record as it was sent.
    public var record: SyncRecord
    public var error: SyncError

    public init(record: SyncRecord, error: SyncError) {
        self.record = record
        self.error = error
    }
}

/// `CKSyncEngine.Event.AccountChange`.
public enum SyncAccountChange: Sendable, Equatable {
    case signIn(userRecordName: String)
    case signOut
    case switchAccounts
}

/// `CKDatabase.DatabaseChange.Deletion.Reason`.
public enum SyncZoneDeletionReason: Sendable, Equatable {
    /// Deleted by a Mac on this account: Remove Luna Data from iCloud.
    case deleted
    /// The user deleted Luna's data in iCloud settings.
    case purged
    /// The account's encryption keys were reset, and every encrypted value with them.
    case encryptedDataReset
}
