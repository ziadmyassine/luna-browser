import BrowserKit
import Foundation
import Testing

/// Open, write, close, reopen. The migrator runs on every launch, so "runs twice over a
/// database that already has data" is the case that matters (§11.1).
@Suite("Store migration & seeding (§11.1)")
struct StoreMigrationTests {

    @Test func survivesACloseAndReopen() async throws {
        let path = temporaryDatabasePath()
        let tabID = UUID()
        let spaceID: UUID

        do {
            let store = try BrowserStore(path: path)
            try await store.seedIfEmpty()
            spaceID = try await store.spaces()[0].id
            try await store.upsert(Tab(id: tabID, spaceID: spaceID, url: URL(string: "https://example.com")!, title: "Example"))
            try await store.recordVisit(url: URL(string: "https://example.com")!, title: "Example", kind: .typed, at: Date())
            // Without this the visit is still sitting in the buffer (§11.5).
            try await store.flush()
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.spaces().count == 1)
        #expect(try await reopened.profiles().count == 1)
        #expect(try await reopened.tabs(inSpace: spaceID, includeArchived: false).map(\.id) == [tabID])
        #expect(try await reopened.searchHistory("example", limit: 5).count == 1)
    }

    /// A buffered visit that nobody flushes is a visit that never happened.
    @Test func doesNotWriteBufferedVisitsUntilFlushed() async throws {
        let path = temporaryDatabasePath()
        let store = try BrowserStore(path: path)
        try await store.recordVisit(url: URL(string: "https://buffered.example")!, title: "Buffered", kind: .typed, at: Date())

        // A second connection sees only what is committed.
        let other = try BrowserStore(path: path)
        #expect(try await other.searchHistory("buffered", limit: 5).isEmpty)

        try await store.flush()
        #expect(try await other.searchHistory("buffered", limit: 5).count == 1)
    }

    @Test func seedsExactlyOnce() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        try await store.seedIfEmpty()

        let spaces = try await store.spaces()
        let profiles = try await store.profiles()
        #expect(spaces.count == 1)
        #expect(profiles.count == 1)
        // The seeded Space must point at the seeded Profile, or the first window has no
        // WKWebsiteDataStore to open (§5.1).
        #expect(spaces[0].profileID == profiles[0].id)
        #expect(spaces[0].symbolName.isEmpty == false)
    }

    /// Foreign keys, not application code, keep a Space's tabs from outliving it.
    @Test func deletingASpaceTakesItsTabs() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0]
        try await store.upsert(Tab(spaceID: space.id, url: URL(string: "https://example.com")!))

        try await store.delete(spaceID: space.id)

        #expect(try await store.spaces().isEmpty)
        #expect(try await store.tabs(inSpace: space.id, includeArchived: true).isEmpty)
    }
}
