@testable import BrowserKit
import Foundation
import Testing

/// Favorites belong to a Space (§2, decision D-S2, schema `v2` and `v7`).
///
/// A Favorite is a logged-in app tile, so it belongs to the cookie jar that holds the
/// login. `v2` read that as "the profile" and `v7` reads it as "the Space", because a Space
/// owns its jar now and nothing else does. The scope did not change; the row carrying it
/// did.
///
/// The rule the migration tests hold is the one that makes `v7` safe to run on a real
/// database: no row is deleted. Eleven tests of `v2`'s per-profile scope were removed with
/// the column they asserted on — what is left is what can still be observed, plus the
/// guarantee that survived.
@Suite("Favorites scope (§2)")
struct FavoritesScopeTests {

    private func tile(_ space: UUID, _ host: String, order: Int, archived: Date? = nil) -> Tab {
        Tab(
            spaceID: space,
            kind: .essential,
            url: URL(string: "https://\(host)")!,
            title: host,
            archivedAt: archived,
            order: order
        )
    }

    private func twoSpaces() async throws -> (store: BrowserStore, first: Space, second: Space) {
        let store = try makeTemporaryStore()
        let first = Space(name: "Work", symbolName: "a", gradient: .defaultSpace, order: 0)
        let second = Space(name: "Personal", symbolName: "b", gradient: .defaultSpace, order: 1)
        try await store.upsert(first)
        try await store.upsert(second)
        return (store, first, second)
    }

    // MARK: - What the scope is now

    @Test func aFavoriteIsFoundInTheSpaceItWasMadeIn() async throws {
        let (store, first, second) = try await twoSpaces()
        try await store.upsert(tile(first.id, "mail.example", order: 0))
        try await store.upsert(tile(second.id, "photos.example", order: 0))

        #expect(try await store.favorites(inSpace: first.id).map(\.title) == ["mail.example"])
        #expect(try await store.favorites(inSpace: second.id).map(\.title) == ["photos.example"])
    }

    /// Two Spaces no longer pool anything. That was the sharing `v7` ended, and the tile
    /// that used to appear in both now appears in the one it was made in.
    @Test func twoSpacesDoNotShareAScope() async throws {
        let (store, first, second) = try await twoSpaces()
        for index in 0..<3 { try await store.upsert(tile(first.id, "tile\(index).example", order: index)) }

        #expect(try await store.favorites(inSpace: first.id).count == 3)
        #expect(try await store.favorites(inSpace: second.id).isEmpty)
    }

    /// Archived ones are off the shelf, not gone: they neither show up here nor count
    /// against the cap. `deleteSpace(_:policy: .archiveTabs)` is what archives one.
    @Test func archivedFavoritesAreExcluded() async throws {
        let (store, first, _) = try await twoSpaces()
        try await store.upsert(tile(first.id, "live.example", order: 0))
        try await store.upsert(tile(first.id, "shelved.example", order: 1, archived: Date()))

        #expect(try await store.favorites(inSpace: first.id).map(\.title) == ["live.example"])
    }

    @Test func favoritesComeBackInDisplayOrder() async throws {
        let (store, first, _) = try await twoSpaces()
        for index in [2, 0, 1] { try await store.upsert(tile(first.id, "tile\(index).example", order: index)) }

        #expect(try await store.favorites(inSpace: first.id).map(\.order) == [0, 1, 2])
    }

    /// Arc's number, and Luna's. It is a cap per Space now rather than per profile, which
    /// is the same cap for everyone who never shared one.
    @Test func theCapIsArcs() {
        #expect(BrowserStore.favoritesCap == 12)
    }

    // MARK: - What `v7` had to preserve

    /// The guarantee that carried over from `v2`: no row is deleted. A legacy database's
    /// Favorites all survive the migration, each in the Space it was made in — which is
    /// where the `spaceID` they already carried said they lived.
    @Test func everyLegacyFavoriteSurvivesTheMigration() async throws {
        let path = temporaryDatabasePath()
        _ = try BrowserStore.seedingALegacySharedProfile(
            at: path,
            spaceNames: ["Work", "Research"],
            favoritesPerSpace: 3
        )

        let store = try BrowserStore(path: path)
        let spaces = try await store.spaces()
        #expect(try await store.allTabsForTesting().count == 6)
        for space in spaces {
            #expect(try await store.favorites(inSpace: space.id).count == 3)
        }
    }
}
