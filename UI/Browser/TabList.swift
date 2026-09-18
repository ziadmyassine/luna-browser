//
//  TabList.swift
//  Luna
//
//  The coordinator's tab storage: every Space's ordered tabs, and the rules
//  that keep them ordered. Split out of `BrowserSession` because it is a data
//  structure, not policy — it decides nothing about web views, persistence or
//  selection, which is exactly why it can be reasoned about (and tested) on
//  its own.
//
//  The invariant, which `BrowserSession` and the whole sidebar depend on:
//  **a Space's tabs are sorted essential → pinned → today, each section by
//  `order`, and `order` is dense and unique within (space, kind).** That is
//  what makes `reorderTab(_:to:kind:)`'s index section-relative and what makes
//  a restored session come back in the order the user left it.
//
//  ## Favorites are per Profile, not per Space (spec §2, D-S2)
//
//  One exception to the sentence above, and it is the biggest model change in
//  the Spaces wave: `.essential` is numbered and resolved **across every Space
//  that shares a Profile**, because a Favorite is a logged-in app tile and a
//  tile that opens in a Space whose cookie jar never saw that login is a broken
//  tile. Arc keys its Favorites container by profile — `topAppsContainerIDs` is
//  a flat profile → container pair, read off its own `StorableSidebar.json` —
//  and the owner's decision is the same shape: per-profile favourites,
//  per-space pinned.
//
//  So the storage stays keyed by Space (an `.essential` row keeps the home
//  Space it was created in, which is what the `tabs.spaceID` foreign key
//  cascades on) and the *resolution* is keyed by Profile: `self[spaceID]`
//  returns that Space's pinned and today tabs plus **the Profile's** Favorites.
//  `setProfiles` is how the list is told which Spaces share one; with no map it
//  degrades to the old per-Space behaviour rather than losing tabs.
//

import BrowserKit
import Foundation

struct TabList: Sendable {

    private var bySpace: [UUID: [Tab]]
    /// Space → Profile. Only Favorites care, but they care everywhere.
    private var profileBySpace: [UUID: UUID]

    init(_ bySpace: [UUID: [Tab]] = [:], profiles: [UUID: UUID] = [:]) {
        self.bySpace = bySpace.mapValues(Self.sorted)
        profileBySpace = profiles
    }

    /// The Space's own pinned and today tabs, plus its **Profile's** Favorites.
    subscript(spaceID: UUID) -> [Tab] {
        guard let profile = profileBySpace[spaceID] else {
            // No profile map — a bare `TabList` in a test, or a Space that has
            // not been registered yet. Answer with what is stored rather than
            // silently dropping the Space's Favorites.
            return own(spaceID)
        }
        return Self.sorted(own(spaceID).filter { $0.kind != .essential } + favorites(onProfile: profile))
    }

    var spaceIDs: [UUID] { Array(bySpace.keys) }

    func tab(_ id: UUID) -> Tab? {
        for list in bySpace.values where list.contains(where: { $0.id == id }) {
            return list.first { $0.id == id }
        }
        return nil
    }

    /// The tab's position **within its own section** — which for `.essential`
    /// is its position among the whole Profile's Favorites, because that is the
    /// list the grid renders.
    func indexInSection(of id: UUID) -> Int? {
        guard let tab = tab(id) else { return nil }
        return self[tab.spaceID].filter { $0.kind == tab.kind }.firstIndex { $0.id == id }
    }

    func nextOrder(kind: TabKind, in spaceID: UUID) -> Int {
        (self[spaceID].filter { $0.kind == kind }.map(\.order).max() ?? -1) + 1
    }

    /// Where a tab that is being **opened now** belongs in its section — the
    /// `index` to hand `insert(_:at:)`.
    ///
    /// **Today's tabs stack newest-first.** The list is a record of what you
    /// are doing, read from the top, and a new tab appended to the bottom of a
    /// long day's browsing opens off the end of the scroll — the one tab you
    /// definitely want to see is the one you cannot. Pinned tabs and Favorites
    /// are the opposite: those are slots the user placed deliberately, so a new
    /// one joins the end rather than pushing the arrangement down.
    static func openIndex(for kind: TabKind) -> Int? {
        kind == .today ? 0 : nil
    }

    // MARK: - Profiles (§2)

