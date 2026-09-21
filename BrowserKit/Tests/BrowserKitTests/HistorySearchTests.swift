import BrowserKit
import Foundation
import Testing

/// §11.2's FTS5 index over title and URL. The Command Bar types into this.
@Suite("History full-text search (§11.2)")
struct HistorySearchTests {

    private func seeded() async throws -> BrowserStore {
        let store = try makeTemporaryStore()
        try await store.recordVisit(
            url: URL(string: "https://developer.apple.com/documentation/webkit")!,
            title: "WebKit — Apple Developer",
            kind: .typed,
            at: daysAgo(1)
        )
        try await store.recordVisit(
            url: URL(string: "https://swift.org/blog")!,
            title: "Swift Blog",
            kind: .link,
            at: daysAgo(1)
        )
        try await store.recordVisit(
            url: URL(string: "https://news.ycombinator.com/")!,
            title: "Hacker News",
            kind: .link,
            at: daysAgo(1)
        )
        return store
    }

    @Test func matchesATitleWord() async throws {
        let hits = try await seeded().searchHistory("hacker", limit: 10)
        #expect(hits.map(\.title) == ["Hacker News"])
    }

    /// The differentiator: a host the user never sees in a title is still findable.
    @Test func matchesAURLToken() async throws {
        let hits = try await seeded().searchHistory("ycombinator", limit: 10)
        #expect(hits.map(\.title) == ["Hacker News"])
    }

    /// Results have to arrive mid-word — the user is still typing (§9.7).
    @Test func matchesOnAPrefix() async throws {
        let hits = try await seeded().searchHistory("swi", limit: 10)
        #expect(hits.map(\.title) == ["Swift Blog"])
    }

    /// Two tokens are an AND, not an OR.
    @Test func requiresEveryToken() async throws {
        let store = try await seeded()
        #expect(try await store.searchHistory("apple webkit", limit: 10).count == 1)
        #expect(try await store.searchHistory("apple hacker", limit: 10).isEmpty)
    }

    @Test func returnsNothingForAMiss() async throws {
        let hits = try await seeded().searchHistory("gopher", limit: 10)
        #expect(hits.isEmpty)
    }

    /// Punctuation is the user's, not FTS5's: `"` and `*` are query syntax and must not
    /// escape into the pattern, or a URL paste blows up the Command Bar.
    @Test func survivesQuerySyntaxInTheQuery() async throws {
        let store = try await seeded()
        #expect(try await store.searchHistory("https://swift.org/blog", limit: 10).count == 1)
        #expect(try await store.searchHistory("\"*(", limit: 10).isEmpty)
    }

    @Test func honoursTheLimit() async throws {
        let hits = try await seeded().searchHistory("", limit: 2)
        #expect(hits.count == 2)
    }

    /// The index tracks `places`, which is written by a trigger rather than by our code —
    /// so a title corrected on a later visit has to be searchable under the new title.
    @Test func reindexesWhenATitleChanges() async throws {
        let store = try makeTemporaryStore()
        let url = URL(string: "https://example.com/page")!
        try await store.recordVisit(url: url, title: "Untitled", kind: .link, at: daysAgo(2))
        try await store.recordVisit(url: url, title: "Quarterly Report", kind: .link, at: daysAgo(1))

        #expect(try await store.searchHistory("quarterly", limit: 10).count == 1)
        #expect(try await store.searchHistory("untitled", limit: 10).isEmpty)
    }
}
