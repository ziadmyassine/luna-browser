//
//  BrowserSession+Sync.swift
//  Luna
//
//  Changes from other Macs, applied to the running session (docs/SYNC-PLAN.md
//  S10). In the app this is the coordinator's `applyInbound`: the session writes
//  its whole in-memory row back on every change, so a change that reached only
//  the database would be overwritten by the next local write.
//

import BrowserKit
import Foundation

extension BrowserSession {

    /// Applies a fetched batch on the write chain, behind every local write
    /// already queued, then takes the Spaces and tabs back from the store.
    func applyRemote(_ changes: SyncChangeSet, isFirstFetch: Bool = false) async throws {
        let (incoming, sendBack) = laidOverThisMac(changes)
        var (snapshot, overtaken) = try await onWriteChain { store in
            try await store.applyRemote(incoming, isFirstFetch: isFirstFetch)
            // An ordinary write, so the triggers send the answer back up.
            for tab in sendBack { try await store.upsert(tab) }
            let snapshot = try await SyncSnapshot(store)
            // Every Mac demotes the same Favorites (`demotingExtraFavorites`), so
            // the demotion goes in as a remote change and is not sent back.
            let demoted = SyncMerge.demotingExtraFavorites(in: snapshot.tabs)
            guard !demoted.isEmpty else { return snapshot }
            try await store.applyRemote(SyncChangeSet(
                modifications: demoted.map { SyncMapping.record(for: $0, modifiedAt: Date(), stored: nil) }
            ))
            return try await SyncSnapshot(store)
        }
        // A local change queued meanwhile is in memory but not in what was read.
        while overtaken { (snapshot, overtaken) = try await onWriteChain(SyncSnapshot.init) }
        await adopt(snapshot)
    }

    /// The §3 tab rules only this Mac can apply, since only it knows which tabs
    /// have a page: a live tab keeps its URL and title, and a remote archive
    /// loses to later activity here. `sendBack` is written after the batch as a
    /// local change.
    private func laidOverThisMac(_ changes: SyncChangeSet) -> (SyncChangeSet, sendBack: [Tab]) {
        var changes = changes
        var sendBack: [Tab] = []
        for (index, record) in changes.modifications.enumerated() {
            guard let remote = SyncMapping.tab(from: record),
                  let local = list.tab(remote.id) ?? archived.first(where: { $0.id == remote.id }) else { continue }
            let (tab, isSentBack) = SyncMerge.incoming(remote, over: local, isLive: controllers[remote.id] != nil)
            if isSentBack {
                sendBack.append(tab)
                continue
            }
            var merged = SyncMapping.record(for: tab, modifiedAt: Date(), stored: record)
            merged.fields["modifiedAt"] = record.fields["modifiedAt"]
            changes.modifications[index] = merged
        }
        return (changes, sendBack)
    }

    /// Takes the store's rows as they now stand. A Space another Mac deleted
    /// goes the way `deleteSpace` takes one, less the undo and the evacuation:
    /// its tabs already moved on that Mac, and arrive as tab changes.
    private func adopt(_ snapshot: SyncSnapshot) async {
        let kept = Set(snapshot.spaces.map(\.id))
        let gone = spaces.filter { !kept.contains($0.id) }
        spaces = snapshot.spaces
        list = TabList(
            Dictionary(grouping: snapshot.tabs.filter { $0.archivedAt == nil }, by: \.spaceID)
                .merging(kept.map { ($0, []) }) { tabs, _ in tabs },
            groups: snapshot.groups
        )
        archived = snapshot.tabs.filter { $0.archivedAt != nil }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        for id in Array(controllers.keys) where list.tab(id) == nil { forget(id) }
        for (spaceID, tabID) in windowFocus.values.flatMap(\.tabBySpace) where list.tab(tabID) == nil {
            releaseTab(tabID, inSpace: spaceID) { nil }
        }
        for space in gone { releaseSpace(space.id, to: spaces.first?.id) }
        notifyChange()
        for space in gone { try? await discardJar(of: space) }
    }

    /// `enqueue`, for work with an answer. `overtaken` says whether another write
    /// joined the chain while this one ran.
    private func onWriteChain<T: Sendable>(
        _ work: @escaping @Sendable (BrowserStore) async throws -> T
    ) async throws -> (T, overtaken: Bool) {
        let previous = writeChain
        let store = store
        let task = Task {
            await previous?.value
            return try await work(store)
        }
        let link = Task { _ = await task.result }
        writeChain = link
        let value = try await task.value
        return (value, writeChain != link)
    }
}

/// Every Space, tab and group in the store, read in one turn of the write chain.
struct SyncSnapshot: Sendable {
    var spaces: [Space]
    var tabs: [Tab] = []
    var groups: [UUID: [TabGroup]] = [:]

    init(_ store: BrowserStore) async throws {
        // Another Mac deleted every Space this one had; a window needs one to stand in.
        try await store.seedIfEmpty()
        spaces = try await store.spaces()
        for space in spaces {
            tabs += try await store.tabs(inSpace: space.id, includeArchived: true)
            groups[space.id] = try await store.groups(inSpace: space.id)
        }
    }
}
