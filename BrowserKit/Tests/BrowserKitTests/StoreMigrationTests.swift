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
            try await store.recordVisit(
                url: URL(string: "https://example.com")!,
                title: "Example",
                kind: .typed,
                at: Date(),
                inSpace: spaceID
            )
            // Without this the visit is still sitting in the buffer (§11.5).
            try await store.flush()
        }

        let reopened = try BrowserStore(path: path)
        #expect(try await reopened.spaces().count == 1)
        #expect(try await reopened.tabs(inSpace: spaceID, includeArchived: false).map(\.id) == [tabID])
        #expect(try await reopened.searchHistory("example", limit: 5, inSpace: spaceID).count == 1)
    }

    /// A buffered visit that nobody flushes is a visit that never happened.
    @Test func doesNotWriteBufferedVisitsUntilFlushed() async throws {
        let path = temporaryDatabasePath()
        let store = try BrowserStore(path: path)
        try await store.seedIfEmpty()
        let space = try await store.spaces()[0].id
        try await store.recordVisit(
            url: URL(string: "https://buffered.example")!,
            title: "Buffered",
            kind: .typed,
            at: Date(),
            inSpace: space
        )

        // A second connection sees only what is committed.
        let other = try BrowserStore(path: path)
        #expect(try await other.searchHistory("buffered", limit: 5, inSpace: space).isEmpty)

        try await store.flush()
        #expect(try await other.searchHistory("buffered", limit: 5, inSpace: space).count == 1)
    }

    @Test func seedsExactlyOnce() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        try await store.seedIfEmpty()

        let spaces = try await store.spaces()
        #expect(spaces.count == 1)
        // The seeded Space must carry a usable identifier, or the first window has no
        // WKWebsiteDataStore to open (§5.1).
        #expect(spaces[0].hasUsableDataStoreIdentifier)
        #expect(spaces[0].symbolName.isEmpty == false)
    }

    /// Since `v8` a visit belongs to a Space, and the two Spaces must not be able
    /// to see each other's — this is the whole of §9.2's isolation, at the bottom
    /// of the stack where it can be proved without a window.
    @Test func aVisitInOneSpaceIsInvisibleFromTheOther() async throws {
        let (store, personal) = try await makeTemporaryStoreWithSpace()
        let work = Space(name: "Work", symbolName: "hammer", gradient: .defaultSpace)
        try await store.upsert(work)

        try await store.recordVisit(
            url: URL(string: "https://mail.example/inbox")!,
            title: "Private Mail",
            kind: .typed,
            at: daysAgo(1),
            inSpace: personal
        )
        try await store.flush()

        #expect(try await store.searchHistory("mail", limit: 10, inSpace: personal).count == 1)
        #expect(try await store.searchHistory("mail", limit: 10, inSpace: work.id).isEmpty)
        // And the opening list of a Space that has never been browsed is empty,
        // rather than the other Space's twenty most recent pages.
        #expect(try await store.searchHistory("", limit: 10, inSpace: work.id).isEmpty)
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
