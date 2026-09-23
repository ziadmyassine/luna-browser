//
//  TabList.swift
//  Luna
//
//  The coordinator's tab storage: every Space's ordered tabs and groups, and the
//  rules that keep them ordered. Split out of `BrowserSession` because it is a
//  data structure rather than policy — it decides nothing about web views,
//  persistence or selection, which is why it can be tested on its own. The slot
//  machinery §3.4b's groups need is next door in `TabList+Slots.swift`.
//
//  The invariant, which `BrowserSession` and the whole sidebar depend on:
//  a Space's tabs are sorted essential → pinned → today, and inside each of the
//  last two the order is the one §3.4 draws — the section's slots, with a
//  group's tabs inline under it.
//
//  ## `order` counts three different things (§3.4b)
//
//  A section's **slots** are its loose tabs and its groups together, sharing one
//  run of indices, because a group can stand between two loose tabs. So:
//
//    · a loose tab's `order` is its slot in `(space, kind)`;
//    · a group's `order` is its slot in the same run;
//    · a grouped tab's `order` is its place among that group's members.
//
//  Each run is dense and unique, which is what makes a drop index mean one
//  thing and what makes a restored session come back the way it was left.
//
//  ## Favorites are per Profile, not per Space (spec §2, D-S2)
//
//  One more exception: `.essential` is numbered and resolved across every Space
//  that shares a Profile, because a Favorite is a logged-in app tile and a tile
//  that opens in a Space whose cookie jar never saw that login is a broken tile.
//  Arc keys its Favorites container by profile — `topAppsContainerIDs` is a flat
//  profile → container pair in its own `StorableSidebar.json` — and Luna's was the
//  same shape until §9's `v7`. A Space owns its cookie jar now and nothing else
//  does, so the tier that belonged to the jar belongs to the Space: everything
//  here is per-Space, and there is no second key to resolve.
//
//  So the storage stays keyed by Space (an `.essential` row keeps the home Space
//  it was created in, which is what the `tabs.spaceID` foreign key cascades on)
//  and the resolution is keyed by Profile: `self[spaceID]` returns that Space's
//  saved and today tabs plus the Profile's Favorites. `setProfiles` is how the
//  list is told which Spaces share one; with no map it degrades to the old
//  per-Space behaviour rather than losing tabs.
//

import BrowserKit
import Foundation

/// What a mutation touched, for the caller to persist.
///
/// It carries groups as well as tabs because §3.4b interleaves them: moving one
/// loose tab renumbers every slot after it, and some of those slots are groups.
/// A `[Tab]` return would have left a group's `order` behind on disk, and the
/// list would have come back in a different arrangement from the one on screen.
struct TabListWrites: Sendable, Equatable {
    var tabs: [Tab] = []
    var groups: [TabGroup] = []

    var isEmpty: Bool { tabs.isEmpty && groups.isEmpty }

    static func += (lhs: inout TabListWrites, rhs: TabListWrites) {
        lhs.tabs += rhs.tabs
        lhs.groups += rhs.groups
    }
}

struct TabList: Sendable {

    // Internal rather than private: `TabList+Slots.swift` is the other half of
    // this type and Swift's `private` is file-scoped.
    var bySpace: [UUID: [Tab]]
    var groupsBySpace: [UUID: [TabGroup]]
    /// Space → Profile. Only Favorites care, but they care everywhere.
    init(_ bySpace: [UUID: [Tab]] = [:], groups: [UUID: [TabGroup]] = [:]) {
        self.bySpace = bySpace.mapValues(Self.sorted)
        groupsBySpace = groups
    }

    /// The Space's own saved and today tabs in the order §3.4 draws them — a
    /// group's members inline under it — plus its Profile's Favorites in front.
    subscript(spaceID: UUID) -> [Tab] {
        var result = favorites(inSpace: spaceID)
        for kind in Self.listedKinds {
            for slot in slots(inSpace: spaceID, kind: kind) {
                switch slot {
                case let .tab(tab): result.append(tab)
                case let .group(group): result += members(ofGroup: group.id)
                }
            }
        }
        return result
    }

    var spaceIDs: [UUID] { Array(bySpace.keys) }

