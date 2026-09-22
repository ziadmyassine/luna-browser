import BrowserKit
import Foundation
import Testing

/// §11.2's FTS5 index over title and URL. The Command Bar types into this.
@Suite("History full-text search (§11.2)")
struct HistorySearchTests {

    private func seeded() async throws -> (store: BrowserStore, space: UUID) {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await store.recordVisit(
            url: URL(string: "https://developer.apple.com/documentation/webkit")!,
            title: "WebKit — Apple Developer",
            kind: .typed,
            at: daysAgo(1),
            inSpace: space
        )
        try await store.recordVisit(
            url: URL(string: "https://swift.org/blog")!,
            title: "Swift Blog",
            kind: .link,
            at: daysAgo(1),
            inSpace: space
        )
        try await store.recordVisit(
            url: URL(string: "https://news.ycombinator.com/")!,
            title: "Hacker News",
            kind: .link,
            at: daysAgo(1),
            inSpace: space
        )
        return (store, space)
    }

    @Test func matchesATitleWord() async throws {
        let (store, space) = try await seeded()
        let hits = try await store.searchHistory("hacker", limit: 10, inSpace: space)
        #expect(hits.map(\.title) == ["Hacker News"])
    }

    /// The differentiator: a host the user never sees in a title is still findable.
    @Test func matchesAURLToken() async throws {
        let (store, space) = try await seeded()
        let hits = try await store.searchHistory("ycombinator", limit: 10, inSpace: space)
        #expect(hits.map(\.title) == ["Hacker News"])
    }

    /// Results have to arrive mid-word — the user is still typing (§9.7).
    @Test func matchesOnAPrefix() async throws {
        let (store, space) = try await seeded()
        let hits = try await store.searchHistory("swi", limit: 10, inSpace: space)
        #expect(hits.map(\.title) == ["Swift Blog"])
    }

    /// Two tokens are an AND, not an OR.
    @Test func requiresEveryToken() async throws {
        let (store, space) = try await seeded()
        #expect(try await store.searchHistory("apple webkit", limit: 10, inSpace: space).count == 1)
        #expect(try await store.searchHistory("apple hacker", limit: 10, inSpace: space).isEmpty)
    }

    @Test func returnsNothingForAMiss() async throws {
        let (store, space) = try await seeded()
        #expect(try await store.searchHistory("gopher", limit: 10, inSpace: space).isEmpty)
    }

    /// Punctuation is the user's, not FTS5's: `"` and `*` are query syntax and must not
    /// escape into the pattern, or a URL paste blows up the Command Bar.
    @Test func survivesQuerySyntaxInTheQuery() async throws {
        let (store, space) = try await seeded()
        #expect(try await store.searchHistory("https://swift.org/blog", limit: 10, inSpace: space).count == 1)
        #expect(try await store.searchHistory("\"*(", limit: 10, inSpace: space).isEmpty)
    }

    @Test func honoursTheLimit() async throws {
        let (store, space) = try await seeded()
        #expect(try await store.searchHistory("", limit: 2, inSpace: space).count == 2)
    }

    /// The index tracks `places`, which is written by a trigger rather than by our code —
    /// so a title corrected on a later visit has to be searchable under the new title.
    @Test func reindexesWhenATitleChanges() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let url = URL(string: "https://example.com/page")!
        try await store.recordVisit(url: url, title: "Untitled", kind: .link, at: daysAgo(2), inSpace: space)
        try await store.recordVisit(url: url, title: "Quarterly Report", kind: .link, at: daysAgo(1), inSpace: space)

        #expect(try await store.searchHistory("quarterly", limit: 10, inSpace: space).count == 1)
        #expect(try await store.searchHistory("untitled", limit: 10, inSpace: space).isEmpty)
    }
}
