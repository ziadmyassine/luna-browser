@testable import BrowserKit
import Foundation
import Testing

/// A Space owns its cookie jar (§3.1, §9, schema `v7`).
///
/// Two things are proved here. The all-zero `dataStoreIdentifier` is still refused on the
/// way in and repaired on the way out — the value `WKWebsiteDataStore(forIdentifier:)`
/// answers with an uncatchable Objective-C exception — and `v7` splits a shared jar without
/// losing one.
///
/// The guard used to live on a `profiles` row. It moved rather than changed: what is
/// asserted below is the same invariant, written on the row that carries it now.
@Suite("Space cookie jars (§3.1, §9, v7)")
struct SpaceJarTests {

    // MARK: - The all-zero identifier (§3.1)

    /// `dataStoreForIdentifier:` documents "Throws exception if identifier is 0". That is an
    /// Objective-C exception, so it is an uncatchable crash rather than an error any call
    /// site can handle — which is why the check happens at the GRDB boundary, where the
    /// value is still data.
    @Test func repairsAZeroDataStoreIdentifierOnRead() async throws {
        let store = try makeTemporaryStore()
        let corrupt = Space(
            name: "Corrupt",
            symbolName: "moon",
            gradient: .defaultSpace,
            dataStoreIdentifier: .zero
        )
        try await store.insertUnvalidated(corrupt)

        let read = try #require(try await store.spaces().first { $0.id == corrupt.id })
        #expect(read.dataStoreIdentifier != .zero)
        #expect(read.hasUsableDataStoreIdentifier)
        // The identity every tab references, and the only one §10 lets sync, is untouched.
        #expect(read.id == corrupt.id)
        #expect(read.name == "Corrupt")
    }

    /// Repairing on read and not persisting it would hand the same landmine to every later
    /// launch, and to any code path that reads the column without going through here.
    @Test func persistsTheRepairSoItCannotComeBack() async throws {
        let path = temporaryDatabasePath()
        let repaired: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.insertUnvalidated(Space(
                name: "Corrupt",
                symbolName: "moon",
                gradient: .defaultSpace,
                dataStoreIdentifier: .zero
            ))
            repaired = try #require(try await store.spaces().first).dataStoreIdentifier
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.spaces().map(\.dataStoreIdentifier) == [repaired])
        #expect(repaired != .zero)
    }

    /// The write side. Stopping a zero identifier reaching the disk is cheaper than
    /// repairing it on every read for the life of the database.
    @Test func refusesToWriteAZeroDataStoreIdentifier() async throws {
        let store = try makeTemporaryStore()
        let corrupt = Space(
            name: "Corrupt",
            symbolName: "moon",
            gradient: .defaultSpace,
            dataStoreIdentifier: .zero
        )

        await #expect(throws: BrowserStoreError.invalidDataStoreIdentifier(spaceID: corrupt.id)) {
            try await store.upsert(corrupt)
        }
        #expect(try await store.spaces().isEmpty)
    }

    /// The sweep's input has to come from the repaired values, or a just-repaired Space's
    /// brand new store looks like an orphan and gets deleted out from under it.
    @Test func liveIdentifiersAreTheRepairedOnes() async throws {
        let store = try makeTemporaryStore()
        try await store.insertUnvalidated(Space(
            name: "Corrupt",
            symbolName: "moon",
            gradient: .defaultSpace,
            dataStoreIdentifier: .zero
        ))

        let live = try await store.liveDataStoreIdentifiers()
        #expect(live.count == 1)
        #expect(!live.contains(.zero))
    }

    /// One jar per Space is the whole point — and the `UNIQUE` index alone does not keep
    /// it, which is what writing this test found. GRDB's upsert names no conflict target,
    /// so SQLite answers a collision by updating the row it hit: the second Space would
    /// have overwritten the first and the first would have been gone. Hence the explicit
    /// refusal in `upsert(_:)`.
    @Test func refusesToPutTwoSpacesInOneJar() async throws {
        let store = try makeTemporaryStore()
        let jar = UUID()
        let first = Space(name: "First", symbolName: "moon", gradient: .defaultSpace, dataStoreIdentifier: jar)
        let second = Space(name: "Second", symbolName: "star", gradient: .defaultSpace, dataStoreIdentifier: jar)
        try await store.upsert(first)

        await #expect(throws: BrowserStoreError.dataStoreIdentifierTaken(spaceID: second.id, by: first.id)) {
            try await store.upsert(second)
        }
        // The point of the refusal: the Space that was already there is still there.
        #expect(try await store.spaces().map(\.name) == ["First"])
    }

    /// And a Space writing its own jar back — every rename, reorder and colour change —
    /// is not a collision with itself.
    @Test func aSpaceMayKeepItsOwnJarAcrossAWrite() async throws {
        let store = try makeTemporaryStore()
        var space = Space(name: "Work", symbolName: "moon", gradient: .defaultSpace)
        try await store.upsert(space)
        space.name = "Research"
        try await store.upsert(space)
        #expect(try await store.spaces().map(\.name) == ["Research"])
    }

    // MARK: - `v7`: splitting a shared jar

    /// The migration that can cost a login, from the shape it will actually meet.
    ///
    /// Two Spaces shared one profile. Afterwards they have a jar each, the first keeps the
    /// one they were sharing — so it stays signed in wherever it was — and the second is
    /// given a new one and starts signed out. There is no third option: the alternative to
    /// one of them keeping it is both of them losing it.
    @Test func splitsASharedJarAndLeavesTheFirstSpaceSignedIn() async throws {
        let path = temporaryDatabasePath()
        let shared = try BrowserStore.seedingALegacySharedProfile(at: path, spaceNames: ["Work", "Research"])

        let store = try BrowserStore(path: path)
        let spaces = try await store.spaces()
        #expect(spaces.map(\.name) == ["Work", "Research"])
        #expect(spaces[0].dataStoreIdentifier == shared)
        #expect(spaces[1].dataStoreIdentifier != shared)
        #expect(Set(spaces.map(\.dataStoreIdentifier)).count == 2)
        let usable = spaces.allSatisfy(\.hasUsableDataStoreIdentifier)
        #expect(usable)
    }

    /// A user who never shared a profile — which is everyone who never went looking for the
    /// setting — keeps the jar they had, so nothing signs out.
    @Test func aSpaceOnItsOwnProfileKeepsItsJar() async throws {
        let path = temporaryDatabasePath()
        let jar = try BrowserStore.seedingALegacySharedProfile(at: path, spaceNames: ["Personal"])

        let store = try BrowserStore(path: path)
        #expect(try await store.spaces().map(\.dataStoreIdentifier) == [jar])
    }

    /// And the row itself is gone, with the column that pointed at it.
    @Test func theProfileRowIsGoneAfterwards() async throws {
        let path = temporaryDatabasePath()
        _ = try BrowserStore.seedingALegacySharedProfile(at: path, spaceNames: ["Personal"])

        let store = try BrowserStore(path: path)
        let tables = try await store.tableNames()
        let spaceColumns = try await store.spaceColumnNames()
        let tabColumns = try await store.tabColumnNames()
        #expect(!tables.contains("profiles"))
        #expect(!spaceColumns.contains("profileID"))
        #expect(!tabColumns.contains("profileID"))
    }

    /// A fresh database is migrated by the same chain, so it lands in the same shape rather
    /// than in whatever `v1` happened to create.
    @Test func aFreshDatabaseIsAlreadyInTheNewShape() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let space = try #require(try await store.spaces().first)
        let tables = try await store.tableNames()
        #expect(space.hasUsableDataStoreIdentifier)
        #expect(!tables.contains("profiles"))
    }
}
