@testable import BrowserKit
import Foundation
import Testing

/// A Space carries the picture the user gave it (§9, schema `v5` and `v7`).
///
/// The column was born on the `profiles` row and moved onto `spaces` when the Profile
/// concept went. The two things worth proving are that bytes survive a close and reopen,
/// and that a Space written before the column existed still reads back — which is the case
/// every database on a Mac today is in.
@Suite("Space pictures (§9)")
struct SpacePictureStoreTests {

    /// Not a real PNG: this suite is about the column, and the bytes are opaque to
    /// everything below the app that draws them.
    private let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF])

    @Test func aPictureSurvivesACloseAndReopen() async throws {
        let path = temporaryDatabasePath()
        let id: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
            var space = try #require(try await store.spaces().first)
            id = space.id
            space.imageData = bytes
            try await store.upsert(space)
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.spaces().first?.imageData == bytes)
        #expect(try await reopened.spaces().first?.id == id)
    }

    /// Nil is the answer for a Space nobody has given a picture, which is every Space that
    /// existed before the column did.
    @Test func aSpaceWithNoPictureReadsBackNil() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let blank = try await store.spaces().allSatisfy { $0.imageData == nil }
        #expect(blank)
    }

    /// Taking the picture off is a write of nil, not a row that keeps the old bytes because
    /// nothing overwrote them.
    @Test func clearingAPictureClearsTheColumn() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        var space = try #require(try await store.spaces().first)
        space.imageData = bytes
        try await store.upsert(space)
        space.imageData = nil
        try await store.upsert(space)
        #expect(try await store.spaces().first?.imageData == nil)
    }

    /// The repair path rebuilds the row, and a field left out of it is a picture lost to a
    /// problem that had nothing to do with pictures.
    @Test func repairingADataStoreIdentifierKeepsThePicture() async throws {
        let broken = Space(
            name: "Corrupt",
            symbolName: "moon",
            gradient: .defaultSpace,
            dataStoreIdentifier: .zero,
            imageData: bytes
        )
        let repaired = broken.repairingDataStoreIdentifier()
        #expect(repaired.imageData == bytes)
        #expect(repaired.dataStoreIdentifier != .zero)
        #expect(repaired.name == "Corrupt")
    }
}
