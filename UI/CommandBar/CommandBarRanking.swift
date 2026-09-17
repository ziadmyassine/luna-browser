//
//  CommandBarRanking.swift
//  Luna
//
//  §9.3, and nothing else. Pure functions over value types: given a query and a
//  snapshot of every local source, produce the ordered, deduped list §9.2 asks
//  for. No AppKit, no actor, no I/O — so `CommandBarRankingTests` can hand-compute
//  an order and assert it, exactly the way `FrecencyRankingTests` does.
//
//  **Frecency is not reimplemented here.** `BrowserStore` already computes
//  §9.3's `Σ (visitTypeWeight × recencyWeight)` over each place's ten most recent
//  visits, in SQL, with its own tests. This file consumes `HistoryHit.score` and
//  never second-guesses it. What it adds is the half the store cannot see: the
//  tier order across sources, dedupe, and adaptive input history.
//
//  **§9.7, the reason this is a pure function.** `merge` runs synchronously on
//  the main actor inside `controlTextDidChange`, over arrays already in memory,
//  so local results are on screen in the same frame as the keystroke. The store
//  query is the only asynchronous part and it merges in afterwards.
//

import BrowserKit
import Foundation

/// One remembered (typed string → chosen URL) pair (§9.3).
struct AdaptiveEntry: Sendable, Hashable {
    /// The string the user had typed at the moment they chose `url`.
    var typed: String
    var url: URL
    /// Grows by `useCount * 0.9 + 1` per use, so it converges on 10.
    var useCount: Double
}

/// Everything local, snapshotted. Held by `CommandBarController` and refreshed on
/// `BrowserSession.onChange`, never rebuilt per keystroke (§9.7).
struct CommandBarSources: Sendable {
    /// Every tab the window knows about, archived ones included — they are the
    /// same rows (§11.1: `archive` is a view over `tabs`, not a second table).
    var tabs: [Tab] = []
    var spaces: [UUID: Space] = [:]
    var adaptive: [AdaptiveEntry] = []
    /// Filled by the asynchronous `BrowserStore.searchHistory` pass, empty on the
    /// synchronous one.
    var history: [HistoryHit] = []
    var commands: [AppCommand] = AppCommand.allCases
}

enum CommandBarRanking {

    /// §9.3's adaptive update: `use_count = use_count * 0.9 + 1`.
    ///
    /// The asymptote §9.3 quotes is the arithmetic, not a clamp — the recurrence's
    /// fixed point is `x = 0.9x + 1`, i.e. exactly 10 — so a count that starts
    /// below 10 approaches it and never passes it. Do not "add" a `min(_, 10)`:
    /// it would be dead code that hides the fact that the formula is self-limiting.
    static func bumped(_ useCount: Double) -> Double {
        useCount * 0.9 + 1
    }

    /// §9.7: "results must never reorder under the user's cursor while they are
    /// moving through them."
    ///
    /// Once the user has taken the highlight off the top row, a late-arriving
    /// merge may only *add*. Everything already on screen keeps its contents and
    /// its position, so the row under the highlight is still the row they were
    /// looking at — which is the whole of the guarantee, and is why the incoming
    /// list's own order is discarded for the rows that are already showing.
    static func appendingWithoutReordering(
        onScreen: [CommandBarResult],
        incoming: [CommandBarResult]
    ) -> [CommandBarResult] {
        let shown = Set(onScreen.map(\.id))
        return onScreen + incoming.filter { !shown.contains($0.id) }
    }

    /// §9.2 merged and deduped, §9.3 ordered.
    static func merge(query rawQuery: String, sources: CommandBarSources, limit: Int) -> [CommandBarResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = query.lowercased().split(separator: " ").map(String.init)

        var rows: [CommandBarResult] = []
        rows.append(contentsOf: adaptiveRows(query: query, sources: sources))
        if let url = CommandBarURL.direct(from: query) {
            rows.append(directRow(url))
        }
        rows.append(contentsOf: tabRows(tokens: tokens, sources: sources))
        rows.append(contentsOf: historyRows(sources: sources))
        rows.append(contentsOf: commandRows(tokens: tokens, sources: sources))
        if let search = searchRow(query: query, hasDirectURL: rows.contains { $0.source == .directURL }) {
            rows.append(search)
        }

        return Array(dedupe(order(rows)).prefix(limit))
    }

