@testable import BrowserKit
import Foundation
import Synchronization

/// `SyncEngineControl` without CloudKit: it records what the coordinator asked for, and
/// the tests play the engine's part by calling the coordinator's event methods.
final class FakeSyncEngine: SyncEngineControl {

    struct Calls {
        /// Every engine the factory made, with the state it was started from.
        var startedWith: [Data?] = []
        var pending: [SyncPendingChange] = []
        var zoneSaves: [SyncZone] = []
        var zoneDeletes: [SyncZone] = []
        var fetches = 0
        var sends = 0
    }

    let calls = Mutex(Calls())

    var pending: [SyncPendingChange] { calls.withLock { $0.pending } }
    var zoneSaves: [SyncZone] { calls.withLock { $0.zoneSaves } }
    var zoneDeletes: [SyncZone] { calls.withLock { $0.zoneDeletes } }
    var startedWith: [Data?] { calls.withLock { $0.startedWith } }

    /// The coordinator's `makeEngine`: every start hands back this same fake.
    var factory: @Sendable (SyncCoordinator, Data?) -> any SyncEngineControl {
        { [self] _, state in
            calls.withLock { $0.startedWith.append(state) }
            return self
        }
    }

    func add(pending changes: [SyncPendingChange]) async {
        calls.withLock { calls in
            // A set, as `CKSyncEngine.State` keeps it.
            for change in changes where !calls.pending.contains(change) { calls.pending.append(change) }
        }
    }

    func remove(pending changes: [SyncPendingChange]) async {
        calls.withLock { $0.pending.removeAll(where: changes.contains) }
    }

    func addZoneSaves(_ zones: [SyncZone]) async {
        calls.withLock { $0.zoneSaves += zones }
    }

    func addZoneDeletes(_ zones: [SyncZone]) async {
        calls.withLock { $0.zoneDeletes += zones }
    }

    func fetchChanges() async throws {
        calls.withLock { $0.fetches += 1 }
    }

    func sendChanges() async throws {
        calls.withLock { $0.sends += 1 }
    }

    /// What `CKSyncEngine` does with a batch it sent: the pending changes go.
    func sent(_ records: [SyncRecord]) {
        calls.withLock { calls in
            calls.pending.removeAll { change in records.contains { $0.recordName == change.recordName } }
        }
    }
}