    func tab(_ id: UUID) -> Tab? {
        for list in bySpace.values where list.contains(where: { $0.id == id }) {
            return list.first { $0.id == id }
        }
        return nil
    }

    /// The tab's position within the run its `order` counts — its group's
    /// members, its section's slots, or the whole Profile's Favorites.
    func indexInSection(of id: UUID) -> Int? {
        guard let tab = tab(id) else { return nil }
        if tab.kind == .essential {
            return favorites(inSpace: tab.spaceID).firstIndex { $0.id == id }
        }
        if let groupID = tab.groupID {
            return members(ofGroup: groupID).firstIndex { $0.id == id }
        }
        return slots(inSpace: tab.spaceID, kind: tab.kind).firstIndex { $0.tabID == id }
    }

    /// The index a tab opening now would take at the end of its run.
    func nextOrder(kind: TabKind, in spaceID: UUID) -> Int {
        kind == .essential
            ? favorites(inSpace: spaceID).count
            : slots(inSpace: spaceID, kind: kind).count
    }

    /// Where a tab that is being opened now belongs in its section — the
    /// `index` to hand `insert(_:at:)`.
    ///
    /// Today's tabs stack newest-first. The list is a record of what you
    /// are doing, read from the top, and a new tab appended to the bottom of a
    /// long day's browsing opens off the end of the scroll — the one tab you
    /// definitely want to see is the one you cannot. Saved rows and Favorites
    /// are the opposite: those are slots the user placed deliberately, so a new
    /// one joins the end rather than pushing the arrangement down.
    ///
    /// - Parameter newestFirst: false under §4's top bar, where the list is
    ///   read left to right and a new tab opens at the right-hand end, beside
    ///   the tabs already open — the place every tab bar opens one. First on
    ///   the bar was the far left, away from everything just opened.
    static func openIndex(for kind: TabKind, newestFirst: Bool = true) -> Int? {
        kind == .today && newestFirst ? 0 : nil
    }

    // MARK: - Favorites (§2)