    /// §9.4's completion: the top URL-bearing row, if what the user typed is a
    /// prefix of its display form. Returns the *whole* completion; the field
    /// selects the part beyond `query`.
    ///
    /// Only the top row, on purpose. Autofilling from row 4 would put text in the
    /// field that nothing on screen is highlighting.
    ///
    /// `query` is used **untrimmed**, because the caller sets the field's text to
    /// what comes back and selects everything past `query.count`. Trimming here
    /// would shift that selection off by the whitespace. Whitespace anywhere in
    /// the query means it is a search, not an address, so there is nothing to
    /// complete — which is also what makes the untrimmed comparison safe.
    static func autofill(query: String, results: [CommandBarResult]) -> String? {
        guard !query.isEmpty, !query.contains(where: \.isWhitespace),
              let url = results.first?.url
        else { return nil }
        let completion = CommandBarURL.displayForm(of: url)
        guard completion.count > query.count, completion.lowercased().hasPrefix(query.lowercased()) else { return nil }
        // Keep the user's own casing for the part they typed; only the tail is ours.
        return query + completion.dropFirst(query.count)
    }

    // MARK: - Sources

    /// §9.3. Firefox's shape, and the right one: a remembered input matches while
    /// the user is still *on the way to typing it*, so learning "gh" → the repo
    /// pays off from the first keystroke.
    ///
    /// Skipped for an empty query — every remembered string starts with "", so
    /// `⌘T`'s opening list would be the entire adaptive table.
    private static func adaptiveRows(query: String, sources: CommandBarSources) -> [CommandBarResult] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return sources.adaptive
            .filter { $0.typed.lowercased().hasPrefix(needle) }
            .map { entry in
                CommandBarResult(
                    source: .adaptive,
                    title: title(for: entry.url, sources: sources),
                    subtitle: CommandBarURL.displayForm(of: entry.url),
                    action: .open(entry.url),
                    url: entry.url,
                    score: entry.useCount,
                    symbolName: "arrow.up.forward"
                )
            }
    }

    private static func directRow(_ url: URL) -> CommandBarResult {
        CommandBarResult(
            source: .directURL,
            title: CommandBarURL.displayForm(of: url),
            subtitle: url.absoluteString,
            action: .open(url),
            url: url,
            symbolName: "globe"
        )
    }

    /// Open tabs across every Space (§9.2), badged with the Space's colour, plus
    /// the archive — which is the same rows with an `archivedAt` (§11.1).
    private static func tabRows(tokens: [String], sources: CommandBarSources) -> [CommandBarResult] {
        sources.tabs.compactMap { tab in
            let haystack = "\(tab.title) \(CommandBarURL.displayForm(of: tab.url))"
            guard matches(tokens, haystack) else { return nil }
            let archived = tab.archivedAt != nil
            return CommandBarResult(
                source: archived ? .archive : .openTab,
                title: tab.title.isEmpty ? CommandBarURL.displayForm(of: tab.url) : tab.title,
                subtitle: CommandBarURL.displayForm(of: tab.url),
                action: archived ? .unarchiveTab(tab.id) : .activateTab(tab.id),
                url: tab.url,
                badge: sources.spaces[tab.spaceID].map(badge),
                // Most recently used first within the tier.
                score: (archived ? tab.archivedAt ?? tab.lastActiveAt : tab.lastActiveAt).timeIntervalSinceReferenceDate,
                symbolName: archived ? "archivebox" : "square.on.square"
            )
        }
    }

    /// `BrowserStore.searchHistory` has already matched and ranked these; matching
    /// them again here would only disagree with FTS5 about what a word is.
    private static func historyRows(sources: CommandBarSources) -> [CommandBarResult] {
        sources.history.map { hit in
            CommandBarResult(
                source: .history,
                title: hit.title.isEmpty ? CommandBarURL.displayForm(of: hit.url) : hit.title,
                subtitle: CommandBarURL.displayForm(of: hit.url),
                action: .open(hit.url),
                url: hit.url,
                score: hit.score,
                symbolName: "clock"
            )
        }
    }

    /// Commands answer a query, never an empty bar — `⌘T`'s opening list is for
    /// getting somewhere, not for browsing a command index.
    private static func commandRows(tokens: [String], sources: CommandBarSources) -> [CommandBarResult] {
        guard !tokens.isEmpty else { return [] }
        return sources.commands.compactMap { command in
            guard matches(tokens, command.title) else { return nil }
            return CommandBarResult(
                source: .command,
                title: command.title,
                subtitle: "",
                action: .command(command),
                symbolName: command.symbolName
            )
        }
    }

    /// The floor: whatever else happened, a non-empty query can always be
    /// searched. The engine lives in `CommandBarURL.search(for:)`, which §3.2's
    /// pill commits through as well.
    private static func searchRow(query: String, hasDirectURL: Bool) -> CommandBarResult? {
        guard !query.isEmpty, !hasDirectURL, let url = CommandBarURL.search(for: query) else { return nil }
        // `url:` is deliberately left nil while the *action* carries the URL: a
        // search row must not dedupe against a history hit for the same search
        // page, and §9.4 must never autofill the field with a search URL.
        return CommandBarResult(
            source: .search,
            title: query,
            subtitle: "Search \(SearchSettings.current.engine.title)",
            action: .open(url),
            symbolName: "magnifyingglass"
        )
    }

    // MARK: - Order and dedupe

    /// §9.3's tier order. `CommandBarSource` is `Comparable` by declaration order,
    /// so the tier lives with the cases rather than in a switch that can drift.
    /// Score only ever breaks ties *within* a tier — an adaptive `useCount` of 3
    /// and a frecency score of 340 are not the same unit and are never compared.
    private static func order(_ rows: [CommandBarResult]) -> [CommandBarResult] {
        rows.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
    }

    /// §9.2 "merged and deduped". The best-ranked row for a URL wins its place —
    /// but it inherits the open tab's *action* and Space badge when one exists,
    /// so a page that is both #1 by adaptive history and already open switches to
    /// the live tab instead of loading a second copy of it (§19.4).
    private static func dedupe(_ rows: [CommandBarResult]) -> [CommandBarResult] {
        var seen: [String: Int] = [:]
        var out: [CommandBarResult] = []
        for row in rows {
            guard let index = seen[row.id] else {
                seen[row.id] = out.count
                out.append(row)
                continue
            }
            guard row.source == .openTab || row.source == .archive else { continue }
            out[index].action = row.action
            out[index].badge = row.badge
            out[index].symbolName = row.symbolName
        }
        return out
    }

    // MARK: - Matching

    /// Every token has to appear somewhere. Token-AND rather than substring so
    /// "luna todo" finds a tab titled "TODO — luna-browser".
    private static func matches(_ tokens: [String], _ haystack: String) -> Bool {
        guard !tokens.isEmpty else { return true }
        let folded = haystack.lowercased()
        return tokens.allSatisfy(folded.contains)
    }

    /// An adaptive entry stores a URL, not a title. Borrow one from whatever else
    /// knows the page rather than showing a bare URL twice.
    private static func title(for url: URL, sources: CommandBarSources) -> String {
        let key = CommandBarURL.dedupeKey(url)
        if let tab = sources.tabs.first(where: { CommandBarURL.dedupeKey($0.url) == key }), !tab.title.isEmpty {
            return tab.title
        }
        if let hit = sources.history.first(where: { CommandBarURL.dedupeKey($0.url) == key }), !hit.title.isEmpty {
            return hit.title
        }
        return CommandBarURL.displayForm(of: url)
    }

    private static func badge(for space: Space) -> SpaceBadge {
        // §21.2 / UI-SPEC §8: name and symbol travel with the colour, because a
        // Space must be separable without it.
        SpaceBadge(name: space.name, colour: space.gradient.start, symbolName: space.symbolName)
    }
}
