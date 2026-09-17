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

import BrowserKit
import Foundation

struct TabList: Sendable {

    private var bySpace: [UUID: [Tab]]

    init(_ bySpace: [UUID: [Tab]] = [:]) {
        self.bySpace = bySpace.mapValues(Self.sorted)
    }

    subscript(spaceID: UUID) -> [Tab] {
        bySpace[spaceID] ?? []
    }

    var spaceIDs: [UUID] { Array(bySpace.keys) }

    func tab(_ id: UUID) -> Tab? {
        for list in bySpace.values where list.contains(where: { $0.id == id }) {
            return list.first { $0.id == id }
        }
        return nil
    }

    /// The tab's position **within its own section**, which is the index
    /// `BrowserSession.reorderTab` speaks in.
    func indexInSection(of id: UUID) -> Int? {
        guard let tab = tab(id) else { return nil }
        return self[tab.spaceID].filter { $0.kind == tab.kind }.firstIndex { $0.id == id }
    }

    func nextOrder(kind: TabKind, in spaceID: UUID) -> Int {
        (self[spaceID].filter { $0.kind == kind }.map(\.order).max() ?? -1) + 1
    }

    /// Adds an empty Space so `switchSpace` has somewhere to land.
    mutating func addSpace(_ spaceID: UUID) {
        bySpace[spaceID] = []
    }

    mutating func removeSpace(_ spaceID: UUID) {
        bySpace[spaceID] = nil
    }

    /// Replaces a tab in place. Silently does nothing if it is gone — the tab
    /// may have been archived while a web view was still reporting on it.
    mutating func update(_ tab: Tab) {
        guard let index = bySpace[tab.spaceID]?.firstIndex(where: { $0.id == tab.id }) else { return }
        bySpace[tab.spaceID]?[index] = tab
    }

    /// Inserts into `tab.kind`'s section at `index`, or at the end of it.
    /// - Returns: the Space's renumbered tabs, which the caller must persist.
    @discardableResult
    mutating func insert(_ tab: Tab, at index: Int? = nil) -> [Tab] {
        var list = self[tab.spaceID]
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

    /// - Returns: the Space's renumbered tabs, which the caller must persist.
    @discardableResult
    mutating func remove(_ id: UUID) -> [Tab] {
        guard let spaceID = tab(id)?.spaceID else { return [] }
        var list = self[spaceID]
        list.removeAll { $0.id == id }
        return renumber(list, in: spaceID)
    }

    // MARK: - Ordering

    /// Groups by kind and rewrites `order` to the position each tab now holds.
    ///
    /// **It must not sort by `order`.** `order` is the value being replaced, so
    /// consulting it here would re-sort the array back into the arrangement the
    /// caller just changed — `insert` would place a tab and this would put it
    /// straight back, renumber to the same values, and the whole reorder would
    /// be a silent no-op. `sorted(_:)` is for rows arriving from SQLite, where
    /// `order` is the authority; in here the array's own order is.
    private mutating func renumber(_ list: [Tab], in spaceID: UUID) -> [Tab] {
        // Bucketing by kind is a stable partition — `sorted(by:)` is not
        // documented as stable, and a reorder within a section depends on it.
        var sections: [TabKind: [Tab]] = [:]
        for tab in list { sections[tab.kind, default: []].append(tab) }

        var ordered: [Tab] = []
        ordered.reserveCapacity(list.count)
        for kind in Self.kindOrder {
            for (position, tab) in (sections[kind] ?? []).enumerated() {
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
