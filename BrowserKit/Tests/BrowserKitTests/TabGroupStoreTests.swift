//
//  TabGroupStoreTests.swift
//  BrowserKitTests
//
//  Schema `v6` — §3.4b's groups, and the two columns that make a saved tab
//  outlive its page.
//
//  The one rule worth a test on its own is `ON DELETE SET NULL`: removing a
//  group must never remove pages. Everything else here is the ordinary
//  round-trip, and the ordering self-heal that `groups(inSpace:)` deliberately
//  does *not* do.
//

import BrowserKit
import Foundation
import Testing

@Suite("Tab groups (§3.4b)")
struct TabGroupStoreTests {

    @Test("a group round-trips with its name, icon, tier and fold")
    func roundTrip() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        let group = TabGroup(
            spaceID: space.id,
            name: "Research",
            symbolName: "books.vertical",
            kind: .pinned,
            isCollapsed: true,
            order: 3
        )
        try await store.upsert(group)

        let read = try #require(try await store.groups(inSpace: space.id).first)
        #expect(read == group)
        #expect(read.isSaved)
    }

    /// §3.3's grid is one tile per tab, so a group cannot be one. Repaired on
    /// the way in rather than refused: the ordinary section is the nearest true
    /// thing, and throwing would lose the group.
    @Test("a group can never be written into the Essentials tier")
    func aGroupIsNeverEssential() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        var group = TabGroup(spaceID: space.id, name: "Nope")
        group.kind = .essential
        try await store.upsert(group)

        #expect(try await store.groups(inSpace: space.id).first?.kind == .today)
    }

    /// Removing a group removes a name, never a page. The tabs come back loose
    /// in the tier they were already in.
    @Test("deleting a group leaves its tabs behind, ungrouped")
    func deletingAGroupKeepsItsTabs() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        let group = TabGroup(spaceID: space.id, name: "Work", kind: .pinned)
        try await store.upsert(group)
        let member = Tab(
            spaceID: space.id,
            kind: .pinned,
            url: URL(string: "https://example.com/one")!,
            groupID: group.id
        )
        try await store.upsert(member)

        try await store.delete(groupID: group.id)

        let tabs = try await store.tabs(inSpace: space.id, includeArchived: false)
        #expect(tabs.count == 1)
        #expect(tabs.first?.groupID == nil)
        #expect(tabs.first?.kind == .pinned)
    }

    /// The two `v6` columns default the way every row that existed before them
    /// already was: loose, and never closed.
    @Test("a tab with no group and no closed page is the default")
    func newColumnsDefault() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        try await store.upsert(Tab(spaceID: space.id, url: URL(string: "https://example.com")!))

        let tab = try #require(try await store.tabs(inSpace: space.id, includeArchived: false).first)
        #expect(tab.groupID == nil)
        #expect(!tab.isDormant)
    }

    /// A dimmed row survives a relaunch, which is the whole reason it is a
    /// column rather than something inferred from "has no web view": every tab
    /// has no web view after a relaunch, and only one of them is one press from
    /// being let go.
    @Test("a closed saved tab comes back still closed")
    func dormancyPersists() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        var tab = Tab(spaceID: space.id, kind: .pinned, url: URL(string: "https://example.com")!)
        tab.isDormant = true
        try await store.upsert(tab)

        #expect(try await store.tabs(inSpace: space.id, includeArchived: false).first?.isDormant == true)
    }

    /// Groups and the loose tabs around them share one run of indices, so
    /// renumbering the groups alone would close the gaps the tabs are standing
    /// in. The read only breaks ties; `TabList` renumbers both together.
    @Test("the read orders by index and does not renumber")
    func theReadDoesNotRenumber() async throws {
        let store = try makeTemporaryStore()
        let space = try await seededSpace(store)
        try await store.upsert(TabGroup(spaceID: space.id, name: "Later", order: 4))
        try await store.upsert(TabGroup(spaceID: space.id, name: "Sooner", order: 1))

        let groups = try await store.groups(inSpace: space.id)
        #expect(groups.map(\.name) == ["Sooner", "Later"])
        #expect(groups.map(\.order) == [1, 4])
    }

    private func seededSpace(_ store: BrowserStore) async throws -> Space {
        try await store.seedIfEmpty()
        return try #require(try await store.spaces().first)
    }
}
