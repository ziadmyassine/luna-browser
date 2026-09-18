@testable import BrowserKit
import Foundation
import Testing

/// Schema `v2`: Favorites re-scoped from per-Space to per-Profile (§2, D-S2).
///
/// Specified by the session layer, implemented in the store. The rule these tests exist to
/// hold is the one that makes the migration safe to run on the owner's real database:
/// **no row is deleted**. Overflow past Arc's cap of 12 is demoted to `pinned`, not removed.
@Suite("Favorites migration, v2 (§2)")
struct FavoritesMigrationTests {

    private struct Fixture {
        var store: BrowserStore
        var profile: Profile
        var spaces: [Space]
    }

    private func seeded() async throws -> Fixture {
        let store = try makeTemporaryStore()
        let profile = Profile(name: "Work")
        try await store.upsert(profile)
        let spaces = [
            Space(name: "A", symbolName: "a", gradient: .defaultSpace, profileID: profile.id, order: 0),
            Space(name: "B", symbolName: "b", gradient: .defaultSpace, profileID: profile.id, order: 1)
        ]
        for space in spaces { try await store.upsert(space) }
        return Fixture(store: store, profile: profile, spaces: spaces)
    }

    @Test func addsTheColumnAndItsIndex() async throws {
        let store = try makeTemporaryStore()
        #expect(try await store.tabColumnNames().contains("profileID"))
        #expect(try await store.indexNames(on: "tabs").contains("tabs_on_profileID"))
    }

    /// The backfill: a favourite belongs to the Profile of the Space it was created in.
    @Test func backfillsEssentialTabsFromTheirSpacesProfile() async throws {
        let path = temporaryDatabasePath()
        let profile = Profile(name: "Work")
        let space = Space(name: "A", symbolName: "a", gradient: .defaultSpace, profileID: profile.id)
        let favourite = UUID()

        do {
            let store = try BrowserStore(path: path)
            try await store.upsert(profile)
            try await store.upsert(space)
            // Written the way a v1 database holds it: no profileID at all.
            try await store.upsert(
                Tab(id: favourite, spaceID: space.id, kind: .essential, url: URL(string: "https://mail.example")!)
            )
            try await store.clearTabProfileIDs()
        }

        let reopened = try BrowserStore(path: path)
        try await reopened.rerunFavoritesMigration()
        let tabs = try await reopened.tabs(inSpace: space.id, includeArchived: true)
        #expect(tabs.first(where: { $0.id == favourite })?.profileID == profile.id)
    }

    /// Two Spaces, one Profile, one pool of favourites — which is the entire point of D-S2.
    @Test func twoSpacesOnOneProfileShareOneFavoritesScope() async throws {
        let fixture = try await seeded()
        let (store, profile, spaces) = (fixture.store, fixture.profile, fixture.spaces)
        for space in spaces {
            try await store.upsert(
                Tab(
                    spaceID: space.id,
                    kind: .essential,
                    url: URL(string: "https://mail.example")!,
                    profileID: profile.id
                )
            )
        }

        let favourites = try await store.favorites(onProfile: profile.id)
        #expect(favourites.count == 2)
        #expect(Set(favourites.map(\.spaceID)) == Set(spaces.map(\.id)))
    }

    /// Only `.essential` carries a Profile. A `pinned` or `today` row with one would be a
    /// second, disagreeing answer to "which cookie jar is this tab in".
    @Test func stripsProfileIDsFromEveryOtherKind() async throws {
        let fixture = try await seeded()
        let (store, profile, spaces) = (fixture.store, fixture.profile, fixture.spaces)
        for kind in [TabKind.pinned, .today] {
            try await store.upsert(
                Tab(spaceID: spaces[0].id, kind: kind, url: URL(string: "https://x.example")!, profileID: profile.id)
            )
        }
        try await store.rerunFavoritesMigration()

        let tabs = try await store.tabs(inSpace: spaces[0].id, includeArchived: true)
        #expect(tabs.count == 2)
        #expect(tabs.allSatisfy { $0.profileID == nil })
    }

