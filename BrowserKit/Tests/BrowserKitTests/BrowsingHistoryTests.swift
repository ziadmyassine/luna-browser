import BrowserKit
import Foundation
import Testing

/// §6.4's History: every page the Space visited, newest first, one row per
/// page, searchable by any word of its title or address.
@Suite("Browsing history (§6.4)")
struct BrowsingHistoryTests {

    private func visit(
        _ store: BrowserStore, _ address: String, _ title: String,
        _ kind: VisitKind = .link, daysAgo days: Double, in space: UUID
    ) async throws {
        try await store.recordVisit(url: URL(string: address)!, title: title, kind: kind, at: daysAgo(days), inSpace: space)
    }

    @Test func listsEveryPageNewestFirstOncePerPage() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/driceroland/Search", "driceroland/Search", daysAgo: 3, in: space)
        try await visit(store, "https://swift.org/blog", "Swift Blog", daysAgo: 2, in: space)
        try await visit(store, "https://github.com/driceroland/Search", "driceroland/Search", daysAgo: 1, in: space)
        let pages = try await store.browsingHistory(limit: 10, inSpace: space)
        #expect(pages.map(\.title) == ["driceroland/Search", "Swift Blog"])
        let newest = try #require(pages.first?.lastVisit)
        #expect(abs(newest.timeIntervalSince(daysAgo(1))) < 5, "the row's time is not its newest visit")
    }

    /// A word only the address carries still finds the page — the reported
    /// case was a repository searched for by its owner's name.
    @Test func findsAPageByAWordInItsAddress() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/driceroland/Search", "A small, fast WebKit browser", daysAgo: 1, in: space)
        try await visit(store, "https://swift.org/blog", "Swift Blog", daysAgo: 1, in: space)
        let pages = try await store.browsingHistory(matching: "drice", limit: 10, inSpace: space)
        #expect(pages.map(\.url.absoluteString) == ["https://github.com/driceroland/Search"])
    }

    /// Search results are in time order too: this is a log, not a ranking.
    @Test func searchResultsAreNewestFirst() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/old", "GitHub old", .typed, daysAgo: 5, in: space)
        try await visit(store, "https://github.com/new", "GitHub new", daysAgo: 1, in: space)
        let pages = try await store.browsingHistory(matching: "github", limit: 10, inSpace: space)
        #expect(pages.map(\.title) == ["GitHub new", "GitHub old"])
    }

    /// A redirect or an embedded frame is a page nobody chose to look at.
    @Test func leavesOutPagesTheUserNeverChose() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://t.co/abc", "", .redirect, daysAgo: 1, in: space)
        try await visit(store, "https://ads.example/frame", "", .embed, daysAgo: 1, in: space)
        try await visit(store, "https://swift.org/blog", "Swift Blog", daysAgo: 1, in: space)
        #expect(try await store.browsingHistory(limit: 10, inSpace: space).map(\.title) == ["Swift Blog"])
    }

    /// Another Space's visits are another cookie jar's (§9.2).
    @Test func keepsToItsSpace() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = Space(name: "Work", symbolName: "briefcase", gradient: .defaultSpace)
        try await store.upsert(other)
        try await visit(store, "https://swift.org/blog", "Swift Blog", daysAgo: 1, in: other.id)
        #expect(try await store.browsingHistory(limit: 10, inSpace: space).isEmpty)
        #expect(try await store.browsingHistory(matching: "swift", limit: 10, inSpace: space).isEmpty)
        #expect(try await store.browsingHistory(matching: "swift", limit: 10, inSpace: other.id).count == 1)
    }

    @Test func punctuationAloneMatchesNothing() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://swift.org/blog", "Swift Blog", daysAgo: 1, in: space)
        #expect(try await store.browsingHistory(matching: "…", limit: 10, inSpace: space).isEmpty)
    }
}
