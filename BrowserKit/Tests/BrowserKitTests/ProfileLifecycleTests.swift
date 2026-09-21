@testable import BrowserKit
import Foundation
import Testing

/// Deleting a profile row, and surviving the one value WebKit cannot be handed (§3.1, §6.3).
@Suite("Profile lifecycle (§3.1, §6.3)")
struct ProfileLifecycleTests {

    // MARK: - delete(profileID:)

    /// Many Spaces may share one profile, so "the Space that owned it is gone" is not the
    /// same question as "anything still needs it". Deleting it anyway would leave a Space
    /// pointing at nothing, which is a window of tabs with no cookie jar.
    @Test func refusesToDeleteAProfileAnySpaceStillNames() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0]
        let profileID = space.profileID

        await #expect(throws: BrowserStoreError.profileInUse(profileID: profileID, spaceIDs: [space.id])) {
            try await store.delete(profileID: profileID)
        }
        #expect(try await store.profile(profileID) != nil)
    }

    /// The many-to-one case: one Space going away does not free a shared profile.
    @Test func refusesWhileASecondSpaceStillSharesTheProfile() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let first = try await store.spaces()[0]
        let second = Space(
            name: "Research",
            symbolName: "book",
            gradient: .defaultSpace,
            profileID: first.profileID,
            order: 1
        )
        try await store.upsert(second)

        try await store.delete(spaceID: first.id)
        await #expect(throws: BrowserStoreError.self) {
            try await store.delete(profileID: first.profileID)
        }

        try await store.delete(spaceID: second.id)
        try await store.delete(profileID: first.profileID)
        #expect(try await store.profile(first.profileID) == nil)
    }

    /// The bug this whole method exists for: `deleteSpace` removed the cookie jar and left
    /// the row, so `profiles` accumulated rows naming stores that no longer existed.
    @Test func deletesTheRowOnceNoSpaceNamesIt() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0]

        try await store.delete(spaceID: space.id)
        try await store.delete(profileID: space.profileID)

        #expect(try await store.profiles().isEmpty)
        #expect(try await store.profile(space.profileID) == nil)
    }

    @Test func reportsWhichSpacesShareAProfile() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let first = try await store.spaces()[0]
        let second = Space(name: "B", symbolName: "b", gradient: .defaultSpace, profileID: first.profileID, order: 1)
        try await store.upsert(second)

        let shared = try await store.spaceIDs(onProfile: first.profileID)
        #expect(Set(shared) == [first.id, second.id])
    }

    // MARK: - The all-zero identifier (§3.1)

    /// `dataStoreForIdentifier:` documents "Throws exception if identifier is 0". That is
    /// an Objective-C exception, so it is an uncatchable crash rather than an error any call
    /// site can handle — which is why the check has to happen here, at the GRDB boundary,
    /// where the value is still data.
    @Test func repairsAZeroDataStoreIdentifierOnRead() async throws {
        let store = try makeTemporaryStore()
        let corrupt = Profile(name: "Corrupt", dataStoreIdentifier: .zero)
        try await store.insertUnvalidated(corrupt)

        let read = try #require(try await store.profile(corrupt.id))
        #expect(read.dataStoreIdentifier != .zero)
        #expect(read.hasUsableDataStoreIdentifier)
        // The identity every Space references, and the only one §10 lets sync, is untouched.
        #expect(read.id == corrupt.id)
        #expect(read.name == "Corrupt")
    }

    /// Repairing on read and not persisting it would hand the same landmine to every later
    /// launch, and to any code path that reads the column without going through here.
    @Test func persistsTheRepairSoItCannotComeBack() async throws {
        let path = temporaryDatabasePath()
        let corrupt = Profile(name: "Corrupt", dataStoreIdentifier: .zero)
        let repaired: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.insertUnvalidated(corrupt)
            repaired = try #require(try await store.profiles().first).dataStoreIdentifier
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.profiles().map(\.dataStoreIdentifier) == [repaired])
        #expect(repaired != .zero)
    }

    /// `profiles()` is the plural boundary and takes the same guard.
    @Test func repairsOnlyTheBrokenRow() async throws {
        let store = try makeTemporaryStore()
        let good = Profile(name: "Aaa")
        let bad = Profile(name: "Bbb", dataStoreIdentifier: .zero)
        try await store.upsert(good)
        try await store.insertUnvalidated(bad)

        let read = try await store.profiles()
        #expect(read.count == 2)
        #expect(read[0].dataStoreIdentifier == good.dataStoreIdentifier)
        #expect(read[1].dataStoreIdentifier != .zero)
        #expect(read.filter(\.hasUsableDataStoreIdentifier).count == 2)
    }

    /// The write side. Stopping a zero identifier reaching the disk is cheaper than repairing
    /// it on every read for the life of the database.
    @Test func refusesToWriteAZeroDataStoreIdentifier() async throws {
        let store = try makeTemporaryStore()
        let corrupt = Profile(name: "Corrupt", dataStoreIdentifier: .zero)

        await #expect(throws: BrowserStoreError.invalidDataStoreIdentifier(profileID: corrupt.id)) {
            try await store.upsert(corrupt)
        }
        #expect(try await store.profiles().isEmpty)
    }

    /// The sweep's input has to come from the repaired values, or a just-repaired profile's
    /// brand new store looks like an orphan and gets deleted out from under it.
    @Test func liveIdentifiersAreTheRepairedOnes() async throws {
        let store = try makeTemporaryStore()
        try await store.insertUnvalidated(Profile(name: "Corrupt", dataStoreIdentifier: .zero))

        let live = try await store.liveDataStoreIdentifiers()
        #expect(live.count == 1)
        #expect(!live.contains(.zero))
    }
}
