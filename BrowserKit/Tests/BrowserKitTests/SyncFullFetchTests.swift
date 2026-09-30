@testable import BrowserKit
import Foundation
import GRDB
import Synchronization
import Testing

/// The turn-on fetch's last rule (docs/plans/SYNC-PLAN.md §3, "Turning sync on"): a row whose
/// system fields prove iCloud once had it, and which a fresh full fetch did not bring back,
/// was deleted on another Mac while this one was off.
@Suite("Sync full fetch (§31)")
struct SyncFullFetchTests {

    private final class Inbound: Sendable {
        let sets = Mutex<[SyncChangeSet]>([])
    }

    private let engine = FakeSyncEngine()
    private let inbound = Inbound()
    private let store: BrowserStore

    init() throws {
        store = try makeTemporaryStore()
    }

    /// Two Spaces that both reached iCloud, then sync off: the system fields stay.
    private func syncedThenOff() async throws -> (SyncCoordinator, kept: Space, gone: Space) {
        let kept = Space(name: "Kept", symbolName: "a", gradient: .defaultSpace)
        let gone = Space(name: "Gone", symbolName: "b", gradient: .defaultSpace)
        try await store.upsert(kept)
        try await store.upsert(gone)
        let sync = SyncCoordinator(store: store, makeEngine: engine.factory, applyInbound: { [inbound, store] changes, first in
            inbound.sets.withLock { $0.append(changes) }
            try await store.applyRemote(changes, isFirstFetch: first)
        })
        try await sync.enable(zones: [.spaces])
        let saved = try await sync.records(for: engine.pending).map { record in
            var record = record
            record.systemFields = Data([1])
            return record
        }
        try await sync.sent(saved: saved)
        try await sync.fetchFinished()
        try await sync.disable()
        return (sync, kept, gone)
    }

    private func fetchedRecord(_ space: Space) -> SyncRecord {
        var record = SyncMapping.record(for: space, modifiedAt: Date(), stored: nil)
        record.systemFields = Data([2])
        return record
    }

    @Test func aSyncedRowMissingFromTheFullFetchIsDeletedLocally() async throws {
        let (sync, kept, gone) = try await syncedThenOff()

        try await sync.enable(zones: [.spaces])
        try await sync.fetched(modifications: [fetchedRecord(kept)], deletions: [])
        try await sync.fetchFinished()

        #expect(try await store.spaces().map(\.id) == [kept.id])
        #expect(try await store.storedRecord(named: gone.id.uuidString) == nil)
        let deletions = inbound.sets.withLock { $0.flatMap(\.deletions) }
        #expect(deletions.map(\.recordName) == [gone.id.uuidString], "it goes through applyInbound, so the session sees it")
    }

    @Test func aFetchResumedFromSavedStateIsNotFull() async throws {
        let (sync, kept, _) = try await syncedThenOff()
        try await sync.enable(zones: [.spaces])
        // A relaunch part-way through: the engine resumes from its state and delivers the rest.
        try await sync.stateUpdated(Data([9]))
        let relaunched = SyncCoordinator(store: store, makeEngine: engine.factory)
        try await relaunched.start()

        try await relaunched.fetched(modifications: [fetchedRecord(kept)], deletions: [])
        try await relaunched.fetchFinished()

        #expect(try await store.spaces().count == 2)
    }

    @Test func laterFetchesAreChangesOnly() async throws {
        let (sync, kept, gone) = try await syncedThenOff()
        try await sync.enable(zones: [.spaces])
        try await sync.fetched(modifications: [fetchedRecord(kept), fetchedRecord(gone)], deletions: [])
        try await sync.fetchFinished()

        try await sync.fetched(modifications: [fetchedRecord(kept)], deletions: [])
        try await sync.fetchFinished()

        #expect(try await store.spaces().count == 2)
    }
}
