import BrowserKit
import Foundation
import Testing

/// §9.3's ranking, asserted against hand-computed scores. The Command Bar is only as good
/// as this order, so the numbers are spelled out rather than derived from the implementation.
@Suite("Frecency ranking (§9.3)")
struct FrecencyRankingTests {

    private func url(_ host: String) -> URL {
        URL(string: "https://\(host).example/")!
    }

    /// typed 200 · bookmarked 140 · link 120 · redirect/embed 0, times the recency weight.
    @Test func ordersPlacesBySummedVisitScore() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()

        // 2 × (120 link × 1.0 recency) = 240
        try await store.recordVisit(url: url("twice-linked"), title: "Twice linked", kind: .link, at: daysAgo(1), inSpace: space)
        try await store.recordVisit(url: url("twice-linked"), title: "Twice linked", kind: .link, at: daysAgo(2), inSpace: space)
        // 1 × (200 typed × 1.0) = 200
        try await store.recordVisit(url: url("typed-today"), title: "Typed today", kind: .typed, at: daysAgo(1), inSpace: space)
        // 1 × (140 bookmarked × 0.5, 20 days ago) = 70
        try await store.recordVisit(url: url("bookmarked"), title: "Bookmarked", kind: .bookmarked, at: daysAgo(20), inSpace: space)
        // 1 × (200 typed × 0.1, 200 days ago) = 20
        try await store.recordVisit(url: url("stale"), title: "Stale", kind: .typed, at: daysAgo(200), inSpace: space)
        // 3 × (0 redirect) = 0 — a redirect chain must never outrank a real visit.
        for day in 1...3 {
            try await store.recordVisit(
                url: url("redirects"),
                title: "Redirects",
                kind: .redirect,
                at: daysAgo(Double(day)),
                inSpace: space
            )
        }

        let hits = try await store.searchHistory("", limit: 10, inSpace: space)

        #expect(hits.map(\.title) == ["Twice linked", "Typed today", "Bookmarked", "Stale", "Redirects"])
        #expect(abs(hits[0].score - 240) < 0.001)
        #expect(abs(hits[1].score - 200) < 0.001)
        #expect(abs(hits[2].score - 70) < 0.001)
        #expect(abs(hits[3].score - 20) < 0.001)
        #expect(hits[4].score == 0)
    }

    /// The recency bucket table, one identical typed visit per bucket.
    @Test(arguments: [(1.0, 200.0), (10.0, 140.0), (20.0, 100.0), (60.0, 60.0), (200.0, 20.0)])
    func weightsOneVisitByItsAge(age: Double, expected: Double) async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await store.recordVisit(url: url("single"), title: "Single", kind: .typed, at: daysAgo(age), inSpace: space)

        let hits = try await store.searchHistory("", limit: 1, inSpace: space)

        #expect(hits.count == 1)
        #expect(abs(hits[0].score - expected) < 0.001)
    }

    /// "Score each URL from its 10 most recent visits". Without the cap a page opened in
    /// a loop by a script would bury everything the user actually chose.
    @Test func scoresAtMostTenVisits() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        for minute in 0..<25 {
            try await store.recordVisit(
                url: url("hammered"),
                title: "Hammered",
                kind: .link,
                at: daysAgo(1).addingTimeInterval(Double(minute) * 60),
                inSpace: space
            )
        }

        let hits = try await store.searchHistory("", limit: 5, inSpace: space)

        // 10 × 120 × 1.0, not 25 × 120.
        #expect(abs(hits[0].score - 1200) < 0.001)
    }

    /// The cap keeps the most recent ten, so ten fresh visits must beat ten old ones even
    /// when the old page has far more of them.
    @Test func keepsTheMostRecentTenNotTheFirstTen() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        for index in 0..<15 {
            // Oldest row inserted first, ages 200, 188, … 32 days.
            try await store.recordVisit(
                url: url("aging"),
                title: "Aging",
                kind: .link,
                at: daysAgo(Double(200 - index * 12)),
                inSpace: space
            )
        }

        let hits = try await store.searchHistory("", limit: 5, inSpace: space)

        // Newest ten (140…32 days) = 120 × (5 × 0.1 + 5 × 0.3) = 240.
        // The ten oldest (200…92 days) would be 120 × 10 × 0.1 = 120.
        #expect(abs(hits[0].score - 240) < 0.001)
    }
}
