import Foundation
import GRDB
import os

// Profile rows: reading them safely, and deleting them at all (§3.1, §6.3).
//
// Two jobs live here, and they are the same job seen from either end of the
// `profiles.dataStoreIdentifier` column:
//
//   · **Read.** The column is `NOT NULL UNIQUE` with no value check. The one value it must
//     never hold is the all-zero UUID, because `WKWebsiteDataStore(forIdentifier:)` answers
//     that with an Objective-C exception Swift cannot catch — an uncatchable crash, not an
//     error any call site can handle. None of the five codebases researched for the spec
//     guards this. Luna guards it here, at the GRDB boundary, because this is the last place
//     a bad value is still data.
//
//   · **Delete.** `BrowserStore` had no `delete(profileID:)` at all, so a Space delete that
//     removed the cookie jar still left the profile row behind — an orphan naming a store
//     that no longer exists, for as long as the database does.

private let log = Logger(subsystem: "dk.trego.Luna", category: "store.profiles")

public extension BrowserStore {

    /// Every profile, by name, with any unusable `dataStoreIdentifier` repaired in place.
    ///
    /// A zero identifier is rewritten with a freshly minted one and persisted before it is
    /// returned, so the value never reaches WebKit and never comes back on the next launch.
    /// See ``Profile/repairingDataStoreIdentifier()`` for why minting is safe: a zero
    /// identifier addresses no store on disk, because nothing could ever have created one
    /// under it. The profile's `id` — the identity every `Space` references — is untouched.
    func profiles() async throws -> [Profile] {
        let persisted = try await pool.read { db in
            try Profile.fetchAll(db, sql: "SELECT * FROM profiles ORDER BY name")
        }
        return try await repairingUnusableIdentifiers(in: persisted)
    }

    /// One profile by id, with the same read-boundary guard as ``profiles()``.
    func profile(_ id: UUID) async throws -> Profile? {
        let persisted = try await pool.read { db in try Profile.fetchOne(db, key: id) }
        guard let persisted else { return nil }
        return try await repairingUnusableIdentifiers(in: [persisted]).first
    }

    /// Deletes a profile row.
    ///
    /// - Throws: ``BrowserStoreError/profileInUse(profileID:spaceIDs:)`` while any Space
    ///   still names it. Many Spaces may share one profile (§1), so "the Space that owned
    ///   it is gone" is not the same question as "anything still needs it", and only the
    ///   database can answer the second one.
    ///
    /// This deletes the **row**, not the cookie jar. The store on disk is
    /// `ProfileStore.remove(_:)`'s job and is deliberately a separate step: WebKit is the
    /// registry for what exists on disk (§3.1), so a row deleted without its store is
    /// recoverable by the next launch's orphan sweep, while a store deleted without its row
    /// is simply gone. Row last is the order that cannot lose data.
    func delete(profileID: UUID) async throws {
        try await pool.write { db in
            let spaceIDs = try UUID.fetchAll(
                db,
                sql: "SELECT id FROM spaces WHERE profileID = ?",
                arguments: [profileID]
            )
            guard spaceIDs.isEmpty else {
                throw BrowserStoreError.profileInUse(profileID: profileID, spaceIDs: spaceIDs)
            }
            _ = try Profile.deleteOne(db, key: profileID)
        }
    }

    /// Which Spaces name this profile. §6.4's dialog needs the count; a delete needs the fact.
    func spaceIDs(onProfile profileID: UUID) async throws -> [UUID] {
        try await pool.read { db in
            try UUID.fetchAll(
                db,
                sql: #"SELECT id FROM spaces WHERE profileID = ? ORDER BY "order", name"#,
                arguments: [profileID]
            )
        }
    }

    /// The live `dataStoreIdentifier` set, for `ProfileStore.sweepOrphans(keeping:)`.
    ///
    /// Reads through ``profiles()`` so a repaired identifier counts as live: sweeping against
    /// the raw column would treat a just-repaired profile's new store as an orphan.
    func liveDataStoreIdentifiers() async throws -> Set<UUID> {
        Set(try await profiles().map(\.dataStoreIdentifier))
    }

    // MARK: - The read-boundary guard

    private func repairingUnusableIdentifiers(in persisted: [Profile]) async throws -> [Profile] {
        guard persisted.contains(where: { !$0.hasUsableDataStoreIdentifier }) else { return persisted }

        let repaired = persisted.map { $0.repairingDataStoreIdentifier() }
        let changed = repaired.filter { profile in
            persisted.contains { $0.id == profile.id && $0.dataStoreIdentifier != profile.dataStoreIdentifier }
        }
        for profile in changed {
            log.error(
                """
                Profile \(profile.id.uuidString, privacy: .public) had the all-zero dataStoreIdentifier, \
                which WKWebsiteDataStore rejects with an uncatchable Objective-C exception. Minted \
                \(profile.dataStoreIdentifier.uuidString, privacy: .public); its site data starts empty.
                """
            )
        }
        try await pool.write { db in
            for profile in changed { try profile.update(db) }
        }
        return repaired
    }
}

// MARK: - Test seams
//
// Internal, reachable only through `@testable import`. Both exist because the guards above
// are guards: a corrupt row and a drifted order cannot be produced through the public API,
// which is the point of the public API, so proving they are repaired needs a way in behind it.

extension BrowserStore {

    /// Writes a profile row **without** the all-zero `dataStoreIdentifier` guard, the way a
    /// bad migration or a hand-edited database would.
    func insertUnvalidated(_ profile: Profile) async throws {
        try await pool.write { db in try profile.upsert(db) }
    }

    /// The `order` column as it is actually stored, bypassing ``spaces()``'s renumbering.
    func persistedSpaceOrders() async throws -> [Int] {
        try await pool.read { db in
            try Int.fetchAll(db, sql: #"SELECT "order" FROM spaces ORDER BY "order", name"#)
        }
    }
}
