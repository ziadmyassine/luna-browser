import Foundation
import GRDB

// §3.4b's groups, on disk. A separate file for the reason `BrowserStore+Favorites` is
// one: it is a whole noun with its own rules, and `BrowserStore.swift` is already the
// longest thing in the module.
//
// Three reads and three writes, and nothing clever. What ordering means — that a group
// and a loose tab share one run of indices inside a section — is `TabList`'s, so that
// "which slot does this drop mean" has exactly one answer and can be tested without a
// database.
public extension BrowserStore {

    /// Every group in a Space, in display order, with `order` renumbered to `0..<n` when
    /// it has drifted — the same self-heal `spaces()` does, for the same reason.
    ///
    /// It cannot renumber against the loose tabs those indices are shared with, and must
    /// not try: the two are interleaved, so `0..<n` over the groups alone would close the
    /// gaps the tabs are standing in. This only breaks ties, and `TabList` renumbers both
    /// together the first time either moves.
    ///
    /// Ties break on name, so two groups sharing an `order` come back the same way on
    /// every launch instead of swapping places.
    func groups(inSpace spaceID: UUID) async throws -> [TabGroup] {
        try await pool.read { db in
            try TabGroup.fetchAll(
                db,
                sql: #"SELECT * FROM tabGroups WHERE spaceID = ? ORDER BY "order", name"#,
                arguments: [spaceID]
            )
        }
        // The read-side half of the grid guard — see `TabGroup.sanitisingKind()`.
        .map { $0.sanitisingKind() }
    }

    /// Persists a group, with §3.3's grid ruled out of `kind`.
    ///
    /// The write side of the guard, paired with the repair in `groups(inSpace:)`. A group
    /// cannot be a tile: the grid draws one icon per tab and a group is a list of them, so
    /// a `.essential` group would be a row nothing in the sidebar knows how to put
    /// anywhere. Repaired rather than refused, because the nearest true thing — the
    /// ordinary section — loses the user nothing, and throwing here would lose the group.
    func upsert(_ group: TabGroup) async throws {
        let sanitised = group.sanitisingKind()
        try await pool.write { db in try sanitised.upsert(db) }
    }

    /// Removes the group. Its tabs stay: `groupID` is `ON DELETE SET NULL`, so they come
    /// back loose in the section they were already in (schema `v6`).
    func delete(groupID: UUID) async throws {
        _ = try await pool.write { db in
            try TabGroup.deleteOne(db, key: groupID)
        }
    }
}