    /// Every Favorite in a Space, ordered — §3.3's tier itself. Capped by
    /// `BrowserSession.favoritesCap`, which is policy and therefore not
    /// enforced here.
    ///
    /// It was a Profile's tier, pooled across every Space sharing one, until
    /// §9's `v7` gave each Space its own jar. A Favorite is a logged-in app
    /// tile and it still belongs to the jar that holds the login; there is
    /// simply nothing between the Space and its jar any more.
    func favorites(inSpace spaceID: UUID) -> [Tab] {
        own(spaceID)
            .filter { $0.kind == .essential }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    /// Adds an empty Space so `switchSpace` has somewhere to land.
    mutating func addSpace(_ spaceID: UUID) {
        bySpace[spaceID] = []
        groupsBySpace[spaceID] = []
    }

    mutating func removeSpace(_ spaceID: UUID) {
        bySpace[spaceID] = nil
        groupsBySpace[spaceID] = nil
    }

    /// Replaces a tab in place. Silently does nothing if it is gone — the tab
    /// may have been archived while a web view was still reporting on it.
    mutating func update(_ tab: Tab) {
        guard let index = bySpace[tab.spaceID]?.firstIndex(where: { $0.id == tab.id }) else { return }
        bySpace[tab.spaceID]?[index] = tab
    }

    // MARK: - Moving tabs

    /// Inserts into whichever run `tab` belongs to — its group's members if it
    /// carries a `groupID`, the Profile's Favorites if it is `.essential`, else
    /// its section's slots — at `index`, or at the end of it.
    ///
    /// A grouped tab takes its group's `kind` and Space on the way in, so
    /// "is this saved" has one answer wherever it is asked (§3.4b).
    @discardableResult
    mutating func insert(_ tab: Tab, at index: Int? = nil) -> TabListWrites {
        // Out of wherever it is first. Every caller that moves a tab already
        // removes it, but a tab arriving twice is two rows with one id — the
        // one failure this structure cannot recover from — and the second
        // removal costs a filter over one section.
        var writes = self.tab(tab.id) == nil ? TabListWrites() : remove(tab.id)
        writes += place(tab, at: index)
        return writes
    }

    private mutating func place(_ tab: Tab, at index: Int?) -> TabListWrites {
        if tab.kind == .essential {
            var favorites = favorites(inSpace: tab.spaceID).filter { $0.id != tab.id }
            favorites.insert(tab, at: Self.clamp(index, to: favorites.count))
            return TabListWrites(tabs: apply(favorites, inSpace: tab.spaceID))
        }
        if let groupID = tab.groupID, let group = group(groupID) {
            var members = members(ofGroup: groupID).filter { $0.id != tab.id }
            members.insert(tab, at: Self.clamp(index, to: members.count))
            return apply(members, ofGroup: group)
        }
        var loose = tab
        loose.groupID = nil
        var slots = slots(inSpace: loose.spaceID, kind: loose.kind).filter { $0.tabID != loose.id }
        slots.insert(.tab(loose), at: Self.clamp(index, to: slots.count))
        return apply(slots, inSpace: loose.spaceID, kind: loose.kind)
    }

    /// Takes a tab out of whatever run it is in, closing the gap behind it.
    @discardableResult
    mutating func remove(_ id: UUID) -> TabListWrites {
        guard let existing = tab(id) else { return TabListWrites() }
        if existing.kind == .essential {
            return TabListWrites(tabs: apply(
                favorites(inSpace: existing.spaceID).filter { $0.id != id },
                inSpace: existing.spaceID
            ))
        }
        if let groupID = existing.groupID, let group = group(groupID) {
            return apply(members(ofGroup: groupID).filter { $0.id != id }, ofGroup: group)
        }
        let remaining = slots(inSpace: existing.spaceID, kind: existing.kind).filter { $0.tabID != id }
        return apply(remaining, inSpace: existing.spaceID, kind: existing.kind)
    }

    // MARK: - Storage

    /// What is actually stored for a Space — its own rows, Favorites included.
    /// Every mutation works on this; only reads go through `self[spaceID]`.
    func own(_ spaceID: UUID) -> [Tab] { bySpace[spaceID] ?? [] }

    /// Writes a Space's Favorites back, renumbered `0..<n`.
    /// - Returns: every Favorite written, for the caller to persist.
    private mutating func apply(_ favorites: [Tab], inSpace spaceID: UUID) -> [Tab] {
        bySpace[spaceID]?.removeAll { $0.kind == .essential }
        var written: [Tab] = []
        written.reserveCapacity(favorites.count)
        for (position, favorite) in favorites.enumerated() {
            var favorite = favorite
            favorite.kind = .essential
            favorite.order = position
            favorite.spaceID = spaceID
            // A tile is one tab in one slot; there is nothing in §3.3's grid for
            // a group to be, so carrying one up there leaves it behind (§3.4b).
            favorite.groupID = nil
            favorite.isDormant = false
            bySpace[spaceID, default: []].append(favorite)
            written.append(favorite)
        }
        bySpace[spaceID] = Self.sorted(own(spaceID))
        return written
    }

    static func clamp(_ index: Int?, to count: Int) -> Int {
        guard let index else { return count }
        return Swift.min(Swift.max(index, 0), count)
    }

    /// The section order of §3.4's list, and the only place it is spelled out.
    static let kindOrder: [TabKind] = [.essential, .pinned, .today]

    /// The two that are rows rather than tiles — §3.4b's saved tier and the
    /// tabs of the day, in the order the column draws them.
    static let listedKinds: [TabKind] = [.pinned, .today]

    static func rank(_ kind: TabKind) -> Int {
        kindOrder.firstIndex(of: kind) ?? kindOrder.count
    }

    /// Storage order, for rows arriving from SQLite and for keeping the stored
    /// array tidy. It is not the display order and must not be read as one: a
    /// group's member and a loose tab can hold the same `order`, because the two
    /// count different runs. `slots(inSpace:kind:)` is the display order.
    static func sorted(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            let ranks = (rank(lhs.kind), rank(rhs.kind))
            guard ranks.0 == ranks.1 else { return ranks.0 < ranks.1 }
            guard lhs.order == rhs.order else { return lhs.order < rhs.order }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
