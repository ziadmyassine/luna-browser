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
    /// The Profiles those Spaces name (§9 / D-S8). Keyed by `Profile.id`, which
    /// is what `Space.profileID` holds.
    ///
    /// Empty is a supported state and degrades honestly: the rows below still
    /// stay *apart* per Profile — that part is derived from `Space.profileID`
    /// and needs no name — they simply carry the Space's name alone instead of
    /// "Space · Profile". Nothing here invents a label from a UUID.
    var profiles: [UUID: Profile] = [:]
    var adaptive: [AdaptiveEntry] = []
    /// Filled by the asynchronous `BrowserStore.searchHistory` pass, empty on the
    /// synchronous one.
    var history: [HistoryHit] = []
    var commands: [AppCommand] = AppCommand.allCases
    /// §3.4's suggestions, already fetched and parsed by
    /// `Features/Search/SearchSuggestions`. Strings, not URLs: the engine
    /// template turns them into one here, exactly as it does for a typed query,
    /// so a suggestion cannot carry a destination Luna did not build.
    var suggestions: [String] = []
}

/// A row plus the Profile whose cookie jar it belongs to, if any. Only an open
/// or archived tab has one — a history hit, a search or a command is not *in* a
/// Profile. It rides alongside the row rather than inside it: `CommandBarResult`
/// is §9.2's public vocabulary, and the Profile is a ranking concern that is
/// spent by the time the list is built.
private struct RankedRow {
    var result: CommandBarResult
    var profileID: UUID?
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