    /// The cap trim. Thirteen pooled favourites, twelve survive as favourites, and the
    /// thirteenth becomes a pinned tab in the Space it already lives in — **not** a deletion.
    @Test func demotesOverflowPastTheCapInsteadOfDeletingIt() async throws {
        let fixture = try await seeded()
        let (store, profile, spaces) = (fixture.store, fixture.profile, fixture.spaces)
        let reference = Date()
        var ids: [UUID] = []
        for index in 0..<13 {
            let tab = Tab(
                spaceID: spaces[index % 2].id,
                kind: .essential,
                url: URL(string: "https://site\(index).example")!,
                // Oldest last: index 12 is the least recently active and is the one to go.
                lastActiveAt: reference.addingTimeInterval(-Double(index)),
                profileID: profile.id
            )
            ids.append(tab.id)
            try await store.upsert(tab)
        }

        try await store.rerunFavoritesMigration()

        let all = try await store.allTabsForTesting()
        #expect(all.count == 13, "the migration never deletes a row")
        let favourites = all.filter { $0.kind == .essential }
        #expect(favourites.count == 12)
        #expect(!favourites.map(\.id).contains(ids[12]))

        let demoted = try #require(all.first { $0.id == ids[12] })
        #expect(demoted.kind == .pinned)
        #expect(demoted.profileID == nil, "a pinned tab is per Space, so it carries no Profile")
        #expect(demoted.spaceID == spaces[12 % 2].id, "it stays in the Space it already lives in")
    }

    /// The cap is per Profile, not global: a second Profile gets its own twelve.
    @Test func capsPerProfileNotGlobally() async throws {
        let store = try makeTemporaryStore()
        var made: [UUID] = []
        for name in ["Work", "Personal"] {
            let profile = Profile(name: name)
            let space = Space(name: name, symbolName: "a", gradient: .defaultSpace, profileID: profile.id)
            try await store.upsert(profile)
            try await store.upsert(space)
            made.append(profile.id)
            for index in 0..<12 {
                try await store.upsert(
                    Tab(
                        spaceID: space.id,
                        kind: .essential,
                        url: URL(string: "https://\(name)\(index).example")!,
                        profileID: profile.id
                    )
                )
            }
        }

        try await store.rerunFavoritesMigration()

        for profileID in made {
            #expect(try await store.favorites(onProfile: profileID).count == 12)
        }
    }

    /// The migrator records `v2`, but "it only runs once" is a promise about the migrator,
    /// not about the file. Replaying every statement must change nothing.
    @Test func isSafeToReRun() async throws {
        let fixture = try await seeded()
        let (store, profile, spaces) = (fixture.store, fixture.profile, fixture.spaces)
        for index in 0..<13 {
            try await store.upsert(
                Tab(
                    spaceID: spaces[index % 2].id,
                    kind: .essential,
                    url: URL(string: "https://site\(index).example")!,
                    lastActiveAt: Date().addingTimeInterval(-Double(index)),
                    profileID: profile.id
                )
            )
        }

        try await store.rerunFavoritesMigration()
        let once = try await store.allTabsForTesting().sorted { $0.id.uuidString < $1.id.uuidString }
        try await store.rerunFavoritesMigration()
        try await store.rerunFavoritesMigration()
        let thrice = try await store.allTabsForTesting().sorted { $0.id.uuidString < $1.id.uuidString }

        #expect(once == thrice)
    }

    /// `archive` is a view over `tabs` (`SELECT *`). A new column has to reach it, or every
    /// archived-tab read starts failing to decode the moment `Tab` gains a property.
    @Test func theArchiveViewSeesTheNewColumn() async throws {
        let fixture = try await seeded()
        let (store, profile, spaces) = (fixture.store, fixture.profile, fixture.spaces)
        let archived = Tab(
            spaceID: spaces[0].id,
            kind: .essential,
            url: URL(string: "https://x.example")!,
            archivedAt: Date(),
            profileID: profile.id
        )
        try await store.upsert(archived)

        let fromView = try await store.archivedTabsForTesting()
        #expect(fromView.map(\.id) == [archived.id])
        #expect(fromView.first?.profileID == profile.id)
    }
}
