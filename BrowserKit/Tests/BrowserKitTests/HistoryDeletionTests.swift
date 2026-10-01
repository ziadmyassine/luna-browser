@testable import BrowserKit
import Foundation
import GRDB
import Testing

/// §11.3: taking pages out of one Space's history — chosen pages, a span of
/// time, a whole site — and everything that would otherwise bring them back:
/// the Command Bar's ranking, its adaptive lessons, the search index and sync.
@Suite("History deletion (§11.3)")
struct HistoryDeletionTests {

    private func visit(
        _ store: BrowserStore, _ address: String, _ kind: VisitKind = .link,
        hoursAgo hours: Double, in space: UUID
    ) async throws {
        try await store.recordVisit(
            url: URL(string: address)!, title: address, kind: kind,
            at: Date().addingTimeInterval(-hours * 3600), inSpace: space
        )
    }

    private func shown(_ store: BrowserStore, in space: UUID) async throws -> [String] {
        try await store.browsingHistory(limit: 100, inSpace: space).map(\.url.absoluteString)
    }

    private func otherSpace(_ store: BrowserStore) async throws -> UUID {
        let other = Space(name: "Work", symbolName: "briefcase", gradient: .defaultSpace)
        try await store.upsert(other)
        return other.id
    }

    @Test func deletingPagesTakesThemOutOfTheListAndTheCommandBar() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/a", .typed, hoursAgo: 3, in: space)
        try await visit(store, "https://github.com/a", hoursAgo: 1, in: space)
        try await visit(store, "https://swift.org/", hoursAgo: 2, in: space)
        try await store.deleteHistory(of: [URL(string: "https://github.com/a")!], inSpace: space)