    /// Every Favorite on a Profile, ordered — the per-Profile tier itself.
    /// Capped by `BrowserSession.favoritesCap`, which is policy and therefore
    /// not enforced here.
    func favorites(onProfile id: UUID) -> [Tab] {
        spaceIDs(onProfile: id)
            .flatMap { own($0) }
            .filter { $0.kind == .essential }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    func profileID(ofSpace spaceID: UUID) -> UUID? { profileBySpace[spaceID] }

    mutating func setProfiles(_ map: [UUID: UUID]) { profileBySpace = map }

    /// Re-points one Space at a Profile. The caller is responsible for what
    /// happens to Favorites homed in that Space — see
    /// `BrowserSession.setProfile(_:forSpace:)`, which re-homes them onto a
    /// surviving Space of the old Profile first.
    mutating func setProfile(_ profileID: UUID, forSpace spaceID: UUID) {
        profileBySpace[spaceID] = profileID
    }

    /// Adds an empty Space so `switchSpace` has somewhere to land.
    mutating func addSpace(_ spaceID: UUID, profileID: UUID? = nil) {
        bySpace[spaceID] = []
        if let profileID { profileBySpace[spaceID] = profileID }
    }

    mutating func removeSpace(_ spaceID: UUID) {
        bySpace[spaceID] = nil
        profileBySpace[spaceID] = nil
    }

    /// Replaces a tab in place. Silently does nothing if it is gone — the tab
    /// may have been archived while a web view was still reporting on it.
    mutating func update(_ tab: Tab) {
        guard let index = bySpace[tab.spaceID]?.firstIndex(where: { $0.id == tab.id }) else { return }
        bySpace[tab.spaceID]?[index] = tab
    }

    /// Inserts into `tab.kind`'s section at `index`, or at the end of it.
    /// - Returns: the renumbered tabs, which the caller must persist. For a
    ///   Favorite that can include tabs homed in *other* Spaces on the same
    ///   Profile, because Favorites are numbered across the Profile.
    @discardableResult
    mutating func insert(_ tab: Tab, at index: Int? = nil) -> [Tab] {
        if tab.kind == .essential, let profile = profileBySpace[tab.spaceID] {
            var favorites = favorites(onProfile: profile).filter { $0.id != tab.id }
            let target = index.map { Swift.min(Swift.max($0, 0), favorites.count) } ?? favorites.count
            favorites.insert(tab, at: target)
            return apply(favorites, onProfile: profile)
        }

        var list = own(tab.spaceID)
        let section = list.indices.filter { list[$0].kind == tab.kind }
        let target: Int
        if let index, index >= 0, index < section.count {
            target = section[index]
        } else {
            target = section.last.map { $0 + 1 } ?? Self.sectionStart(for: tab.kind, in: list)
        }
        list.insert(tab, at: Swift.min(target, list.count))
        return renumber(list, in: tab.spaceID)
    }

    /// - Returns: the renumbered tabs, which the caller must persist.
    @discardableResult
    mutating func remove(_ id: UUID) -> [Tab] {
        guard let existing = tab(id) else { return [] }
        if existing.kind == .essential, let profile = profileBySpace[existing.spaceID] {
            return apply(favorites(onProfile: profile).filter { $0.id != id }, onProfile: profile)
        }
        var list = own(existing.spaceID)
        list.removeAll { $0.id == id }
        return renumber(list, in: existing.spaceID)
    }

    // MARK: - Ordering

    /// What is actually stored for a Space — its own rows, Favorites included,
    /// with no Profile resolution. Every mutation works on this; only reads go
    /// through `self[spaceID]`. Renumbering the *resolved* list would write
    /// another Space's Favorites into this one.
    private func own(_ spaceID: UUID) -> [Tab] { bySpace[spaceID] ?? [] }

    private func spaceIDs(onProfile id: UUID) -> [UUID] {
        // Sorted so the flat-mapped Favorites list is the same on every launch
        // whatever order the dictionary iterates in. `order` decides the
        // arrangement; this only decides how ties break.
        profileBySpace.filter { $0.value == id }.keys.sorted { $0.uuidString < $1.uuidString }
    }

    /// Writes a Profile's Favorites back, renumbered `0..<n` across the Profile
    /// and each one filed under the Space it belongs to.
    /// - Returns: every Favorite written, for the caller to persist.
    private mutating func apply(_ favorites: [Tab], onProfile profile: UUID) -> [Tab] {
        for spaceID in spaceIDs(onProfile: profile) {
            bySpace[spaceID]?.removeAll { $0.kind == .essential }
        }
        var written: [Tab] = []
        written.reserveCapacity(favorites.count)
        for (position, favorite) in favorites.enumerated() {
            var favorite = favorite
            favorite.kind = .essential
            favorite.order = position
            bySpace[favorite.spaceID, default: []].append(favorite)
            written.append(favorite)
        }
        for spaceID in spaceIDs(onProfile: profile) {
            bySpace[spaceID] = Self.sorted(own(spaceID))
        }
        return written
    }

    /// Groups by kind and rewrites `order` to the position each tab now holds.
    ///
    /// **It must not sort by `order`.** `order` is the value being replaced, so
    /// consulting it here would re-sort the array back into the arrangement the
    /// caller just changed — `insert` would place a tab and this would put it
    /// straight back, renumber to the same values, and the whole reorder would
    /// be a silent no-op. `sorted(_:)` is for rows arriving from SQLite, where
    /// `order` is the authority; in here the array's own order is.
    ///
    /// Favorites are the exception, and for the same reason: their `order` is
    /// the Profile's, not this Space's, so renumbering them here would collide
    /// two Spaces' tiles onto the same indices. `apply(_:onProfile:)` owns them.
    private mutating func renumber(_ list: [Tab], in spaceID: UUID) -> [Tab] {
        // Bucketing by kind is a stable partition — `sorted(by:)` is not
        // documented as stable, and a reorder within a section depends on it.
        var sections: [TabKind: [Tab]] = [:]
        for tab in list { sections[tab.kind, default: []].append(tab) }

        var ordered: [Tab] = []
        ordered.reserveCapacity(list.count)
        for kind in Self.kindOrder {
            let section = sections[kind] ?? []
            if kind == .essential, profileBySpace[spaceID] != nil {
                ordered += section.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
                continue
            }
            for (position, tab) in section.enumerated() {
                var tab = tab
                tab.order = position
                ordered.append(tab)
            }
        }
        bySpace[spaceID] = ordered
        return ordered
    }

    /// The section order of §3.4's list, and the only place it is spelled out.
    static let kindOrder: [TabKind] = [.essential, .pinned, .today]

    /// Where a section begins when it is currently empty.
    private static func sectionStart(for kind: TabKind, in list: [Tab]) -> Int {
        list.firstIndex { rank($0.kind) > rank(kind) } ?? list.count
    }

    static func rank(_ kind: TabKind) -> Int {
        kindOrder.firstIndex(of: kind) ?? kindOrder.count
    }

    static func sorted(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            rank(lhs.kind) == rank(rhs.kind)
                ? lhs.order < rhs.order
                : rank(lhs.kind) < rank(rhs.kind)
        }
    }
}