        var rows: [RankedRow] = []
        rows.append(contentsOf: adaptiveRows(query: query, sources: sources).map(unscoped))
        if let url = CommandBarURL.direct(from: query) {
            rows.append(unscoped(directRow(url)))
        }
        rows.append(contentsOf: tabRows(tokens: tokens, sources: sources))
        rows.append(contentsOf: historyRows(sources: sources).map(unscoped))
        rows.append(contentsOf: commandRows(tokens: tokens, sources: sources).map(unscoped))
        let hasDirect = rows.contains { $0.result.source == .directURL }
        if let search = searchRow(query: query, hasDirectURL: hasDirect) {
            rows.append(unscoped(search))
        }
        rows.append(contentsOf: suggestionRows(query: query, sources: sources).map(unscoped))

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
    private static func tabRows(tokens: [String], sources: CommandBarSources) -> [RankedRow] {
        let qualify = spansSeveralProfiles(sources)
        return sources.tabs.compactMap { tab in
            let haystack = "\(tab.title) \(CommandBarURL.displayForm(of: tab.url))"
            guard matches(tokens, haystack) else { return nil }
            let archived = tab.archivedAt != nil
            let space = sources.spaces[tab.spaceID]
            let result = CommandBarResult(
                source: archived ? .archive : .openTab,
                title: tab.title.isEmpty ? CommandBarURL.displayForm(of: tab.url) : tab.title,
                subtitle: CommandBarURL.displayForm(of: tab.url),
                action: archived ? .unarchiveTab(tab.id) : .activateTab(tab.id),
                url: tab.url,
                badge: space.map { badge(for: $0, sources: sources, qualify: qualify) },
                // Most recently used first within the tier.
                score: (archived ? tab.archivedAt ?? tab.lastActiveAt : tab.lastActiveAt).timeIntervalSinceReferenceDate,
                symbolName: archived ? "archivebox" : "square.on.square"
            )
            return RankedRow(result: result, profileID: space?.profileID)
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
    /// Score only ever breaks ties *within* a tier — an adaptive `useCount` of 3
    /// and a frecency score of 340 are not the same unit and are never compared.
    private static func order(_ rows: [RankedRow]) -> [RankedRow] {
        rows.sorted { left, right in
            let lhs = left.result, rhs = right.result
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
    }

    /// §9.2 "merged and deduped". The best-ranked row for a URL wins its place —
    /// but it inherits the open tab's *action* and Space badge when one exists,
    /// so a page that is both #1 by adaptive history and already open switches to
    /// the live tab instead of loading a second copy of it (§19.4).
    /// **The Profile boundary stops the dedupe, and that is zen#14371's fix.**
    /// The same URL open in two Spaces on two *different* Profiles is two pages,
    /// two logins and two accounts, so it stays two rows. Collapsing them was
    /// worse than the bug it looks like: the second tab silently overwrote the
    /// first row's action, so choosing "Switch to tab" teleported you into
    /// whichever Space the loop reached last.
    ///
    /// Within one Profile nothing changes: the best-ranked row keeps its place
    /// and inherits the open tab's action, badge and glyph exactly as before.
    private static func dedupe(_ rows: [RankedRow]) -> [CommandBarResult] {
        var slot: [String: Int] = [:]
        /// "url + profile" pairs already reachable from some row on screen.
        var reachable: Set<String> = []
        /// URLs whose kept row already carries a live tab's action.
        var live: Set<String> = []
        var out: [CommandBarResult] = []
        for ranked in rows {
            let row = ranked.result
            let isTab = row.source == .openTab || row.source == .archive
            guard let index = slot[row.id] else {
                slot[row.id] = out.count
                if isTab {
                    live.insert(row.id)
                    ranked.profileID.map { reachable.insert(compound(row.id, $0)) }
                }
                out.append(row)
                continue
            }
            guard isTab else { continue }
            // A tab whose Space is unknown cannot be placed in a Profile; treat
            // it as belonging to whichever one already holds this URL rather
            // than minting a second row on a guess.
            guard let profile = ranked.profileID else {
                if !live.contains(row.id) { adopt(row, into: &out[index], marking: &live) }
                continue
            }
            guard !reachable.contains(compound(row.id, profile)) else { continue }
            reachable.insert(compound(row.id, profile))
            if !live.contains(row.id) {
                adopt(row, into: &out[index], marking: &live)
                continue
            }
            // Another Profile has the same page open. Its own row, with its own
            // identity so §9.7's selection can tell the two apart.
            var extra = row
            extra.id = compound(row.id, profile)
            out.append(extra)
        }
        return out
    }

    /// A history or adaptive row that is *also* an open tab switches to the live
    /// tab instead of loading a second copy of it (§19.4), keeping its own rank.
    private static func adopt(_ tab: CommandBarResult, into row: inout CommandBarResult, marking live: inout Set<String>) {
        live.insert(row.id)
        row.action = tab.action
        row.badge = tab.badge
        row.symbolName = tab.symbolName
    }

    /// A row identity that is unique per (URL, Profile). The separator is a unit
    /// separator so it cannot occur inside a normalised URL.
    private static func compound(_ id: String, _ profileID: UUID) -> String {
        "\(id)\u{1F}\(profileID.uuidString)"
    }

    private static func unscoped(_ result: CommandBarResult) -> RankedRow {
        RankedRow(result: result, profileID: nil)
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

    /// True when the tabs on offer come from Spaces on more than one Profile —
    /// the only situation in which a row needs to say whose cookies it is.
    ///
    /// With one Profile the Space badge is already enough, and "Work · Work"
    /// on every row is noise that teaches the user to stop reading the badge.
    private static func spansSeveralProfiles(_ sources: CommandBarSources) -> Bool {
        var seen: Set<UUID> = []
        for tab in sources.tabs {
            guard let profile = sources.spaces[tab.spaceID]?.profileID else { continue }
            seen.insert(profile)
            if seen.count > 1 { return true }
        }
        return false
    }

    /// §9 / D-S8: **the Profile identity must appear wherever tabs from different
    /// Profiles can meet**, and the Space colour is not it — a colour says which
    /// Space, never whose cookie jar. It rides on the badge's `name` rather than
    /// on a new field, so it reaches the visible chip and VoiceOver through the
    /// path that already exists.
    private static func badge(for space: Space, sources: CommandBarSources, qualify: Bool) -> SpaceBadge {
        // §21.2 / UI-SPEC §8: name and symbol travel with the colour, because a
        // Space must be separable without it.
        SpaceBadge(
            name: label(for: space, sources: sources, qualify: qualify),
            colour: space.gradient.start,
            symbolName: space.symbolName
        )
    }

    private static func label(for space: Space, sources: CommandBarSources, qualify: Bool) -> String {
        guard qualify, let profile = sources.profiles[space.profileID] else { return space.name }
        // A Profile named after its Space says nothing twice.
        guard profile.name != space.name else { return space.name }
        return "\(space.name) · \(profile.name)"
    }
}
