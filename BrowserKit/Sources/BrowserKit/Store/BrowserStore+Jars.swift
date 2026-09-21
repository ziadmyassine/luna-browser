import Foundation
import GRDB
import os

// The `spaces.dataStoreIdentifier` column, read safely (§3.1).
//
// The column is `NOT NULL UNIQUE` with no value check. The one value it must never hold
// is the all-zero UUID, because `WKWebsiteDataStore(forIdentifier:)` answers that with an
// Objective-C exception Swift cannot catch — an uncatchable crash rather than an error any
// call site can handle. None of the five codebases researched for the spec guards it. Luna
// guards it at the GRDB boundary, the last place a bad value is still data.
//
// It sat on a `profiles` row until `v7`, when the Profile concept went and every Space
// took its own jar. The guard came with it unchanged; only what it is written on moved.

private let log = Logger(subsystem: "dk.trego.Luna", category: "store.jars")

public extension BrowserStore {

    /// The live `dataStoreIdentifier` set, for `ProfileStore.sweepOrphans(keeping:)`.
    ///
    /// Reads through ``spaces()`` so a repaired identifier counts as live: sweeping against
    /// the raw column would treat a just-repaired Space's new store as an orphan.
    func liveDataStoreIdentifiers() async throws -> Set<UUID> {
        Set(try await spaces().map(\.dataStoreIdentifier))
    }
}

extension BrowserStore {

    /// Rewrites any unusable `dataStoreIdentifier` with a freshly minted one and persists
    /// it before returning, so the value never reaches WebKit and never comes back on the
    /// next launch.
    ///
    /// See ``Space/repairingDataStoreIdentifier()`` for why minting is safe: a zero
    /// identifier addresses no store on disk, because nothing could ever have created one
    /// under it. The Space's `id` — the identity every tab references — is untouched.
    func repairingUnusableIdentifiers(in persisted: [Space]) async throws -> [Space] {
        guard persisted.contains(where: { !$0.hasUsableDataStoreIdentifier }) else { return persisted }

        let repaired = persisted.map { $0.repairingDataStoreIdentifier() }
        let changed = repaired.filter { space in
            persisted.contains { $0.id == space.id && $0.dataStoreIdentifier != space.dataStoreIdentifier }
        }
        for space in changed {
            log.error(
                """
                Space \(space.id.uuidString, privacy: .public) had the all-zero dataStoreIdentifier, \
                which WKWebsiteDataStore rejects with an uncatchable Objective-C exception. Minted \
                \(space.dataStoreIdentifier.uuidString, privacy: .public); its site data starts empty.
                """
            )
        }
        try await pool.write { db in
            for space in changed { try space.update(db) }
        }
        return repaired
    }

    // MARK: - Test seams
    //
    // Internal, reachable only through `@testable import`. Both exist because the guards
    // above are guards: a corrupt row and a drifted order cannot be produced through the
    // public API, which is the point of the public API, so proving they are repaired needs
    // a way in behind it.

    /// Writes a Space without the all-zero `dataStoreIdentifier` guard, the way a bad
    /// migration or a hand-edited database would.
    func insertUnvalidated(_ space: Space) async throws {
        try await pool.write { db in try space.upsert(db) }
    }

    /// The `order` column as it is actually stored, bypassing ``spaces()``'s renumbering.
    func persistedSpaceOrders() async throws -> [Int] {
        try await pool.read { db in
            try Int.fetchAll(db, sql: #"SELECT "order" FROM spaces ORDER BY "order", name"#)
        }
    }
}

// MARK: - The `v7` seam

extension BrowserStore {

    /// A database in the shape it had before `v7`, with `spaceNames.count` Spaces sharing
    /// one profile, ready for `BrowserStore(path:)` to migrate.
    ///
    /// Built by running the real migration chain up to `v6` rather than by hand-writing the
    /// old DDL, so what `v7` is tested against is the shape it will actually meet on
    /// somebody's Mac. The one migration in Luna's history that can cost a user a login is
    /// worth a test that starts from the truth.
    ///
    /// - Returns: the profile's `dataStoreIdentifier` — the jar exactly one of those Spaces
    ///   is entitled to keep.
    static func seedingALegacySharedProfile(
        at path: URL,
        spaceNames: [String],
        favoritesPerSpace: Int = 0
    ) throws -> UUID {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: path.path)
        try Schema.migrator().migrate(queue, upTo: "v6")

        let profileID = UUID()
        let jar = UUID()
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO profiles (id, name, dataStoreIdentifier) VALUES (?, ?, ?)",
                arguments: [profileID, "Shared", jar]
            )
            let gradient = try String(data: JSONEncoder().encode(GradientPair.defaultSpace), encoding: .utf8)
            for (order, name) in spaceNames.enumerated() {
                let spaceID = UUID()
                try db.execute(
                    sql: #"""
                    INSERT INTO spaces (id, name, symbolName, gradient, profileID, "order")
                    VALUES (?, ?, ?, ?, ?, ?)
                    """#,
                    arguments: [UUID(uuidString: spaceID.uuidString), name, "moon.stars.fill", gradient, profileID, order]
                )
                // Favorites as `v2` left them: scoped by `profileID`, homed by `spaceID`.
                for tile in 0..<favoritesPerSpace {
                    try db.execute(
                        sql: #"""
                        INSERT INTO tabs (id, spaceID, kind, url, title, createdAt, lastActiveAt, "order", hasUnread, profileID)
                        VALUES (?, ?, 'essential', ?, ?, ?, ?, ?, 0, ?)
                        """#,
                        arguments: [
                            UUID(), spaceID, "https://tile\(tile).\(name).example", "\(name) \(tile)",
                            Date(), Date(), tile, profileID
                        ]
                    )
                }
            }
        }
        return jar
    }

    /// The live schema's own answer to "is the Profile row gone", for the test that asks.
    func tableNames() async throws -> Set<String> {
        try await pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    func spaceColumnNames() async throws -> [String] {
        try await pool.read { db in try db.columns(in: "spaces").map(\.name) }
    }
}