        #expect(try await shown(store, in: space) == ["https://swift.org/"])
        #expect(try await store.searchHistory("github", limit: 10, inSpace: space).isEmpty)
        #expect(try await store.searchHistory("", limit: 10, inSpace: space).map(\.url.absoluteString) == ["https://swift.org/"])
    }

    /// The other Space visited the same page; its history is its own.
    @Test func deletingInOneSpaceLeavesTheOther() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = try await otherSpace(store)
        try await visit(store, "https://github.com/a", hoursAgo: 1, in: space)
        try await visit(store, "https://github.com/a", hoursAgo: 1, in: other)
        try await store.deleteHistory(since: nil, inSpace: space)

        #expect(try await shown(store, in: space).isEmpty)
        #expect(try await shown(store, in: other) == ["https://github.com/a"])
        #expect(try await store.searchHistory("github", limit: 10, inSpace: other).count == 1)
    }

    /// A page with an older visit outside the span stays, dated by that visit.
    @Test func clearingASpanKeepsOlderVisits() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/a", hoursAgo: 30, in: space)
        try await visit(store, "https://github.com/a", hoursAgo: 0.2, in: space)
        try await visit(store, "https://swift.org/", hoursAgo: 0.5, in: space)
        try await visit(store, "https://apple.com/", hoursAgo: 5, in: space)
        try await store.deleteHistory(since: Date().addingTimeInterval(-3600), inSpace: space)

        let pages = try await store.browsingHistory(limit: 10, inSpace: space)
        #expect(pages.map(\.url.absoluteString) == ["https://apple.com/", "https://github.com/a"])
        let github = try #require(pages.last?.lastVisit)
        #expect(abs(github.timeIntervalSinceNow + 30 * 3600) < 5, "the page kept the date of the visit that was cleared")
        let stored = try await store.pool.read { db in
            try Date.fetchOne(db, sql: "SELECT lastVisit FROM places WHERE url = 'https://github.com/a'")
        }
        #expect(abs((stored ?? .distantPast).timeIntervalSinceNow + 30 * 3600) < 5)
    }

    @Test func forgettingASiteTakesItsSubdomainsAndNotItsLookalikes() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = try await otherSpace(store)
        for address in ["https://apple.com/", "https://developer.apple.com/xcode", "https://notapple.com/", "https://apple.co.uk/"] {
            try await visit(store, address, hoursAgo: 1, in: space)
        }
        try await visit(store, "https://apple.com/", hoursAgo: 1, in: other)
        try await store.deleteHistory(ofSite: "apple.com", inSpace: space)

        #expect(Set(try await shown(store, in: space)) == ["https://notapple.com/", "https://apple.co.uk/"])
        #expect(try await shown(store, in: other) == ["https://apple.com/"])
    }

    /// An adaptive lesson ranks above everything (§9.3), so a deleted page
    /// would otherwise stay first in the Command Bar.
    @Test func aPageGoneFromTheSpaceTakesItsLessonsWithIt() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = try await otherSpace(store)
        let page = URL(string: "https://github.com/a")!
        try await visit(store, page.absoluteString, .typed, hoursAgo: 1, in: space)
        try await visit(store, page.absoluteString, .typed, hoursAgo: 1, in: other)
        try await store.setInputUseCount(typed: "gi", url: page, useCount: 3, inSpace: space)
        try await store.setInputUseCount(typed: "gi", url: page, useCount: 3, inSpace: other)

        try await store.deleteHistory(of: [page], inSpace: space)
        #expect(try await store.inputHistory(inSpace: space).isEmpty)
        #expect(try await store.inputHistory(inSpace: other).count == 1)
    }

    /// Clearing the last hour is not unlearning a page typed for months.
    @Test func aLessonStaysWhileTheSpaceStillHasThePage() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let page = URL(string: "https://github.com/a")!
        try await visit(store, page.absoluteString, .typed, hoursAgo: 48, in: space)
        try await visit(store, page.absoluteString, .typed, hoursAgo: 0.1, in: space)
        try await store.setInputUseCount(typed: "gi", url: page, useCount: 3, inSpace: space)
        try await store.deleteHistory(since: Date().addingTimeInterval(-3600), inSpace: space)
        #expect(try await store.inputHistory(inSpace: space).map(\.typed) == ["gi"])
    }

    /// A page nobody has visited or learned leaves the disk, and the index.
    @Test func aPageNobodyHasLeavesTheSearchIndex() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/a", hoursAgo: 1, in: space)
        try await store.deleteHistory(since: nil, inSpace: space)
        let (places, indexed) = try await store.pool.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM places") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM placeSearch WHERE placeSearch MATCH 'github'") ?? -1
            )
        }
        #expect(places == 0)
        #expect(indexed == 0)
    }

    /// A visit still in the write buffer is deleted too, rather than landing a
    /// second later and putting the page back.
    @Test func aBufferedVisitIsDeletedToo() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await visit(store, "https://github.com/a", hoursAgo: 0, in: space)
        try await store.deleteHistory(since: Date().addingTimeInterval(-60), inSpace: space)
        try await store.flush()
        #expect(try await shown(store, in: space).isEmpty)
    }

    // MARK: - Sync

    private func outbox(_ store: BrowserStore) async throws -> [(key: String, isDelete: Bool)] {
        try await store.syncOutbox().map { ($0.localKey, $0.isDelete) }
    }

    private func placeKey(_ store: BrowserStore, _ address: String) async throws -> String {
        let id = try await store.pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM places WHERE url = ?", arguments: [address])
        }
        return try #require(id.map { String($0) })
    }

    /// The last typed visit going deletes the entry this Mac sent.
    @Test func deletingThePagesLastSentVisitDeletesItsEntry() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.history, enabled: true)
        try await visit(store, "https://github.com/a", .typed, hoursAgo: 1, in: space)
        try await store.flush()
        let key = try await placeKey(store, "https://github.com/a")
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }

        try await store.deleteHistory(since: nil, inSpace: space)
        let queued = try await outbox(store)
        #expect(queued.map(\.key) == [key])
        #expect(queued.map(\.isDelete) == [true])
    }

    /// Another Space's typed visits are in the same entry, so it is sent again
    /// without this Space's, not deleted.
    @Test func deletingOneSpacesVisitsResendsTheEntry() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        let other = try await otherSpace(store)
        try await store.setSyncZone(.history, enabled: true)
        try await visit(store, "https://github.com/a", .typed, hoursAgo: 1, in: space)
        try await visit(store, "https://github.com/a", .typed, hoursAgo: 2, in: other)
        try await store.flush()
        try await store.pool.write { db in try db.execute(sql: "DELETE FROM syncOutbox") }

        try await store.deleteHistory(of: [URL(string: "https://github.com/a")!], inSpace: space)
        #expect(try await outbox(store).map(\.isDelete) == [false])
    }

    /// A link visit was never sent, and a visit from another Mac is that Mac's.
    @Test func deletingVisitsThisMacNeverSentQueuesNothing() async throws {
        let (store, space) = try await makeTemporaryStoreWithSpace()
        try await store.setSyncZone(.history, enabled: true)
        try await visit(store, "https://github.com/a", .link, hoursAgo: 1, in: space)
        try await store.flush()
        let key = try await placeKey(store, "https://github.com/a")
        try await store.pool.write { db in
            try db.execute(
                sql: "INSERT INTO visits (placeId, at, type, spaceID, syncOrigin) VALUES (?, ?, 'typed', ?, 'other-mac')",
                arguments: [Int64(key), Date(), space]
            )
            try db.execute(sql: "DELETE FROM syncOutbox")
        }
        try await store.deleteHistory(since: nil, inSpace: space)
        #expect(try await store.syncOutbox().isEmpty)
    }
}
