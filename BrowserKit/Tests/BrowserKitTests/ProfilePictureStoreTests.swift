@testable import BrowserKit
import Foundation
import Testing

/// `v5`: a profile carries the picture the user gave it (§9).
///
/// The column is nullable with no backfill, so the two things worth proving are
/// that bytes survive a close and reopen, and that a profile written before the
/// column existed still reads back — which is the case every database on a Mac
/// today is in.
@Suite("Profile pictures (§9, v5)")
struct ProfilePictureStoreTests {

    /// Not a real PNG: this suite is about the column, and the bytes are opaque
    /// to everything below the app that draws them.
    private let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF])

    @Test func aPictureSurvivesACloseAndReopen() async throws {
        let path = temporaryDatabasePath()
        let id: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
            var profile = try #require(try await store.profiles().first)
            id = profile.id
            profile.imageData = bytes
            try await store.upsert(profile)
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.profile(id)?.imageData == bytes)
    }

    /// Nil is the answer for a profile nobody has given a picture, which is
    /// every profile that existed before the column did.
    @Test func aProfileWithNoPictureReadsBackNil() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        #expect(try await store.profiles().allSatisfy { $0.imageData == nil })
    }

    /// Taking the picture off is a write of nil, not a row that keeps the old
    /// bytes because nothing overwrote them.
    @Test func clearingAPictureClearsTheColumn() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        var profile = try #require(try await store.profiles().first)
        profile.imageData = bytes
        try await store.upsert(profile)
        profile.imageData = nil
        try await store.upsert(profile)
        #expect(try await store.profile(profile.id)?.imageData == nil)
    }

    /// The repair path rebuilds the row field by field, and a field left out of
    /// it is a picture lost to a problem that had nothing to do with pictures.
    @Test func repairingADataStoreIdentifierKeepsThePicture() async throws {
        let broken = Profile(name: "Corrupt", dataStoreIdentifier: .zero, imageData: bytes)
        let repaired = broken.repairingDataStoreIdentifier()
        #expect(repaired.imageData == bytes)
        #expect(repaired.dataStoreIdentifier != .zero)
    }

    /// The migration is guarded on the live schema, because "this runs once" is
    /// a promise about the migrator and not about the file on disk.
    @Test func theMigrationIsSafeToRunTwice() async throws {
        let path = temporaryDatabasePath()
        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
        }
        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.profiles().count == 1)
    }
}
