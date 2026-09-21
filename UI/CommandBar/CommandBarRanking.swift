//
//  CommandBarRanking.swift
//  Luna
//
//  §9.3, and nothing else. Pure functions over value types: given a query and a
//  snapshot of every local source, produce the ordered, deduped list §9.2 asks
//  for. No AppKit, no actor, no I/O — so `CommandBarRankingTests` can hand-compute
//  an order and assert it, exactly the way `FrecencyRankingTests` does.
//
//  Frecency is not reimplemented here. `BrowserStore` computes §9.3's
//  `Σ (visitTypeWeight × recencyWeight)` over each place's ten most recent
//  visits, in SQL, with its own tests; this file consumes `HistoryHit.score`
//  and never second-guesses it. What it adds is the half the store cannot see:
//  tier order across sources, dedupe, and adaptive input history.
//
//  §9.7 is why this is pure. `merge` runs synchronously on the main actor
//  inside `controlTextDidChange`, over arrays already in memory, so local
//  results are on screen in the same frame as the keystroke. The store query is
//  the only asynchronous part and merges in afterwards.
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
///
/// One Space's, all of it. The bar is opened from inside a Space and answers
/// with that Space's things — its tabs, its archive, its history, its lessons —
/// because the Space is the cookie jar (§9) and a row from the other one is a
/// page signed in as somebody else.
struct CommandBarSources: Sendable {
    /// The active Space's tabs, archived ones included — they are the
    /// same rows (§11.1: `archive` is a view over `tabs`, not a second table).
    var tabs: [Tab] = []
    var adaptive: [AdaptiveEntry] = []
    /// Filled by the asynchronous `BrowserStore.searchHistory` pass, empty on the
    /// synchronous one. Already scoped to the Space by the query.
    var history: [HistoryHit] = []
    var commands: [AppCommand] = AppCommand.allCases
    /// §3.4's suggestions, already fetched and parsed by
    /// `Features/Search/SearchSuggestions`. Strings, not URLs: the engine
    /// template turns them into one here, exactly as it does for a typed query,
    /// so a suggestion cannot carry a destination Luna did not build.
    var suggestions: [String] = []
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
    /// merge may only add. Everything already on screen keeps its contents and
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
        let hasDirect = rows.contains { $0.source == .directURL }
        if let search = searchRow(query: query, hasDirectURL: hasDirect) {
            rows.append(search)
        }
        rows.append(contentsOf: suggestionRows(query: query, sources: sources))

        return Array(dedupe(order(rows)).prefix(limit))
    }

    /// §9.4's completion: the top URL-bearing row, if what the user typed is a
    /// prefix of its display form. Returns the whole completion; the field
    /// selects the part beyond `query`.
    ///
    /// Only the top row: autofilling from row 4 would put text in the field
    /// that nothing on screen is highlighting.
    ///
    /// `query` is used untrimmed, because the caller sets the field's text to
    /// what comes back and selects everything past `query.count`, so trimming
    /// would shift that selection by the whitespace. Whitespace anywhere in the
    /// query means it is a search rather than an address, so there is nothing
    /// to complete — which is what makes the untrimmed comparison safe.
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
    /// the user is still on the way to typing it, so learning "gh" → the repo
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

    /// The Space's open tabs (§9.2), plus its archive — which is the same rows
    /// with an `archivedAt` (§11.1).
    private static func tabRows(tokens: [String], sources: CommandBarSources) -> [CommandBarResult] {
        sources.tabs.compactMap { tab -> CommandBarResult? in
            // §3.4a: a renamed tab is found and shown under the name the user gave it.
            // Its own title is deliberately not also in the haystack — a tab you renamed
            // "Invoices" should not keep answering to whatever the page calls itself.
            let haystack = "\(tab.listTitle) \(CommandBarURL.displayForm(of: tab.url))"
            guard matches(tokens, haystack) else { return nil }
            let archived = tab.archivedAt != nil
            return CommandBarResult(
                source: archived ? .archive : .openTab,
                title: tab.listTitle.isEmpty ? CommandBarURL.displayForm(of: tab.url) : tab.listTitle,
                subtitle: CommandBarURL.displayForm(of: tab.url),
                action: archived ? .unarchiveTab(tab.id) : .activateTab(tab.id),
                url: tab.url,
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
        // `url:` is deliberately left nil while the action carries the URL: a
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

    /// §3.4's suggestions as rows, in the order the engine returned them —
    /// which is its ranking, and re-sorting it here would be Luna second-
    /// guessing the only party that has seen more than one user's query.
    /// `score` counts down so `order(_:)` preserves that within the tier.
    ///
    /// The engine's echo of the query is dropped: `searchRow` is already that
    /// row, one tier up, and two identical lines is what makes a suggestion
    /// list look broken.
    private static func suggestionRows(query: String, sources: CommandBarSources) -> [CommandBarResult] {
        guard !query.isEmpty else { return [] }
        let typed = query.lowercased()
        let setting = SearchSettings.current
        var rank = 0.0
        return sources.suggestions.compactMap { phrase in
            guard phrase.lowercased() != typed, let url = setting.url(searching: phrase) else { return nil }
            rank -= 1
            return CommandBarResult(
                source: .suggestion,
                title: phrase,
                subtitle: "Search \(setting.engine.title)",
                action: .open(url),
                score: rank,
                symbolName: "magnifyingglass"
            )
        }
    }

    // MARK: - Order and dedupe

    /// §9.3's tier order. `CommandBarSource` is `Comparable` by declaration order,
    /// so the tier lives with the cases rather than in a switch that can drift.
    /// Score only ever breaks ties within a tier — an adaptive `useCount` of 3
    /// and a frecency score of 340 are not the same unit and are never compared.
    private static func order(_ rows: [CommandBarResult]) -> [CommandBarResult] {
        rows.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
    }

    /// §9.2 "merged and deduped". The best-ranked row for a URL wins its place —
    /// but it inherits the open tab's action when one exists, so a page that is
    /// both #1 by adaptive history and already open switches to the live tab
    /// instead of loading a second copy of it (§19.4).
    ///
    /// One row per URL, flatly, because every row on offer is in one Space and
    /// one cookie jar. This used to keep a row per (URL, jar) pair and was the
    /// answer to zen#14371 — the same page open in two Spaces deduped into one
    /// row whose "Switch to tab" teleported you into whichever the loop reached
    /// last. The bar no longer offers the other Space at all, so two jars can no
    /// longer meet in the list and there is nothing left to tell apart.
    private static func dedupe(_ rows: [CommandBarResult]) -> [CommandBarResult] {
        var slot: [String: Int] = [:]
        /// URLs whose kept row already carries a live tab's action.
        var live: Set<String> = []
        var out: [CommandBarResult] = []
        for row in rows {
            let isTab = row.source == .openTab || row.source == .archive
            guard let index = slot[row.id] else {
                slot[row.id] = out.count
                if isTab { live.insert(row.id) }
                out.append(row)
                continue
            }
            guard isTab, !live.contains(row.id) else { continue }
            adopt(row, into: &out[index], marking: &live)
        }
        return out
    }

    /// A history or adaptive row that is also an open tab switches to the live
    /// tab instead of loading a second copy of it (§19.4), keeping its own rank.
    private static func adopt(_ tab: CommandBarResult, into row: inout CommandBarResult, marking live: inout Set<String>) {
        live.insert(row.id)
        row.action = tab.action
        row.symbolName = tab.symbolName
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
}
