import BrowserKit
import Foundation
import Testing

/// §6.2: `interactionState` is WebKit's opaque session blob — back/forward history and
/// scroll position. If SQLite mangles a single byte, restore silently loses the session.
@Suite("Tab persistence (§6.1, §6.2)")
struct TabPersistenceTests {

    private func storeWithSpace() async throws -> (BrowserStore, Space) {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()
        return try await (store, store.spaces()[0])
    }

    @Test func interactionStateSurvivesTheRoundTrip() async throws {
        let (store, space) = try await storeWithSpace()
        // Real blobs are kilobytes of arbitrary bytes, including NUL and invalid UTF-8.
        var blob = Data([0x00, 0xFF, 0xFE, 0x00, 0x7F])
        blob.append(contentsOf: (0..<4096).map { UInt8($0 % 251) })
        let tab = Tab(spaceID: space.id, url: URL(string: "https://example.com/deep/page?q=1#frag")!, interactionState: blob)

        try await store.upsert(tab)
        let restored = try await store.tabs(inSpace: space.id, includeArchived: false)

        #expect(restored.count == 1)
        #expect(restored[0].interactionState == blob)
        #expect(restored[0].url == tab.url)
    }

    /// Every field, because a `Codable` column that silently stops being written looks
    /// exactly like a field the user never set.
    @Test func roundTripsEveryField() async throws {
        let (store, space) = try await storeWithSpace()
        let parent = Tab(spaceID: space.id, url: URL(string: "https://parent.example")!)
        try await store.upsert(parent)
        let tab = Tab(
            spaceID: space.id,
            kind: .essential,
            url: URL(string: "https://child.example")!,
            title: "Child",
            faviconKey: "child.example",
            themeColor: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1),
            // Whole seconds: SQLite keeps dates to the millisecond, so a `Date()` taken now
            // would fail an equality check for reasons that have nothing to do with the store.
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_700_003_600),
            archivedAt: Date(timeIntervalSince1970: 1_700_007_200),
            parentTabID: parent.id,
            interactionState: Data([1, 2, 3]),
            hasUnread: true,
            order: 7,
            pinnedURL: URL(string: "https://child.example/home")!,
            customTitle: "Invoices",
            customSymbolName: "star"
        )

        try await store.upsert(tab)
        let restored = try await store.tabs(inSpace: space.id, includeArchived: true).first { $0.id == tab.id }

        #expect(restored == tab)
    }

    /// Schema `v3`. The column is nullable on purpose — nil means "this tab has no home
    /// to go back to", which is the truth for every tab that is not a tile — so the one
    /// thing worth asserting is that nil survives as nil rather than arriving back as the
    /// tab's own URL, which is what a non-null column with a default would have done.
    @Test func aTabWithNoHomeKeepsNotHavingOne() async throws {
        let (store, space) = try await storeWithSpace()
        let tab = Tab(spaceID: space.id, url: URL(string: "https://example.com/somewhere")!)
        try await store.upsert(tab)

        let restored = try await store.tabs(inSpace: space.id, includeArchived: false)
        #expect(restored[0].pinnedURL == nil)
    }

    /// `upsert` is an update, not a second row — the sidebar writes on every title change.
    @Test func upsertReplacesRatherThanDuplicates() async throws {
        let (store, space) = try await storeWithSpace()
        var tab = Tab(spaceID: space.id, url: URL(string: "https://example.com")!, title: "Loading…")
        try await store.upsert(tab)
        tab.title = "Example Domain"
        try await store.upsert(tab)

        let restored = try await store.tabs(inSpace: space.id, includeArchived: false)
        #expect(restored.count == 1)
        #expect(restored[0].title == "Example Domain")
    }

    @Test func hidesArchivedTabsUnlessAsked() async throws {
        let (store, space) = try await storeWithSpace()
        try await store.upsert(Tab(spaceID: space.id, url: URL(string: "https://live.example")!, title: "Live"))
        try await store.upsert(Tab(
            spaceID: space.id,
            url: URL(string: "https://archived.example")!,
            title: "Archived",
            archivedAt: daysAgo(1)
        ))

        #expect(try await store.tabs(inSpace: space.id, includeArchived: false).map(\.title) == ["Live"])
        #expect(try await store.tabs(inSpace: space.id, includeArchived: true).count == 2)
    }

    /// The sidebar renders in `order`; §6.6 drags rewrite it.
    @Test func returnsTabsInOrder() async throws {
        let (store, space) = try await storeWithSpace()
        for (index, title) in ["third", "first", "second"].enumerated() {
            let position = ["third": 2, "first": 0, "second": 1][title] ?? index
            try await store.upsert(Tab(
                spaceID: space.id,
                url: URL(string: "https://\(title).example")!,
                title: title,
                order: position
            ))
        }

        let restored = try await store.tabs(inSpace: space.id, includeArchived: false)
        #expect(restored.map(\.title) == ["first", "second", "third"])
    }

    @Test func deletesOneTabWithoutTouchingTheRest() async throws {
        let (store, space) = try await storeWithSpace()
        let doomed = Tab(spaceID: space.id, url: URL(string: "https://doomed.example")!, title: "Doomed")
        try await store.upsert(doomed)
        try await store.upsert(Tab(spaceID: space.id, url: URL(string: "https://kept.example")!, title: "Kept"))

        try await store.delete(tabID: doomed.id)

        #expect(try await store.tabs(inSpace: space.id, includeArchived: true).map(\.title) == ["Kept"])
    }
}
