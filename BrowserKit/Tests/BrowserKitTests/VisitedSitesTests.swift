import BrowserKit
import Foundation
import Testing

/// §9.4's site list: one row per host, the page it opens, and the order the
/// Command Bar completes from.
@Suite("Visited sites (§9.4)")
struct VisitedSitesTests {

    private func visit(
        _ store: BrowserStore, _ address: String, _ kind: VisitKind = .typed, daysAgo days: Double = 1, in space: UUID
    ) async throws {
        try await store.recordVisit(url: URL(string: address)!, title: address, kind: kind, at: daysAgo(days), inSpace: space)
    }

    /// Two letters name a site, so the site's front page is what opens — even
    /// when a page deeper in was visited more.
    @Test func aSiteOpensItsFrontPageWhenItHasOne() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/", daysAgo: 30, in: space)
        for _ in 0..<5 { try await visit(store, "https://github.com/luna/issues", .link, in: space) }

        let sites = try await store.visitedSites(inSpace: space)

        #expect(sites.map(\.host) == ["github.com"])
        #expect(sites.first?.url.absoluteString == "https://github.com/")
    }

    /// Without one, its most visited page.
    @Test func aSiteWithNoFrontPageOpensItsBestPage() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://www.uow.edu.au/study/", in: space)
        try await visit(store, "https://www.uow.edu.au/study/", in: space)
        try await visit(store, "https://www.uow.edu.au/about/", in: space)

        let sites = try await store.visitedSites(inSpace: space)

        #expect(sites.first?.host == "uow.edu.au", "www. is folded into the host a person types")
        #expect(sites.first?.domain == "uow.edu.au")
        #expect(sites.first?.url.absoluteString == "https://www.uow.edu.au/study/")
    }

    /// Typed visits order the list before every other kind: a feed followed by
    /// links all day is not the address the user types.
    @Test func typedVisitsOrderTheSites() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        for _ in 0..<10 { try await visit(store, "https://linkedin.com/feed/\(UUID())", .link, in: space) }
        try await visit(store, "https://linuxcommand.org/", in: space)

        let sites = try await store.visitedSites(inSpace: space)

        #expect(sites.map(\.host) == ["linuxcommand.org", "linkedin.com"])
    }

    /// One link followed once is not a site the bar should complete; three are.
    /// Another Space's visits are not this Space's sites at all.
    @Test func aSiteHasToBeChosenToBeListed() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = Space(name: "Work", symbolName: "briefcase", gradient: .defaultSpace)
        try await store.upsert(other)
        try await visit(store, "https://once.example/", .link, in: space)
        for _ in 0..<3 { try await visit(store, "https://thrice.example/", .link, in: space) }
        try await visit(store, "https://elsewhere.example/", in: other.id)
        try await visit(store, "https://redirected.example/", .redirect, in: space)

        let sites = try await store.visitedSites(inSpace: space)

        #expect(sites.map(\.host) == ["thrice.example"])
    }
}
